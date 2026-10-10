#!/usr/bin/env bash
# Tests scripts/check-pushers.sh with a throwaway repository (a bare origin, a clone with several branches, so
# refs/remotes/origin/* exist) and a stubbed gh that keeps commit statuses in a folder.
set -uo pipefail
SCRIPT="$(cd "$(dirname "$0")" && pwd)/check-pushers.sh"
TMPROOT="${TMPDIR:-/tmp}"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-testlib.sh"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
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
# origin: main (base) ; work: c1 c2 on top of main ; other: c1 then o1 (shares c1 with work)
git init -q --bare -b main "$W/origin"; git clone -q "$W/origin" "$W/repo" 2>/dev/null; R="$W/repo"
cd "$R" && git checkout -q -b main 2>/dev/null; git config user.email t@t && git config user.name t
echo a > f && git add f && git commit -qm base && git push -q origin main
git checkout -qb work && echo b > f && git commit -qam c1 && echo c > f && git commit -qam c2 && git push -q origin work
C1=$(git rev-parse HEAD~1); C2=$(git rev-parse HEAD)
git checkout -qb other "$C1" && echo o > o && git add o && git commit -qm o1 && git push -q origin other; O1=$(git rev-parse HEAD)
git checkout -q work; git fetch -q origin
printf '111 founder-one founder\n333 agents-bot agent\n' > "$W/accounts"
KEY=not-a-real-key-not-a-real-key-not-a-real-key   # 32+ characters, low entropy on purpose (secret scanners)
Z=0000000000000000000000000000000000000000
mac() { GUARDS_LEDGER_KEY="$KEY" MSG="$1 $2" python3 -I -c 'import hashlib,hmac,os; print(hmac.new(os.environ["GUARDS_LEDGER_KEY"].encode(), os.environ["MSG"].encode(), hashlib.sha256).hexdigest()[:40])'; }
call() { (cd "$R" && env PATH="$W/stub:$PATH" GH_LOG="$W/gh.log" STATUS_DIR="$W/statuses" GH_REPO=owner/repo GUARDS_LEDGER_KEY="$KEY" bash "$SCRIPT" "$@" 2>&1); }
prints() { local line=$1; shift; call "$@" | grep -xF -- "$line" >/dev/null; }     # prints <exact line> <args...> (pipefail: grep reads all)
mentions() { local text=$1; shift; call "$@" | grep -F -- "$text" >/dev/null; }   # mentions <substring> <args...>
run() { # run <ok|fail> <name> <message> [VAR=value ...] -- <args...>
  local want=$1 name=$2 msg=$3; shift 3; local envs=(); while [ "$1" != -- ]; do envs+=("$1"); shift; done; shift
  out=$(cd "$R" && env PATH="$W/stub:$PATH" GH_LOG="$W/gh.log" STATUS_DIR="$W/statuses" GH_REPO=owner/repo GUARDS_LEDGER_KEY="$KEY" "${envs[@]}" bash "$SCRIPT" "$@" 2>&1); rc=$?
  assert_result "$want" "$rc" "$name" "$msg" "$out"; }

run fail "usage" "usage: check-pushers.sh record" -- record work
run fail "unknown subcommand" "usage: check-pushers.sh record" -- bogus main HEAD x
run fail "bad GH_REPO" "bad GH_REPO" GH_REPO="owner/re po" -- verify main work "$W/accounts"
run fail "record: non-numeric pusher" "pusher id must be numeric" -- record work origin/main "$Z" "$C2" abc
run fail "record: bad ref name" "bad ref name" -- record 'wo rk' origin/main "$Z" "$C2" 111
run fail "record: bad sha" "before/after must be 40-hex" -- record work origin/main "$Z" nope 111
run fail "record: no key" "GUARDS_LEDGER_KEY is missing or shorter than 32" GUARDS_LEDGER_KEY= -- record work origin/main "$Z" "$C2" 111
run fail "record: short key" "GUARDS_LEDGER_KEY is missing or shorter than 32" GUARDS_LEDGER_KEY=short -- record work origin/main "$Z" "$C2" 111
run ok "record: deleted branch records nothing" "branch deleted; nothing to record" -- record work origin/main "$C2" "$Z" 111
run fail "record: pushed commit not in the checkout" "is not in this checkout" -- record work origin/main "$Z" "$(printf 'a%.0s' {1..40})" 111
run fail "verify: bad base ref" "could not list commits" -- verify nope work "$W/accounts"
run ok "verify before any record: unknown rows" "$C2 - unknown" -- verify main work "$W/accounts"
run ok "record: empty range (before == after)" "Recorded 0 new commit(s)" -- record work origin/main "$C2" "$C2" 111
out=$(call verify main main "$W/accounts"); rc=$?; [ $rc = 0 ] && [ -z "$out" ] && t PASS "verify: empty range prints nothing" || { t FAIL "verify empty range ($rc)"; echo "$out"; }
# New branch (before = zeros): everything since main that no other branch has. c1 is also on 'other', so only c2 is recorded.
run ok "record: new branch credits only the commits no other branch has" "Recorded 1 new commit(s) as pushed by user ID 111." -- record work origin/main "$Z" "$C2" 111
check "c2 recorded for the founder, c1 (shared with 'other') left alone" bash -c '[ -f "$1/$2" ] && [ ! -f "$1/$3" ]' _ "$W/statuses" "$C2" "$C1"
run ok "verify: c1 unknown" "$C1 - unknown" -- verify main work "$W/accounts"
check "verify prints c2 as the founder's" prints "$C2 111 founder" verify main work "$W/accounts"
# Fast-forward push: only before..after; c1 is shared with 'other', so still nothing new
run ok "record: fast-forward push, nothing new left" "Recorded 0 new commit(s)" -- record work origin/main "$C1" "$C2" 111
check "the record step says which range it took" mentions "Recording fast-forward $C1..$C2" record work origin/main "$C1" "$C2" 111
# 'other' pushed as a fast-forward from c1: o1 is its own and goes to the agent; c1 stays unknown (shared, and before the push)
run ok "record: o1 on 'other' for the agent" "Recorded 1 new commit(s) as pushed by user ID 333." -- record other origin/main "$C1" "$O1" 333
check "c1 still has no record" bash -c '[ ! -f "$1/$2" ]' _ "$W/statuses" "$C1"
# A force push of 'work' (before not an ancestor): everything since main minus other branches' commits; c2 is already recorded
run ok "record: force push re-credits nothing already recorded" "Recording new branch or force push: everything since origin/main" -- record work origin/main "$O1" "$C2" 333
check "the agent's later record did not add statuses on c2" bash -c '[ "$(wc -l < "$1/$2")" = 1 ]' _ "$W/statuses" "$C2"
# Forged, copied and conflicting records
m2=$(sed -E 's/^id=111 mac=//' "$W/statuses/$C2")
printf 'id=111 mac=%s\nid=111 mac=%s\n' "$(printf 'a%.0s' {1..40})" "$(mac "$C1" 111)" > "$W/statuses/$C2"   # forged, then a mac for another commit
run ok "verify: forged and copied macs are ignored" "$C2 - unknown" -- verify main work "$W/accounts"
printf 'id=111 mac=%s\nid=333 mac=%s\n' "$m2" "$(mac "$C2" 333)" > "$W/statuses/$C2"   # two valid records, two pushers
run ok "verify: two valid records with different ids are unknown (conflict)" "$C2 - unknown (valid records name more than one pusher)" -- verify main work "$W/accounts"
printf 'id=111 mac=%s\nid=111 mac=%s\n' "$m2" "$m2" > "$W/statuses/$C2"   # two valid records, same pusher
check "verify: two valid records for the same id are fine" prints "$C2 111 founder" verify main work "$W/accounts"
printf 'id=999 mac=%s\n' "$(mac "$C1" 999)" > "$W/statuses/$C1"
run ok "verify: a valid record for an id outside accounts.txt is 'unknown' role" "$C1 999 unknown" -- verify main work "$W/accounts"
run fail "verify: broken accounts file" "bad line" -- verify main work "$SCRIPT"
run fail "verify: no key" "GUARDS_LEDGER_KEY is missing" GUARDS_LEDGER_KEY= -- verify main work "$W/accounts"
# API errors are errors, never "no record"
rm -f "$W/statuses/$O1"; run fail "record: statuses unreadable is an error" "could not read the statuses of" STUB_GH_GET_FAIL=1 -- record other origin/main "$C1" "$O1" 333
check "no status was posted while the API failed" bash -c '[ ! -f "$1/$2" ]' _ "$W/statuses" "$O1"
run fail "verify: statuses unreadable is an error, not 'unknown'" "could not read the statuses of" STUB_GH_GET_FAIL=1 -- verify main work "$W/accounts"
run fail "record: gh fails entirely" "could not read the statuses of" STUB_GH_FAIL=1 -- record work origin/main "$Z" "$C2" 111
# A commit that survives only in a PR head (its branch deleted) is never credited to whoever pushes it again
git -C "$R" checkout -qb gone "$O1" && echo g > "$R/g" && git -C "$R" add g && git -C "$R" commit -qm g1 && git -C "$R" push -q origin gone; G1=$(git -C "$R" rev-parse HEAD)
git -C "$R" push -q origin "$G1:refs/pull/5/head" && git -C "$R" push -q origin --delete gone 2>/dev/null
git -C "$R" fetch -q --prune origin '+refs/heads/*:refs/remotes/origin/*' '+refs/pull/*/head:refs/remotes/pull/*'
git -C "$R" checkout -qb founder-copy "$G1" && echo f > "$R/f" && git -C "$R" add f && git -C "$R" commit -qm f1 && git -C "$R" push -q origin founder-copy; F1=$(git -C "$R" rev-parse HEAD); git -C "$R" fetch -q origin
run ok "record: a founder's new branch on top of a PR-only commit credits only the founder's own commit" "Recorded 1 new commit(s) as pushed by user ID 111." -- record founder-copy origin/main "$Z" "$F1" 111
check "the PR-only commit got no record (it is reachable from refs/remotes/pull/5)" bash -c '[ ! -f "$1/$2" ] && [ -f "$1/$3" ]' _ "$W/statuses" "$G1" "$F1"
git -C "$R" checkout -qb lonely "$C2" && echo l > "$R/l" && git -C "$R" add l && git -C "$R" commit -qm l1 && git -C "$R" push -q origin lonely; L1=$(git -C "$R" rev-parse HEAD); git -C "$R" fetch -q origin
printf '#!/usr/bin/env bash\necho "gh $*" >> "$GH_LOG"; [ "$2" = --paginate ] && exit 0; exit 1\n' > "$W/stub/gh"
run fail "record: posting the status fails" "could not record the pusher of" -- record lonely origin/main "$C2" "$L1" 111
summary
