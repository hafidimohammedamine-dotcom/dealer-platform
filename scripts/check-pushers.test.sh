#!/usr/bin/env bash
# Tests scripts/check-pushers.sh with a throwaway repository (a bare origin and a clone with several branches), push event
# files shaped like GitHub's, and a stubbed gh that keeps commit statuses in a folder.
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

# ev <before> <after> <sender-id> [distinct-sha ...] [--all sha ...] [--deleted] [--ref refs/heads/x] [--count n]: a push
# event file like GitHub's ($GITHUB_EVENT_PATH); commits after --all are listed with distinct=false
ev() { python3 -I - "$W/event.json" "$@" <<'PYEOF'
import json, sys
out, a = sys.argv[1], sys.argv[2:]
e = {"ref": "refs/heads/work", "before": a[0], "after": a[1], "sender": {"id": int(a[2]) if a[2].isdigit() else a[2]}, "deleted": False, "commits": []}
mode = True; i = 3
while i < len(a):
    x = a[i]
    if x == "--all": mode = False
    elif x == "--deleted": e["deleted"] = True
    elif x == "--ref": i += 1; e["ref"] = a[i]
    elif x == "--count": i += 1; e["commits"] = [{"id": "f" * 40, "distinct": True}] * int(a[i])
    else: e["commits"].append({"id": x, "distinct": mode})
    i += 1
json.dump(e, open(out, "w"))
PYEOF
echo "$W/event.json"; }
run fail "usage" "usage: check-pushers.sh record" -- record
run fail "unknown subcommand" "usage: check-pushers.sh record" -- bogus main HEAD x
run fail "record: extra arguments" "usage: check-pushers.sh record" -- record "$(ev "$Z" "$C2" 111)" extra
run fail "bad GH_REPO" "bad GH_REPO" GH_REPO="owner/re po" -- verify main work "$W/accounts"
run fail "record: missing event file" "push event file not found" -- record "$W/nope.json"
printf 'not json' > "$W/event.json"; run fail "record: malformed event" "could not read the push event" -- record "$W/event.json"
printf '{"ref":"refs/heads/work"}' > "$W/event.json"; run fail "record: not a push event (no commits list)" "could not read the push event" -- record "$W/event.json"
run fail "record: non-numeric pusher" "pusher id must be numeric" -- record "$(ev "$Z" "$C2" abc "$C2")"
run fail "record: bad ref name" "bad ref name" -- record "$(ev "$Z" "$C2" 111 "$C2" --ref 'refs/heads/wo rk')"
run fail "record: a tag, not a branch" "bad ref name" -- record "$(ev "$Z" "$C2" 111 "$C2" --ref refs/tags/v1)"
run fail "record: bad sha" "before/after must be 40-hex" -- record "$(ev "$Z" nope 111)"
run fail "record: no key" "GUARDS_LEDGER_KEY is missing or shorter than 32" GUARDS_LEDGER_KEY= -- record "$(ev "$Z" "$C2" 111 "$C2")"
run fail "record: short key" "GUARDS_LEDGER_KEY is missing or shorter than 32" GUARDS_LEDGER_KEY=short -- record "$(ev "$Z" "$C2" 111 "$C2")"
run ok "record: deleted branch records nothing" "branch deleted; nothing to record" -- record "$(ev "$C2" "$Z" 111 --deleted)"
run fail "record: pushed commit not in the checkout" "is not in this checkout" -- record "$(ev "$Z" "$(printf 'a%.0s' {1..40})" 111)"
run fail "record: a listed commit that is not on the pushed branch" "the event lists $O1, which is not on the pushed branch" -- record "$(ev "$Z" "$C2" 111 "$O1")"
run fail "record: a bad commit id in the event" "bad commit id in the event" -- record "$(ev "$Z" "$C2" 111 nope)"
run fail "record: GitHub's 2048-commit limit reached" "lists 2048 commits (GitHub's limit): too many to credit safely" -- record "$(ev "$Z" "$C2" 111 --count 2048)"
run fail "verify: bad base ref" "could not list commits" -- verify nope work "$W/accounts"
run ok "verify before any record: unknown rows" "$C2 - unknown" -- verify main work "$W/accounts"
run ok "record: an event with no distinct commit (a re-push of known commits) records nothing" "Recorded 0 new commit(s)" -- record "$(ev "$C1" "$C2" 111 --all "$C2")"
out=$(call verify main main "$W/accounts"); rc=$?; [ $rc = 0 ] && [ -z "$out" ] && t PASS "verify: empty range prints nothing" || { t FAIL "verify empty range ($rc)"; echo "$out"; }
# GitHub lists c2 as distinct (new with this push) and c1 as not (it was pushed before, on 'other'): only c2 is credited
run ok "record: only the commits GitHub lists as distinct are credited" "Recorded 1 new commit(s) as pushed by user ID 111." -- record "$(ev "$Z" "$C2" 111 "$C2" --all "$C1")"
check "c2 recorded for the founder, c1 (not distinct) left alone" bash -c '[ -f "$1/$2" ] && [ ! -f "$1/$3" ]' _ "$W/statuses" "$C2" "$C1"
check "the record step says what it took from the event" mentions "Recording the 1 commit(s) GitHub lists as new to the repository with this push (work: $Z..$C2, 2 listed)" record "$(ev "$Z" "$C2" 111 "$C2" --all "$C1")"
run ok "verify: c1 unknown" "$C1 - unknown" -- verify main work "$W/accounts"
check "verify prints c2 as the founder's" prints "$C2 111 founder" verify main work "$W/accounts"
# 'other' pushed o1 (distinct): the agent's; c1 stays unknown (not distinct, pushed before)
run ok "record: o1 on 'other' for the agent" "Recorded 1 new commit(s) as pushed by user ID 333." -- record "$(ev "$C1" "$O1" 333 "$O1" --ref refs/heads/other)"
check "c1 still has no record" bash -c '[ ! -f "$1/$2" ] && [ -f "$1/$3" ]' _ "$W/statuses" "$C1" "$O1"
# A commit already recorded is never re-credited, even when the event lists it as distinct
run ok "record: an already recorded commit keeps its first record" "Recorded 0 new commit(s)" -- record "$(ev "$O1" "$C2" 333 "$C2")"
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
rm -f "$W/statuses/$O1"; run fail "record: statuses unreadable is an error" "could not read the statuses of" STUB_GH_GET_FAIL=1 -- record "$(ev "$C1" "$O1" 333 "$O1" --ref refs/heads/other)"
check "no status was posted while the API failed" bash -c '[ ! -f "$1/$2" ]' _ "$W/statuses" "$O1"
run fail "verify: statuses unreadable is an error, not 'unknown'" "could not read the statuses of" STUB_GH_GET_FAIL=1 -- verify main work "$W/accounts"
run fail "record: gh fails entirely" "could not read the statuses of" STUB_GH_FAIL=1 -- record "$(ev "$Z" "$C2" 111 "$C2")"
# A commit a founder re-pushes under a new branch name is not in GitHub's list of what is new (measured: a commit pushed
# once is never listed as distinct again, not even after the branch that held it is rewound), so it is never credited
git -C "$R" checkout -qb founder-copy "$O1" && echo f > "$R/f" && git -C "$R" add f && git -C "$R" commit -qm f1 && git -C "$R" push -q origin founder-copy; F1=$(git -C "$R" rev-parse HEAD)
run ok "record: a founder's new branch on top of an older commit credits only what GitHub lists as new" "Recorded 1 new commit(s) as pushed by user ID 111." -- record "$(ev "$Z" "$F1" 111 "$F1" --all "$O1" "$C1" --ref refs/heads/founder-copy)"
check "the older commits got no new record" bash -c '[ "$(wc -l < "$1/$2")" = 1 ] && grep -q "^id=999 " "$1/$2" && [ -f "$1/$3" ] && [ ! -f "$1/$4" ]' _ "$W/statuses" "$C1" "$F1" "$O1"
git -C "$R" checkout -qb lonely "$C2" && echo l > "$R/l" && git -C "$R" add l && git -C "$R" commit -qm l1 && git -C "$R" push -q origin lonely; L1=$(git -C "$R" rev-parse HEAD); git -C "$R" fetch -q origin
printf '#!/usr/bin/env bash\necho "gh $*" >> "$GH_LOG"; [ "$2" = --paginate ] && exit 0; exit 1\n' > "$W/stub/gh"
run fail "record: posting the status fails" "could not record the pusher of" -- record "$(ev "$C2" "$L1" 111 "$L1" --ref refs/heads/lonely)"
summary
