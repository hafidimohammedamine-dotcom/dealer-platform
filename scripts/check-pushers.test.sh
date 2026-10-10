#!/usr/bin/env bash
# Tests scripts/check-pushers.sh with a throwaway git repo and a stubbed gh that keeps commit statuses in a folder.
set -uo pipefail
SCRIPT="$(cd "$(dirname "$0")" && pwd)/check-pushers.sh"
TMPROOT="${TMPDIR:-/tmp}"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-testlib.sh"
W=$(mktemp -d "$TMPROOT/cp.XXXXXX") || exit 2; trap 'rm -rf "$W"' EXIT
mkdir -p "$W/stub" "$W/statuses"
# gh stub: POST statuses/<sha> appends the description to statuses/<sha>; GET commits/<sha>/statuses prints them as JSON.
cat > "$W/stub/gh" <<'STUB'
#!/usr/bin/env bash
echo "gh $*" >> "$GH_LOG"
[ "${STUB_GH_FAIL:-}" = 1 ] && exit 1
[ "${STUB_GH_GET_FAIL:-}" = 1 ] && [ "$2" = --paginate ] && exit 1
if [ "$1" = api ] && [ "$2" = -X ] && [ "$3" = POST ]; then
  sha=${4##*/}; d=""; for a in "$@"; do case "$a" in description=*) d=${a#description=};; esac; done
  echo "$d" >> "$STATUS_DIR/$sha"; exit 0
fi
if [ "$1" = api ] && [ "$2" = --paginate ]; then
  sha=$(sed -E 's#.*/commits/([0-9a-f]+)/statuses#\1#' <<<"$3")
  [ -f "$STATUS_DIR/$sha" ] && while read -r d; do printf '%s\n' "$d"; done < "$STATUS_DIR/$sha"; exit 0
fi
exit 9
STUB
chmod +x "$W/stub/gh"
R="$W/repo"; mkdir -p "$R"; cd "$R" && git init -q -b main . && git config user.email t@t && git config user.name t
echo a > f && git add f && git commit -qm base && git checkout -qb work && echo b > f && git commit -qam c1 && echo c > f && git commit -qam c2
C1=$(git rev-parse HEAD~1); C2=$(git rev-parse HEAD)
printf '111 founder-one founder\n333 agents-bot agent\n' > "$W/accounts"
KEY=not-a-real-key-not-a-real-key-not-a-real-key   # 32+ characters, low entropy on purpose (secret scanners)
run() { # run <ok|fail> <name> <message> [VAR=value ...] -- <args...>
  local want=$1 name=$2 msg=$3; shift 3; local envs=(); while [ "$1" != -- ]; do envs+=("$1"); shift; done; shift
  out=$(cd "$R" && env PATH="$W/stub:$PATH" GH_LOG="$W/gh.log" STATUS_DIR="$W/statuses" GH_REPO=owner/repo GUARDS_LEDGER_KEY="$KEY" "${envs[@]}" bash "$SCRIPT" "$@" 2>&1); rc=$?
  assert_result "$want" "$rc" "$name" "$msg" "$out"; }

run fail "usage" "usage: check-pushers.sh" -- record main
run fail "unknown subcommand" "usage: check-pushers.sh record|verify" -- bogus main HEAD x
run fail "bad GH_REPO" "bad GH_REPO" GH_REPO="owner/re po" -- record main HEAD 111
run fail "record: non-numeric pusher" "pusher id must be numeric" -- record main HEAD abc
run fail "record: no key" "GUARDS_LEDGER_KEY is missing or shorter than 32" GUARDS_LEDGER_KEY= -- record main HEAD 111
run fail "record: short key" "GUARDS_LEDGER_KEY is missing or shorter than 32" GUARDS_LEDGER_KEY=short -- record main HEAD 111
run fail "bad base ref" "could not list commits" -- record nope HEAD 111
run ok "record: empty range (base == head)" "Recorded 0 new commit(s)" -- record work work 111
out=$(cd "$R" && env PATH="$W/stub:$PATH" GH_LOG="$W/gh.log" STATUS_DIR="$W/statuses" GH_REPO=owner/repo GUARDS_LEDGER_KEY="$KEY" bash "$SCRIPT" verify work work "$W/accounts" 2>&1); rc=$?
[ $rc = 0 ] && [ -z "$out" ] && t PASS "verify: empty range prints nothing" || { t FAIL "verify empty range ($rc)"; echo "$out"; }
run ok "verify before any record: unknown rows" "$C2 - unknown" -- verify main HEAD "$W/accounts"
run ok "record two commits for the founder" "Recorded 2 new commit(s) as pushed by user ID 111." -- record main HEAD 111
check "a status per commit with id and 40-hex mac" bash -c 'grep -qE "^id=111 mac=[0-9a-f]{40}$" "$1/$2" && grep -qE "^id=111 mac=[0-9a-f]{40}$" "$1/$3"' _ "$W/statuses" "$C1" "$C2"
run ok "verify: both founder" "$C1 111 founder" -- verify main HEAD "$W/accounts"
run ok "record again: nothing new" "Recorded 0 new commit(s)" -- record main HEAD 333
check "the agent's later record did not add statuses" bash -c '[ "$(cat "$1/$2" | wc -l)" = 1 ]' _ "$W/statuses" "$C2"
# A forged status (no key) does not verify; the real one still does. A status copied from another commit does not verify.
m1=$(sed -E 's/^id=111 mac=//' "$W/statuses/$C1")
printf 'id=111 mac=%s\nid=111 mac=%s\n' "$(printf 'a%.0s' {1..40})" "$m1" > "$W/statuses/$C2"   # forged first, then a mac from C1
run ok "verify: forged and copied macs are ignored, no valid record left" "$C2 - unknown" -- verify main HEAD "$W/accounts"
run ok "verify: the untouched commit still verifies" "$C1 111 founder" -- verify main HEAD "$W/accounts"
run ok "record fills the commit whose records were forged, as the current pusher (the agent)" "Recorded 1 new commit(s) as pushed by user ID 333." -- record main HEAD 333
run ok "verify: agent role shown" "$C2 333 agent" -- verify main HEAD "$W/accounts"
rm -f "$W/statuses/$C1"; echo "id=999 mac=$(GUARDS_LEDGER_KEY="$KEY" MSG="$C1 999" python3 -I -c 'import hashlib,hmac,os; print(hmac.new(os.environ["GUARDS_LEDGER_KEY"].encode(), os.environ["MSG"].encode(), hashlib.sha256).hexdigest()[:40])')" > "$W/statuses/$C1"
run ok "verify: a valid record for an id outside accounts.txt is 'unknown' role" "$C1 999 unknown" -- verify main HEAD "$W/accounts"
run fail "verify: broken accounts file" "bad line" -- verify main HEAD "$SCRIPT"
run fail "verify: no key" "GUARDS_LEDGER_KEY is missing" GUARDS_LEDGER_KEY= -- verify main HEAD "$W/accounts"
run fail "record: gh fails" "could not read the statuses of" STUB_GH_FAIL=1 -- record main HEAD 111
rm -f "$W/statuses/$C2"; run fail "record: statuses unreadable is an error, not 'no record'" "could not read the statuses of $C2 (GitHub API error)" STUB_GH_GET_FAIL=1 -- record main HEAD 111
check "no status was posted while the API failed" bash -c '[ ! -f "$1/$2" ]' _ "$W/statuses" "$C2"
run fail "verify: statuses unreadable is an error, not 'unknown'" "could not read the statuses of" STUB_GH_GET_FAIL=1 -- verify main HEAD "$W/accounts"
printf '#!/usr/bin/env bash\necho "gh $*" >> "$GH_LOG"; [ "$2" = --paginate ] && exit 0; exit 1\n' > "$W/stub/gh"
run fail "record: posting the status fails" "could not record the pusher of" -- record main HEAD 111
summary
