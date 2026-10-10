#!/usr/bin/env bash
# Tests scripts/check-main-push.sh in a throwaway git repo (a bare "origin" plus a clone) with a stubbed gh.
set -uo pipefail
SCRIPT="$(cd "$(dirname "$0")" && pwd)/check-main-push.sh"
TMPROOT="${TMPDIR:-/tmp}"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-testlib.sh"
W=$(mktemp -d "$TMPROOT/mp.XXXXXX") || exit 2; trap 'rm -rf "$W"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null   # the test's local pushes must not pick up proxy/negotiation settings
mkdir -p "$W/nogit"; printf '#!/usr/bin/env bash\ncase "$1" in commit-tree) exit 1;; esac; exec "%s" "$@"\n' "$(command -v git)" > "$W/nogit/git"; chmod +x "$W/nogit/git"
mkdir -p "$W/stub"; write_gh_stub "$W/stub"; cat > "$W/stub/gh-extra" <<'EXTRA'
echo "gh $*" >> "$GH_LOG"
O="${ORIGIN:-}"   # the bare origin: the fallback step's git API calls are answered from it
case "$*" in
  'api repos/owner/repo/git/ref/heads/main --jq .object.sha') git -C "$O" rev-parse refs/heads/main; exit 0;;
  'api repos/owner/repo/git/commits/'*' --jq .tree.sha') [ "${STUB_TREE_RC:-0}" = 0 ] || exit 1; git -C "$O" rev-parse "${2##*/}^{tree}"; exit $?;;
  'api -X POST repos/owner/repo/git/commits -f message='*' -f tree='*' -f parents[]='*' --jq .sha')
    [ "${STUB_MKCOMMIT_RC:-0}" = 0 ] || exit 1; git -C "$O" -c user.name=github-actions -c user.email=bot@x commit-tree "${8#tree=}" -p "${10#parents[]=}" -m "${6#message=}"; exit $?;;
  'api -X PATCH repos/owner/repo/git/refs/heads/main -f sha='*' -F force='*)
    [ "${STUB_REF_RC:-0}" = 0 ] || exit 1; new="${6#sha=}"; cur=$(git -C "$O" rev-parse refs/heads/main)
    [ "$8" = force=true ] || git -C "$O" merge-base --is-ancestor "$cur" "$new" || exit 1   # a non-fast-forward update is refused like GitHub's
    git -C "$O" update-ref refs/heads/main "$new" "$cur"; exit $?;;
  'api repos/owner/repo/compare/'*'...596905e54f7ae8385c90f6d334db5f18a4427e28 --jq .status') ;;   # the floor compare: the shared stub (STUB_REL)
  'api repos/owner/repo/compare/'*' --jq .status')   # any other compare is computed on the origin
    [ "${STUB_CMP_RC:-0}" = 0 ] || exit 1; ab="${2#repos/owner/repo/compare/}"; a="${ab%%...*}"; b="${ab##*...}"
    git -C "$O" cat-file -e "$a" 2>/dev/null && git -C "$O" cat-file -e "$b" 2>/dev/null || exit 1   # an unknown commit is a 404
    if [ "$a" = "$b" ]; then echo identical; elif git -C "$O" merge-base --is-ancestor "$a" "$b" 2>/dev/null; then echo ahead
    elif git -C "$O" merge-base --is-ancestor "$b" "$a" 2>/dev/null; then echo behind; else echo diverged; fi; exit 0;;
esac
case "$1 $2" in
  "workflow disable") [ "$3" = "${STUB_WF_FAIL:-}" ] && exit 1; exit "${STUB_WF_RC:-0}";;
  "issue create") exit "${STUB_ISSUE_RC:-0}";;
  "run list") [ "$4" = agent-manager.yml ] && [ "$6" = in_progress ] && echo "${STUB_RUNNING_ID:-}"; exit 0;;   # one running manager shift
  "run cancel") exit "${STUB_CANCEL_RC:-0}";;
esac
EXTRA
printf '111 founder-one founder\n222 founder-two founder\n333 agents-bot agent\n' > "$W/accounts"
fresh() { # a bare origin with main = base; a clone where the "pushed" commits are made and pushed to origin main
  rm -rf "$W/origin" "$W/clone"; git init -q --bare -b main "$W/origin"
  git clone -q "$W/origin" "$W/clone" 2>/dev/null; cd "$W/clone" && git checkout -q -b main 2>/dev/null
  git config user.email t@t && git config user.name t; echo base > f && git add f && git commit -qm base && git push -q origin main
  BASE=$(git rev-parse HEAD); : > "$W/gh.log"
}
push_commits() { for i in "$@"; do echo "$i" > "f$i" && git add "f$i" && git commit -qm "c$i"; done; git push -q origin main; HEAD=$(git rev-parse HEAD); }
TOK=ghp_test_not_a_real_token   # the job token; never printed (assert_no_token)
run() { # run <ok|fail> <name> <message> <pusher> <before> <after> [VAR=value ...]
  local want=$1 name=$2 msg=$3 pusher=$4 before=$5 after=$6; shift 6
  out=$(cd "$W/clone" && env -u GITHUB_ACTIONS -u GITHUB_REPOSITORY PATH="$W/stub:$PATH" GH_LOG="$W/gh.log" GH_TOKEN="$TOK" GH_REPO=owner/repo GITHUB_RUN_ID=7 GITHUB_RUN_NUMBER=12 "STUB_NUMBERS=$(seq -s " " 1 12)" "$@" bash "$SCRIPT" "$pusher" "$before" "$after" "$W/accounts" 2>&1); rc=$?
  assert_result "$want" "$rc" "$name" "$msg" "$out"; assert_no_token "$name" "$out" "$TOK"; }
Z=0000000000000000000000000000000000000000
same_tree() { cd "$1" && git fetch -q origin && [ "$(git rev-parse "origin/main^{tree}")" = "$(git rev-parse "$2^{tree}")" ]; }   # origin main's tree is exactly <commit>'s

fresh; push_commits 1; run ok "a founder's push is fine" "Push to main by founder 'founder-one' (ID 111): OK." 111 "$BASE" "$HEAD"
check "founder push: nothing undone, nothing disabled, no issue (only the chain check asked for the previous head's runs and the newest run)" bash -c '! grep -qv "gh api repos/owner/repo/actions/workflows/main-guard.yml/runs?" "$1" && grep -q "runs?head_sha=$2" "$1"' _ "$W/gh.log" "$BASE"
# main must still descend from the newest checked head: a force push back to an older, once-checked commit with the
# workflow disabled (no run records the move) is caught on the next push or the hourly run
fresh; push_commits 1; M=$HEAD; (cd "$W/clone" && git push -q --force origin "$BASE:main" && git reset -q --hard "$BASE")
run fail "schedule: main moved back to an older checked commit (the newest successful run is ahead of it)" "main was moved back to an older commit (rolled back $BASE (behind the last checked head $M, compare: behind)" schedule - - STUB_LATEST="$M"
check "rollback: the agents stop, the issue names the move, main untouched" bash -c '[ "$(grep -c "gh workflow disable " "$1")" = 8 ] && grep -q "gh issue create --title SECURITY: main was moved back to an older commit ($2)" "$1" && cd "$3" && git fetch -q origin && [ "$(git rev-parse origin/main)" = "$2" ]' _ "$W/gh.log" "$BASE" "$W/clone"
fresh; push_commits 1; M=$HEAD; (cd "$W/clone" && git push -q --force origin "$BASE:main" && git reset -q --hard "$BASE"); push_commits 2
run fail "a founder's push on top of a rolled-back main: the chain check catches the move" "rolled back $BASE (behind the last checked head $M" 111 "$BASE" "$HEAD" STUB_LATEST="$M"
check "rollback then push: the agents stop" bash -c '[ "$(grep -c "gh workflow disable " "$1")" = 8 ]' _ "$W/gh.log"
fresh; push_commits 1; run ok "a push whose previous tip is the newest checked head passes" "Push to main by founder" 111 "$BASE" "$HEAD" STUB_LATEST="$BASE"
fresh; push_commits 1 2; run ok "a push whose previous tip descends from the newest checked head passes (compare: ahead)" "Push to main by founder" 111 "$(git -C "$W/clone" rev-parse HEAD~1)" "$HEAD" STUB_LATEST="$BASE"
# The hourly run also requires every retained main-guard run to still exist (the agents' token can delete runs, which
# would erase the newest checked head): run numbers are sequential, so a deleted run is a gap before this run's number
fresh; push_commits 1; run ok "schedule: the retained runs are one unbroken sequence up to this run" "Runs: ok main-guard runs #9..#11 are all retained" schedule - - "STUB_NUMBERS=9 10 11 12"
fresh; push_commits 1; run ok "schedule: the first run (nothing earlier retained)" "Runs: ok no earlier main-guard run from #1 is retained (this is run #1)" schedule - - STUB_NUMBERS=1 GITHUB_RUN_NUMBER=1
fresh; push_commits 1; run fail "schedule: every earlier run deleted stops the agents" "deleted main-guard run(s) #1..#11: none is retained before this run #12" schedule - - STUB_NUMBERS=12
fresh; push_commits 1; run ok "schedule: a push run numbered above this one is not a gap" "Runs: ok main-guard runs #9..#11 are all retained" schedule - - "STUB_NUMBERS=9 10 11 12 13"
fresh; push_commits 1; run fail "schedule: a run deleted in the middle stops the agents" "deleted main-guard run(s) between #9 and #11" schedule - - "STUB_NUMBERS=9 11 12"
check "deleted runs: 8 disables and the issue" bash -c '[ "$(grep -c "gh workflow disable " "$1")" = 8 ] && grep -q "gh issue create --title SECURITY: main-guard workflow runs were deleted" "$1"' _ "$W/gh.log"
fresh; push_commits 1; run fail "schedule: the newest runs deleted (a gap before this run) stops the agents" "deleted main-guard run(s) between #9 and this run #12" schedule - - "STUB_NUMBERS=8 9 12"
fresh; push_commits 1; run fail "schedule: the run list fails: an error, nothing stopped" "could not list the main-guard runs" schedule - - STUB_NUMBERS_RC=1
check "run list error: no disable, no issue" bash -c '! grep -q "workflow disable\|issue create" "$1"' _ "$W/gh.log"
fresh; push_commits 1; run fail "a push run does not ask for the run numbers (only the hourly run does)" "restored main to the tree of" 333 "$BASE" "$HEAD" "STUB_NUMBERS=1 12"
check "push run: no paginated run listing" bash -c '! grep -q -- "--paginate" "$1"' _ "$W/gh.log"
fresh; push_commits 1; run fail "the newest-run lookup fails: an error, nothing stopped" "could not read the newest main-guard run" 111 "$BASE" "$HEAD" STUB_LATEST_RC=1
check "lookup error: no disable, no issue" bash -c '! grep -q "workflow disable\|issue create" "$1"' _ "$W/gh.log"
# The chain: the previous push's head must have passed the main guard itself (a [skip ci] push or a cancelled run has none)
fresh; push_commits 1; run fail "a founder's push after an unchecked push: the agents are stopped, an issue opened, nothing reverted" "reached main without passing the main guard (missing $BASE (runs: none))" 111 "$BASE" "$HEAD" STUB_RUNS=
check "unchecked push: 8 workflows disabled, the issue names the commit, main untouched" bash -c 'cd "$1" && git fetch -q origin && [ "$(git rev-list --count origin/main)" = 2 ] && [ "$(grep -c "gh workflow disable " "$2")" = 8 ] && grep -q "gh issue create --title SECURITY: a push to main passed no main-guard run (commit $3)" "$2"' _ "$W/clone" "$W/gh.log" "$BASE"
fresh; push_commits 1; run fail "a cancelled run on the previous head counts as unchecked" "missing $BASE (runs: completed/cancelled)" 111 "$BASE" "$HEAD" STUB_RUNS=completed/cancelled
fresh; push_commits 1; run ok "a previous head older than the guard's floor is fine" "is on the default branch before the main guard existed (floor 596905e54f7ae8385c90f6d334db5f18a4427e28)" 111 "$BASE" "$HEAD" STUB_RUNS= STUB_REL=ahead
fresh; push_commits 1; run ok "a previous head whose run is still going: waited, then passed" "passed the main guard" 111 "$BASE" "$HEAD" "STUB_RUNS=completed/success in_progress/" MAIN_GUARD_WAIT=10
fresh; push_commits 1; run fail "the previous head's runs cannot be listed: an error, not a pass" "could not list the main-guard runs of $BASE" 111 "$BASE" "$HEAD" STUB_RUNS_RC=1
check "API error: nothing disabled, no issue" bash -c '! grep -q "gh workflow disable" "$1" && ! grep -q "gh issue create" "$1"' _ "$W/gh.log"
fresh; push_commits 1; run ok "the first push ever (zero before) has no chain to check" "Push to main by founder" 111 "$Z" "$HEAD" STUB_RUNS=
# The schedule: main's head itself must have passed
fresh; push_commits 1; run ok "schedule: main's head passed" "Scheduled check: main's head $HEAD passed the main guard." schedule - -
fresh; push_commits 1; run fail "schedule: main's head never checked (a [skip ci] push) stops the agents" "commit $HEAD reached main without passing the main guard" schedule - - STUB_RUNS=
check "schedule: issue opened, workflows disabled" bash -c 'grep -q "gh issue create --title SECURITY: a push to main passed no main-guard run" "$1" && [ "$(grep -c "gh workflow disable " "$1")" = 8 ]' _ "$W/gh.log"
# A founder accepts a commit by hand (workflow_dispatch): the status is posted; anyone else, or a commit not on main, is refused
fresh; push_commits 1; run ok "accept: a founder marks a commit on main with the guards/main-guard status" "Accepted: commit $HEAD now carries the guards/main-guard status (founder ID 111)" accept 111 "$HEAD"
check "accept: the status was posted with the founder's ID in the description, nothing else touched" bash -c 'grep -qF "gh api -X POST repos/owner/repo/statuses/$2 -f state=success -f context=guards/main-guard -f description=accepted by founder 111 (main-guard run 7)" "$1" && ! grep -q "workflow disable\|issue create\|runs?head_sha" "$1"' _ "$W/gh.log" "$HEAD"
fresh; push_commits 1; run fail "accept: the agents' account cannot accept (the agents' token can start the workflow by hand)" "only a founder may accept a commit; user ID 333 is not one. Nothing was marked." accept 333 "$HEAD"
check "accept refused: no status posted" bash -c '! grep -q "statuses/" "$1"' _ "$W/gh.log"
fresh; push_commits 1; run fail "accept: an unknown account cannot accept" "user ID 999 is not one" accept 999 "$HEAD"
fresh; push_commits 1; run fail "accept: a commit that is not on main is refused" "is not on main (this checkout); nothing was marked" accept 111 "$(printf 'a%.0s' {1..40})"
fresh; push_commits 1; run fail "accept: a bad sha" "must be a 40-hex sha" accept 111 nope
fresh; push_commits 1; run fail "accept: a non-numeric actor" "the actor id must be numeric" accept me "$HEAD"
fresh; push_commits 1; run fail "accept: the status post fails" "could not post the guards/main-guard status on $HEAD" accept 111 "$HEAD" STUB_MARK_RC=1
fresh; push_commits 1; run fail "accept in Actions: a run started from another branch is refused (that branch's workflow file ran)" "run this workflow from the main branch (this run used 'refs/heads/other'); nothing was marked" accept 111 "$HEAD" GITHUB_ACTIONS=true GITHUB_REPOSITORY=owner/repo GITHUB_REF=refs/heads/other
check "accept off main: no status posted" bash -c '! grep -q "statuses/" "$1"' _ "$W/gh.log"
fresh; push_commits 1; run ok "accept in Actions from main" "Accepted: commit $HEAD" accept 111 "$HEAD" GITHUB_ACTIONS=true GITHUB_REPOSITORY=owner/repo GITHUB_REF=refs/heads/main
# The chain check accepts a previous head that carries the status (the guard's own revert, or a founder's acceptance)
fresh; push_commits 1; run ok "a previous head with no run but the guards/main-guard status passes the chain" "carries the guards/main-guard status" 111 "$BASE" "$HEAD" STUB_RUNS= STUB_MARKS=1
fresh; push_commits 1 2; run fail "an agent's push is undone, the secret-holding workflows cancelled and disabled, an issue opened" "restored main to the tree of $BASE with one undo commit"  333 "$BASE" "$HEAD" STUB_RUNNING_ID=4242
check "the report: one undo commit, cancelled 1, every workflow disabled" grep -qE "with one undo commit \([0-9a-f]{40}\); cancelled 1 running or queued run\(s\); disabled agent-manager.yml review.yml claude.yml agent-daily-report.yml agent-weekly-audit.yml egress-lock-claude.yml pusher-ledger.yml guards.yml \(re-enable them after the review\)" <<<"$out"
check "origin main is one undo commit on top of the push, with exactly the base tree" bash -c 'cd "$1" && git fetch -q origin && [ "$(git rev-list --count origin/main)" = 4 ] && git show origin/main:f | grep -qx base && ! git ls-tree --name-only origin/main | grep -q "^f1$"' _ "$W/clone"
check "same tree as before the push" same_tree "$W/clone" "$BASE"
check "the running shift is cancelled before the disables (both states asked for every workflow)" bash -c 'grep -q "gh run cancel 4242" "$1" && [ "$(grep -c "gh run list --workflow " "$1")" = 16 ] && [ "$(grep -n "gh run cancel 4242" "$1" | cut -d: -f1)" -lt "$(grep -n "gh workflow disable agent-manager.yml" "$1" | cut -d: -f1)" ]' _ "$W/gh.log"
check "every secret-holding workflow disabled and the issue labeled security + blocked" bash -c '[ "$(grep -c "gh workflow disable " "$1")" = 8 ] && grep -q "gh workflow disable review.yml" "$1" && grep -q "gh workflow disable guards.yml" "$1" && grep -q "gh issue create --title SECURITY: non-founder push to main by user ID 333 --label area:security --label blocked --label priority:1" "$1" && grep -q "@founder-one @founder-two" "$1"' _ "$W/gh.log"
check "the undo commit (origin main's new head) was marked with the guards/main-guard status by the job token, once" bash -c 'cd "$1" && grep -qF "gh api -X POST repos/owner/repo/statuses/$(git rev-parse origin/main) -f state=success -f context=guards/main-guard -f description=undo by main-guard run 7" "$2" && [ "$(grep -c "statuses/" "$2")" = 1 ]' _ "$W/clone" "$W/gh.log"
fresh; push_commits 1; run fail "the undo is pushed but cannot be marked: reported, a founder accepts it by hand" "could not be marked with the guards/main-guard status; the next run will flag it, so a founder accepts it (Actions -> Main guard -> Run workflow)" 333 "$BASE" "$HEAD" STUB_MARK_RC=1
check "unmarked undo: still pushed with the base tree, workflows disabled" bash -c 'cd "$1" && git fetch -q origin && [ "$(git rev-list --count origin/main)" = 3 ] && [ "$(grep -c "gh workflow disable " "$2")" = 8 ]' _ "$W/clone" "$W/gh.log"
check "unmarked undo: same tree as before the push" same_tree "$W/clone" "$BASE"
# The undo is one commit with the previous tip's tree, never per-commit reverts: a pushed merge M whose first parent is an
# OLDER main commit (made with commit-tree, any tree, no workflow file) would make `git revert -m 1 M` roll main back to that
# older tree - every founder change since, gone, and the head marked checked. The tree check makes that push a no-op.
fresh; push_commits 1 2; OLD1=$(git -C "$W/clone" rev-parse HEAD~1); BASE2=$HEAD
M=$(cd "$W/clone" && git commit-tree "$BASE2^{tree}" -p "$OLD1" -p "$BASE2" -m "merge with an older first parent" </dev/null) && (cd "$W/clone" && git update-ref refs/heads/main "$M" && git reset -q --hard && git push -q origin main)
run fail "a pushed merge with an older first parent: main gets the previous tip's tree back (not the older parent's)" "restored main to the tree of $BASE2 with one undo commit" 333 "$BASE2" "$M"
check "merge attack: f1 and f2 still there (the previous tip's tree), one status posted" bash -c 'cd "$1" && git fetch -q origin && git ls-tree --name-only origin/main | grep -q "^f2$" && git ls-tree --name-only origin/main | grep -q "^f1$" && [ "$(grep -c "statuses/" "$2")" = 1 ]' _ "$W/clone" "$W/gh.log"
check "merge attack: same tree as before the push" same_tree "$W/clone" "$BASE2"
# A push that changes nothing (the same tree) still gets its undo commit (empty) as the marked head
fresh; push_commits 1; (cd "$W/clone" && git commit -q --allow-empty -m empty && git push -q origin main); HEAD=$(git -C "$W/clone" rev-parse HEAD)
run fail "an empty push is undone with an empty undo commit" "restored main to the tree of $BASE" 333 "$BASE" "$HEAD"
check "empty push: one undo commit on top, marked once" bash -c 'cd "$1" && git fetch -q origin && [ "$(git rev-list --count origin/main)" = 4 ] && [ "$(grep -c "statuses/" "$2")" = 1 ]' _ "$W/clone" "$W/gh.log"
check "empty push: same tree as before" same_tree "$W/clone" "$BASE"
# A re-run (or a later push): main is no longer at the event's head, so nothing is undone (undoing again would undo more)
fresh; push_commits 1; OLD=$HEAD; push_commits 2; run fail "main moved past the pushed head: nothing undone, agents still stopped" "main is no longer at $OLD (a later push, or a re-run of this job); nothing undone" 333 "$BASE" "$OLD"
check "moved main: untouched, no status posted, workflows disabled, issue opened" bash -c 'cd "$1" && git fetch -q origin && [ "$(git rev-list --count origin/main)" = 3 ] && ! grep -q "statuses/" "$2" && [ "$(grep -c "gh workflow disable " "$2")" = 8 ] && grep -q "gh issue create" "$2" && grep -q "nothing undone" "$2"' _ "$W/clone" "$W/gh.log"
fresh; push_commits 1; run fail "an unknown account's push" "not in $W/accounts, role unknown" 999 "$BASE" "$HEAD"
# Inside Actions the test overrides are ignored (a step that ran before could have written $GITHUB_ENV)
fresh; push_commits 1; run fail "in Actions: MAIN_GUARD_WORKFLOWS cannot shrink the stop list" "disabled agent-manager.yml review.yml claude.yml agent-daily-report.yml agent-weekly-audit.yml egress-lock-claude.yml pusher-ledger.yml guards.yml" 333 "$BASE" "$HEAD" GITHUB_ACTIONS=true GITHUB_REPOSITORY=owner/repo MAIN_GUARD_WORKFLOWS=review.yml
check "in Actions: all 8 workflows disabled" bash -c '[ "$(grep -c "gh workflow disable " "$1")" = 8 ]' _ "$W/gh.log"
fresh; push_commits 1; echo 0 > "$W/count"; run ok "in Actions: MAIN_GUARD_WAIT=0 is ignored (the fixed wait lets a run still going finish)" "passed the main guard" 111 "$BASE" "$HEAD" GITHUB_ACTIONS=true GITHUB_REPOSITORY=owner/repo MAIN_GUARD_WAIT=0 STUB_RUNS=queued/ STUB_RUNS_LATER=completed/success STUB_COUNT="$W/count"
fresh; push_commits 1; run fail "a new-branch push (before = zeros): nothing to restore, the founders reset main" "main was created by this push; there is no previous tip to restore" 333 "$Z" "$HEAD"
check "new branch: untouched, unmarked, workflows disabled" bash -c 'cd "$1" && git fetch -q origin && [ "$(git rev-list --count origin/main)" = 2 ] && ! grep -q "statuses/" "$2" && [ "$(grep -c "gh workflow disable " "$2")" = 8 ]' _ "$W/clone" "$W/gh.log"
fresh; cd "$W/clone" && git checkout -q -b side && echo s > s && git add s && git commit -qm side && git checkout -q main && git merge -q --no-ff -m merge side && git push -q origin main && HEAD=$(git rev-parse HEAD)
run fail "a pushed merge is undone like any push" "restored main to the tree of $BASE with one undo commit" 333 "$BASE" "$HEAD"
check "the merge's file is gone from origin main" bash -c 'cd "$1" && git fetch -q origin && ! git ls-tree --name-only origin/main | grep -q "^s$"' _ "$W/clone"
check "merge push: same tree as before" same_tree "$W/clone" "$BASE"
# A force push: main is put back to the previous tip (force-with-lease on the pushed tip), nothing is reverted.
fresh; push_commits 1; OLD=$HEAD; cd "$W/clone" && git commit -q --amend -m rewritten && git push -q --force origin main && HEAD=$(git rev-parse HEAD)
run fail "a force push by the agent is undone" "restored main to $OLD after a force push" 333 "$OLD" "$HEAD"
check "origin main is the previous tip again" bash -c 'cd "$1" && git fetch -q origin && [ "$(git rev-parse origin/main)" = "$2" ]' _ "$W/clone" "$OLD"
fresh; push_commits 1; OLD=$HEAD; cd "$W/clone" && git commit -q --amend -m rewritten && git push -q --force origin main && HEAD=$(git rev-parse HEAD)
run fail "a force push whose previous tip never passed the guard: nothing restored (the guard never puts an unchecked commit on main)" "commit $OLD reached main without passing the main guard" 333 "$OLD" "$HEAD" STUB_RUNS=
check "unchecked previous tip: main stays as pushed, agents stopped" bash -c 'cd "$1" && git fetch -q origin && [ "$(git rev-parse origin/main)" = "$2" ] && [ "$(grep -c "gh workflow disable " "$3")" = 8 ]' _ "$W/clone" "$HEAD" "$W/gh.log"
mkdir -p "$W/nopush"; printf '#!/usr/bin/env bash\ncase "$1" in push) exit 1;; esac; exec "%s" "$@"\n' "$(command -v git)" > "$W/nopush/git"; chmod +x "$W/nopush/git"
fresh; push_commits 1; OLD=$HEAD; cd "$W/clone" && git commit -q --amend -m rewritten && git push -q --force origin main && HEAD=$(git rev-parse HEAD)
run fail "a force push that cannot be restored is reported" "main was force-pushed and could not be restored to $OLD" 333 "$OLD" "$HEAD" PATH="$W/nopush:$W/stub:$PATH"
fresh; push_commits 1; run fail "the undo cannot be pushed: reported, manager still disabled, issue still opened" "the undo commit could not be pushed" 333 "$BASE" "$HEAD" PATH="$W/nopush:$W/stub:$PATH"
check "undo push failure: nothing undone in the report, no status, every workflow disabled, issue opened" bash -c 'grep -q "nothing undone" "$1" && ! grep -q "statuses/" "$1" && [ "$(grep -c "gh workflow disable" "$1")" = 8 ] && grep -q "gh issue create" "$1"' _ "$W/gh.log"
fresh; push_commits 1; run fail "disable fails for every workflow: reported, still exits 1" "disabled no workflow(re-enable them after the review); could not disable agent-manager.yml review.yml" 333 "$BASE" "$HEAD" STUB_WF_RC=1
fresh; push_commits 1; run fail "a cancel that fails does not stop the rest" "cancelled 0 running or queued run(s); disabled agent-manager.yml" 333 "$BASE" "$HEAD" STUB_RUNNING_ID=4242 STUB_CANCEL_RC=1
fresh; push_commits 1; run fail "disable fails for one workflow: the others are off, the one is named" "could not disable claude.yml - disable by hand" 333 "$BASE" "$HEAD" STUB_WF_FAIL=claude.yml
fresh; push_commits 1; run fail "issue creation fails: the text goes to the log" "could not open the security issue; founders:" 333 "$BASE" "$HEAD" STUB_ISSUE_RC=1
fresh; push_commits 1; run fail "an unknown previous tip: nothing undone, the founders restore main" "the previous tip $(printf 'a%.0s' {1..40}) is not in this checkout and could not be fetched" 333 "$(printf 'a%.0s' {1..40})" "$HEAD"
fresh; push_commits 1; run fail "the undo commit cannot be made: reported, nothing pushed" "the undo commit could not be made" 333 "$BASE" "$HEAD" PATH="$W/nogit:$W/stub:$PATH"
check "undo failure: nothing pushed, no status, workflows disabled, issue still opened" bash -c 'cd "$1" && git fetch -q origin && [ "$(git rev-list --count origin/main)" = 2 ] && ! grep -q "statuses/" "$2" && [ "$(grep -c "gh workflow disable" "$2")" = 8 ] && grep -q "Left to do" "$2"' _ "$W/clone" "$W/gh.log"
fresh; run fail "non-numeric pusher" "pusher id must be numeric" abc "$BASE" "$BASE"
fresh; run fail "bad sha" "before/after must be 40-hex" 333 "$BASE" nope
fresh; printf 'nonsense\n' > "$W/bad-accounts"; out=$(cd "$W/clone" && env -u GITHUB_ACTIONS -u GITHUB_REPOSITORY PATH="$W/stub:$PATH" GH_LOG="$W/gh.log" GH_REPO=owner/repo bash "$SCRIPT" 333 "$BASE" "$BASE" "$W/bad-accounts" 2>&1); rc=$?
[ $rc = 1 ] && grep -q "bad line 1" <<<"$out" && t PASS "broken accounts file fails closed" || { t FAIL "broken accounts file ($rc)"; echo "$out"; }
out=$(cd "$W/clone" && env -u GITHUB_ACTIONS -u GITHUB_REPOSITORY PATH="$W/stub:$PATH" GH_LOG="$W/gh.log" bash "$SCRIPT" 333 "$BASE" "$BASE" "$W/accounts" 2>&1); rc=$?
[ $rc != 0 ] && grep -q "GH_REPO or GITHUB_REPOSITORY" <<<"$out" && t PASS "GH_REPO required" || t FAIL "GH_REPO required ($rc)"
# main-guard.yml's pin step (id pins) uses .github/pins.txt like every workflow; scripts/check-pins.sh checks it is current.
REPO_ROOT="$(cd "$(dirname "$SCRIPT")/.." && pwd)"
check "the repository's pins (pins.txt and every workflow's PINS_SHA256) are current (the checker verifies them)" bash "$REPO_ROOT/scripts/check-workflows.sh" "$REPO_ROOT"
# The pin-mismatch fallback step, run exactly as written in main-guard.yml against the throwaway repo and the gh stub.
fb_run() { python3 -I -c 'import sys, yaml; d = yaml.safe_load(open(sys.argv[1]))
print(next(s["run"] for s in d["jobs"]["guard"]["steps"] if s.get("name", "").startswith("If the guard could not run")))' "$REPO_ROOT/.github/workflows/main-guard.yml"; }
FB=$(fb_run)
# The step runs from the clone's directory, but uses no checkout: every git API call is answered from the bare origin.
runfb() { # runfb <name> <message> <pusher> <before> <after> [VAR=value ...]   (the step exits 1 on a non-founder push)
  local name=$1 msg=$2 pusher=$3 before=$4 after=$5; shift 5; : > "$W/gh.log"
  out=$(cd "$W/clone" && env -u GITHUB_ACTIONS -u GITHUB_REPOSITORY PATH="$W/stub:$PATH" GH_LOG="$W/gh.log" ORIGIN="$W/origin" GH_TOKEN="$TOK" GH_REPO=owner/repo GITHUB_RUN_ID=7 PUSHER_ID="$pusher" BEFORE="$before" AFTER="$after" FOUNDER_IDS="111 222" FLOOR=596905e54f7ae8385c90f6d334db5f18a4427e28 "$@" bash -c "$FB" 2>&1); rc=$?
  assert_result fail "$rc" "$name" "$msg" "$out"; assert_no_token "$name" "$out" "$TOK"; }
fresh; push_commits 1 2; runfb "fallback: normal push by the agent is undone, runs cancelled, workflows disabled, issue opened" "::error::push to main by user ID 333 changed pinned files or broke the checkout" 333 "$BASE" "$HEAD" STUB_RUNNING_ID=4242
check "fallback: origin main has the base tree back in one undo commit, cancel before disable, 8 disables, issue" bash -c 'cd "$1" && git fetch -q origin && [ "$(git rev-list --count origin/main)" = 4 ] && ! git ls-tree --name-only origin/main | grep -q "^f1$" && grep -q "gh run cancel 4242" "$2" && [ "$(grep -c "gh workflow disable " "$2")" = 8 ] && grep -q "restored main to the tree of $3 with one undo commit" "$2" && grep -q "gh issue create --title SECURITY: push to main changed pinned files or broke the checkout (user ID 333)" "$2" && grep -q "event: 333, $3..$4" "$2"' _ "$W/clone" "$W/gh.log" "$BASE" "$HEAD"
check "fallback: same tree as before the push" same_tree "$W/clone" "$BASE"
check "fallback: the undo commit was marked guards/main-guard by the job token, once" bash -c 'cd "$1" && grep -qF "gh api -X POST repos/owner/repo/statuses/$(git rev-parse origin/main) -f state=success -f context=guards/main-guard -f description=undo by main-guard run 7" "$2" && [ "$(grep -c "statuses/" "$2")" = 1 ]' _ "$W/clone" "$W/gh.log"
fresh; push_commits 1; runfb "fallback: the undo cannot be marked: the issue says a founder accepts it" "changed pinned files" 333 "$BASE" "$HEAD" STUB_MARK_RC=1
check "fallback: unmarked undo reported in the issue, still pushed with the base tree" bash -c 'cd "$1" && git fetch -q origin && [ "$(git rev-list --count origin/main)" = 3 ] && grep -q "could not be marked guards/main-guard: a founder accepts it by running this workflow with its sha" "$2"' _ "$W/clone" "$W/gh.log"
check "fallback: unmarked undo has the base tree" same_tree "$W/clone" "$BASE"
fresh; push_commits 1 2; OLD1=$(git -C "$W/clone" rev-parse HEAD~1); BASE2=$HEAD
M=$(cd "$W/clone" && git commit-tree "$BASE2^{tree}" -p "$OLD1" -p "$BASE2" -m "merge with an older first parent" </dev/null) && (cd "$W/clone" && git update-ref refs/heads/main "$M" && git reset -q --hard && git push -q origin main)
runfb "fallback: a pushed merge with an older first parent gets the previous tip's tree back" "changed pinned files" 333 "$BASE2" "$M"
check "fallback: merge attack: f1 and f2 kept, one status" bash -c 'cd "$1" && git fetch -q origin && git ls-tree --name-only origin/main | grep -q "^f2$" && [ "$(grep -c "statuses/" "$2")" = 1 ]' _ "$W/clone" "$W/gh.log"
check "fallback: merge attack: same tree as before the push" same_tree "$W/clone" "$BASE2"
fresh; push_commits 1; OLD=$HEAD; push_commits 2; runfb "fallback: main moved past the pushed head: nothing undone" "changed pinned files" 333 "$BASE" "$OLD"
check "fallback: moved main untouched, the issue says so" bash -c 'cd "$1" && git fetch -q origin && [ "$(git rev-list --count origin/main)" = 3 ] && grep -q "main is no longer at $3 (a later push, or a re-run of this job); nothing undone" "$2" && ! grep -q "statuses/" "$2"' _ "$W/clone" "$W/gh.log" "$OLD"
for v in STUB_TREE_RC STUB_MKCOMMIT_RC STUB_REF_RC; do
  fresh; push_commits 1; runfb "fallback: the undo cannot be made or pushed ($v): nothing pushed, the founders restore main" "changed pinned files" 333 "$BASE" "$HEAD" "$v=1"
  check "fallback ($v): failure reported, main untouched, no status" bash -c 'cd "$1" && git fetch -q origin && [ "$(git rev-list --count origin/main)" = 2 ] && grep -q "the undo commit could not be made or pushed (see the job log); the founders restore main by hand" "$2" && ! grep -q "statuses/" "$2"' _ "$W/clone" "$W/gh.log"
done
fresh; push_commits 1; runfb "fallback: the compare API fails: nothing undone (never a blind force reset)" "changed pinned files" 333 "$BASE" "$HEAD" STUB_CMP_RC=1
check "fallback: compare failure: main untouched, no ref update, no status" bash -c 'cd "$1" && git fetch -q origin && [ "$(git rev-list --count origin/main)" = 2 ] && grep -q "could not compare $3 with" "$2" && ! grep -q "git/refs/heads/main" "$2" && ! grep -q "statuses/" "$2"' _ "$W/clone" "$W/gh.log" "$BASE"
# The fallback never restores or marks an unchecked previous tip: push A1 with [skip ci] (no run), then A2 touching a pinned
# file seconds later; the fallback runs with BEFORE=A1 and must leave main alone (A1's content would otherwise be laundered).
fresh; push_commits 1; A1=$HEAD; push_commits 2; runfb "fallback: the previous tip never passed the main guard: nothing restored, nothing marked" "changed pinned files" 333 "$A1" "$HEAD" STUB_RUNS=
check "fallback: unchecked previous tip: main untouched, no status, the issue names the tip, every workflow disabled" bash -c 'cd "$1" && git fetch -q origin && [ "$(git rev-list --count origin/main)" = 3 ] && ! grep -q "statuses/" "$2" && ! grep -q "git/refs/heads/main" "$2" && grep -q "the previous tip $3 never passed the main guard (runs: none); nothing restored or marked" "$2" && [ "$(grep -c "gh workflow disable " "$2")" = 8 ]' _ "$W/clone" "$W/gh.log" "$A1"
fresh; push_commits 1; A1=$HEAD; push_commits 2; runfb "fallback: a previous tip with the guards/main-guard status (no run) is restored" "changed pinned files" 333 "$A1" "$HEAD" STUB_RUNS= STUB_MARKS=1
check "fallback: status-checked previous tip: its tree is back, marked once" bash -c 'cd "$1" && git fetch -q origin && [ "$(git rev-list --count origin/main)" = 4 ] && [ "$(grep -c "statuses/" "$2")" = 1 ]' _ "$W/clone" "$W/gh.log"
check "fallback: status-checked previous tip: same tree" same_tree "$W/clone" "$A1"
fresh; push_commits 1; A1=$HEAD; push_commits 2; runfb "fallback: a previous tip older than the floor (compare: ahead) is restored" "changed pinned files" 333 "$A1" "$HEAD" STUB_RUNS= STUB_REL=ahead
check "fallback: floor-checked previous tip: same tree" same_tree "$W/clone" "$A1"
fresh; push_commits 1; M=$HEAD; (cd "$W/clone" && git push -q --force origin "$BASE:main" && git reset -q --hard "$BASE"); push_commits 2
runfb "fallback: a previous tip behind the newest checked head counts as unchecked (a rollback)" "changed pinned files" 333 "$BASE" "$HEAD" STUB_LATEST="$M"
check "fallback: rollback: main untouched, nothing marked, the issue says behind the last checked head" bash -c 'cd "$1" && git fetch -q origin && [ "$(git rev-list --count origin/main)" = 2 ] && ! grep -q "statuses/\|git/refs" "$2" && grep -q "never passed the main guard (runs: completed/success; behind the last checked head $3)" "$2"' _ "$W/clone" "$W/gh.log" "$M"
fresh; push_commits 1; A1=$HEAD; push_commits 2; runfb "fallback: a cancelled run on the previous tip counts as unchecked" "changed pinned files" 333 "$A1" "$HEAD" STUB_RUNS=completed/cancelled
check "fallback: cancelled run: main untouched (runs: completed/cancelled)" bash -c 'cd "$1" && git fetch -q origin && [ "$(git rev-list --count origin/main)" = 3 ] && grep -q "(runs: completed/cancelled); nothing restored or marked" "$2"' _ "$W/clone" "$W/gh.log"
fresh; push_commits 1; A1=$HEAD; push_commits 2; echo 0 > "$W/count"; runfb "fallback: a run still going on the previous tip is waited for" "changed pinned files" 333 "$A1" "$HEAD" STUB_RUNS=in_progress/ STUB_RUNS_LATER=completed/success STUB_COUNT="$W/count"
check "fallback: waited, then restored" same_tree "$W/clone" "$A1"
fresh; push_commits 1; OLD=$HEAD; cd "$W/clone" && git commit -q --amend -m rewritten && git push -q --force origin main && HEAD=$(git rev-parse HEAD)
runfb "fallback: force push restored" "changed pinned files" 333 "$OLD" "$HEAD"
check "fallback: origin main is the previous tip again (force=true), issue says restored, no status (the tip has its own run)" bash -c 'cd "$1" && git fetch -q origin && [ "$(git rev-parse origin/main)" = "$3" ] && grep -q "restored main to $3 after a force push" "$2" && grep -q "git/refs/heads/main -f sha=$3 -F force=true" "$2" && ! grep -q "statuses/" "$2"' _ "$W/clone" "$W/gh.log" "$OLD"
fresh; push_commits 1; OLD=$HEAD; cd "$W/clone" && git commit -q --amend -m rewritten && git push -q --force origin main && HEAD=$(git rev-parse HEAD)
runfb "fallback: a force push whose previous tip never passed the guard: nothing restored" "changed pinned files" 333 "$OLD" "$HEAD" STUB_RUNS=
check "fallback: unchecked force-push tip: main stays as pushed" bash -c 'cd "$1" && git fetch -q origin && [ "$(git rev-parse origin/main)" = "$3" ] && ! grep -q "git/refs/heads/main" "$2"' _ "$W/clone" "$W/gh.log" "$HEAD"
fresh; push_commits 1; OLD=$HEAD; cd "$W/clone" && git commit -q --amend -m rewritten && git push -q --force origin main && HEAD=$(git rev-parse HEAD)
runfb "fallback: a force push that cannot be restored is reported" "changed pinned files" 333 "$OLD" "$HEAD" STUB_REF_RC=1
check "fallback: force restore failure reported" grep -q "main was force-pushed and could not be restored to $OLD; the founders restore it by hand" "$W/gh.log"
fresh; push_commits 1; runfb "fallback: new-branch push (zero before): nothing to restore" "created main with pinned files changed" 333 "$Z" "$HEAD"
check "fallback: zero before: main untouched, no API call on the tree, the issue says there is no previous tip" bash -c 'cd "$1" && git fetch -q origin && [ "$(git rev-list --count origin/main)" = 2 ] && grep -q "no previous tip to restore; the founders reset main by hand" "$2" && ! grep -q "statuses/\|git/" "$2"' _ "$W/clone" "$W/gh.log"
fresh; push_commits 1; runfb "fallback: an unknown before (no run, a 404 on every call about it): nothing undone and says so" "changed pinned files" 333 "$(printf 'a%.0s' {1..40})" "$HEAD" STUB_RUNS=
check "fallback: unknown before: main untouched, never passed, every workflow disabled" bash -c 'cd "$1" && git fetch -q origin && [ "$(git rev-list --count origin/main)" = 2 ] && grep -q "the previous tip $3 never passed the main guard (runs: none); nothing restored or marked" "$2" && ! grep -q "git/refs" "$2" && [ "$(grep -c "gh workflow disable " "$2")" = 8 ]' _ "$W/clone" "$W/gh.log" "$(printf 'a%.0s' {1..40})"
fresh; push_commits 1; runfb "fallback: a founder's push on a checked tip only reports the missing pin update" "a founder's push ($HEAD) changed pinned files without a pin update" 111 "$BASE" "$HEAD"
check "fallback: founder push on a checked tip: nothing undone, nothing disabled, no issue (only the tip's checks asked)" bash -c '! grep -q "workflow disable\|issue create\|git/" "$1"' _ "$W/gh.log"
fresh; push_commits 1; runfb "fallback: a founder's push creating main with pinned files changed: only the message" "created main and changed pinned files" 111 "$Z" "$HEAD"
check "fallback: founder new-branch push: no gh call" bash -c '! grep -q "gh " "$1"' _ "$W/gh.log"
# A founder's push on top of an unchecked tip (a [skip ci] agent push, then a founder merge that also fails the pins): the
# agents stop and the issue names the unchecked tip, nothing is undone
fresh; push_commits 1; A1=$HEAD; push_commits 2; runfb "fallback: a founder's push on an unchecked tip stops the agents" "a founder's push $A1..$HEAD sits on a tip that never passed the main guard" 111 "$A1" "$HEAD" STUB_RUNS=
check "fallback: founder push on an unchecked tip: main untouched, 8 disables, the issue names the tip, nothing marked" bash -c 'cd "$1" && git fetch -q origin && [ "$(git rev-list --count origin/main)" = 3 ] && [ "$(grep -c "gh workflow disable " "$2")" = 8 ] && grep -q "gh issue create --title SECURITY: a push to main passed no main-guard run (commit $3)" "$2" && grep -q "the previous tip $3 never passed the main guard (runs: none); the founder.s push $3..$4 on top of it failed the pin check" "$2" && ! grep -q "statuses/\|git/refs" "$2"' _ "$W/clone" "$W/gh.log" "$A1" "$HEAD"
# The hourly schedule run whose checkout or pin check fails: nothing to undo, but the agents stop and an issue says so
fresh; push_commits 1; runfb "fallback on a schedule run (main's head failed the pins or its checkout): the agents stop" "main's head failed the pin check (or its checkout) on the scheduled run" schedule - - GITHUB_SHA="$HEAD"
check "fallback: schedule: 8 disables, the issue names main's head, no undo, no status" bash -c '[ "$(grep -c "gh workflow disable " "$1")" = 8 ] && grep -q "gh issue create --title SECURITY: main.s head failed the pin check on the scheduled main-guard run" "$1" && grep -q "main.s head ($2) failed the pin check or its checkout on the scheduled run; nothing undone" "$1" && ! grep -q "statuses/\|git/" "$1"' _ "$W/gh.log" "$HEAD"
fresh; push_commits 1; runfb "fallback on a by-hand run: only an error (a founder started it and reads the log)" "the guard could not run on this by-hand run" accept 111 "$HEAD"
check "fallback: accept: no gh call" bash -c '! grep -q "gh " "$1"' _ "$W/gh.log"
# The pin-mismatch fallback in main-guard.yml: runs only on a pin failure, calls no repo script, carries the founders' IDs
# from accounts.txt, and labels the issue area:security + blocked + priority:1.
python3 -I - "$REPO_ROOT" <<'PY' && t PASS "main-guard.yml fallback: condition, no repo script, founder IDs, labels" || t FAIL "main-guard.yml fallback"
import re, sys, yaml
root = sys.argv[1]
wf = yaml.safe_load(open(f"{root}/.github/workflows/main-guard.yml"))
steps = wf["jobs"]["guard"]["steps"]
pins = [s for s in steps if s.get("id") == "pins"][0]
fb = [s for s in steps if s.get("name", "").startswith("If the guard could not run")][0]
assert fb["if"] == "(failure() || cancelled()) && steps.guard.outcome == 'skipped'", fb["if"]   # pins mismatch, a failed or timed-out checkout, a cancel
checkout = [s for s in steps if str(s.get("uses", "")).startswith("actions/checkout@")][0]
assert checkout.get("timeout-minutes"), "the checkout times out on its own, inside the job's limit (a step timeout fails the step; a job timeout cancels the run)"
assert checkout["timeout-minutes"] + 6 <= wf["jobs"]["guard"]["timeout-minutes"], "the fallback keeps at least 6 minutes (its 2-minute wait, the cancels and disables)"
assert not re.search(r"(^|[\s;&|])(bash|sh|source|\.)\s+\S*(scripts/|\./)", fb["run"], re.M), "the fallback must not run repo files"
assert pins["run"] == 'echo "$PINS_SHA256  .github/pins.txt" | sha256sum --check --strict --quiet\nsha256sum --check --strict --quiet .github/pins.txt\nbash scripts/check-pins.sh verify\n', pins["run"]
founders = sorted(l.split()[0] for l in open(f"{root}/.github/accounts.txt") if l.split() and not l.startswith("#") and l.split()[2] == "founder")
assert sorted(fb["env"]["FOUNDER_IDS"].split()) == founders, (fb["env"]["FOUNDER_IDS"], founders)
for lab in ("area:security", "blocked", "priority:1"):
    assert f"--label {lab}" in fb["run"], lab
assert not re.search(r"(^|[\s;&|$(])git\s", fb["run"]), "the fallback uses no checkout: GitHub API calls only"
assert fb["env"]["FLOOR"] == re.search(r"^MAIN_GUARD_FLOOR=([0-9a-f]{40})$", open(f"{root}/scripts/check-github-lib.sh").read(), re.M).group(1)
assert 'select(.event == "push")' in fb["run"] and ".creator.id == 41898282" in fb["run"] and 'compare/$1...$FLOOR' in fb["run"] and 'tip_checked "$BEFORE"' in fb["run"], "the fallback's chain check"
assert "runs?event=push&status=success&per_page=1" in fb["run"] and 'compare/$latest...$1' in fb["run"], "the fallback's lineage check"
assert '-f "parents[]=$AFTER"' in fb["run"] and '-F force=false' in fb["run"], "the undo commit is a fast-forward on the pushed head"
wfs = re.search(r"for w in ([^;\n]+); do", fb["run"]).group(1).split()
src = open(f"{root}/scripts/check-main-push.sh").read()
assert wfs == re.search(r'MAIN_GUARD_WORKFLOWS:-([^}]+)\}', src).group(1).split(), (wfs, "must equal the script's list")
# (that both equal the policy's stop_workflows, and that the policy lists every workflow with a secret or write scope, is
# the workflow checker's rule: scripts/check-workflows.py check_stop_list)
main = [s for s in steps if s.get("id") == "guard"][0]
assert main["name"].startswith("The pusher must be a founder")
assert fb["env"]["PUSHER_ID"] == main["env"]["PUSHER_ID"], "the fallback tells a schedule or by-hand run apart the same way"
assert main["run"].strip() == 'bash scripts/check-main-push.sh "$PUSHER_ID" "$BEFORE" "$AFTER" .github/accounts.txt'
on = wf.get("on", wf.get(True))
assert on["push"] == {"branches": ["main"]} and on["schedule"] == [{"cron": "37 * * * *"}] and set(on) == {"push", "schedule", "workflow_dispatch"}, on
assert on["workflow_dispatch"]["inputs"]["accept_sha"]["required"] is True and on["workflow_dispatch"]["inputs"]["accept_sha"]["type"] == "string"
assert wf["permissions"] == {"contents": "write", "actions": "write", "issues": "write", "statuses": "write"}
env = main["env"]
assert env["PUSHER_ID"] == "${{ github.event_name == 'schedule' && 'schedule' || github.event_name == 'workflow_dispatch' && 'accept' || github.event.sender.id }}", env["PUSHER_ID"]
assert env["BEFORE"] == "${{ github.event_name == 'workflow_dispatch' && github.event.sender.id || github.event.before || '-' }}", env["BEFORE"]
assert env["AFTER"] == "${{ github.event.inputs.accept_sha || github.event.after || '-' }}", env["AFTER"]
assert 'statuses/$undo' in fb["run"] and "-f context=guards/main-guard" in fb["run"], "the fallback marks its undo commit"
assert 'elif [ "$head" != "$AFTER" ]' in fb["run"], "the fallback never undoes when main moved on (a re-run)"
PY
summary
