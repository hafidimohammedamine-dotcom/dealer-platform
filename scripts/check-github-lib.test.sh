#!/usr/bin/env bash
# Tests scripts/check-github-lib.sh (gh_context, token_account, main_guard_runs, main_guard_status, mark_main_guard_passed,
# main_guard_passed, main_head_passed) with a
# stubbed gh; the scripts that use them have their own tests.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/check-testlib.sh"
. "$HERE/check-accounts-lib.sh"
. "$HERE/check-github-lib.sh"
A=$(mktemp "${TMPDIR:-/tmp}/gl-accounts.XXXXXX"); printf '111 founder-one founder\n333 agents-bot agent\n' > "$A"; rows=$(accounts_rows "$A"); rm -f "$A"
# The GitHub helpers the token-holding guards share
D=$(mktemp -d "${TMPDIR:-/tmp}/al.XXXXXX"); trap 'rm -rf "$D"' EXIT; mkdir -p "$D/bin"
write_gh_stub "$D/bin"
ctx() { ( unset GITHUB_ACTIONS GITHUB_REPOSITORY GH_REPO GH_BIN; export "$@"; gh_context && echo "GH=$GH REPO=$REPO" ) 2>&1; }
check "gh_context outside Actions: GH_BIN and GH_REPO" test "$(ctx GH_BIN=/x/gh GH_REPO=o/r)" = "GH=/x/gh REPO=o/r"
check "gh_context outside Actions: GITHUB_REPOSITORY as the fallback" test "$(ctx GH_BIN=/x/gh GITHUB_REPOSITORY=o/r)" = "GH=/x/gh REPO=o/r"
check "gh_context inside Actions ignores GH_BIN and GH_REPO" test "$(ctx GITHUB_ACTIONS=true GITHUB_REPOSITORY=o/r GH_BIN=/x/gh GH_REPO=a/b)" = "GH=gh REPO=o/r"
check "gh_context: no repository is an error" test "$(ctx GH_BIN=/x/gh)" = "ERROR: GH_REPO or GITHUB_REPOSITORY (owner/repo) is not set"
check "gh_context: a bad repository name is an error" test "$(ctx GH_BIN=/x/gh 'GH_REPO=o/r x')" = "ERROR: bad GH_REPO"
acct() { ( GH="$D/bin/gh"; export "$@"; token_account "$rows" && echo "$TOKEN_ID $TOKEN_LOGIN ${TOKEN_ROLE:-none}" ) 2>&1; }
check "token_account: the agents' token" test "$(acct STUB_WHO='333 agents-bot')" = "333 agents-bot agent"
check "token_account: a founder's token" test "$(acct STUB_WHO='111 founder-one')" = "111 founder-one founder"
check "token_account: an unknown account has no role" test "$(acct STUB_WHO='999 someone')" = "999 someone none"
check "token_account: gh fails" test "$(acct STUB_WHO= STUB_RC=1)" = "ERROR: could not read the token's GitHub login (is GH_TOKEN set and valid?)"
check "token_account: odd login text" test "$(acct STUB_WHO='333 x;y')" = "ERROR: could not read the token's GitHub login (is GH_TOKEN set and valid?)"
S40=$(printf 'c%.0s' {1..40})
mgp() { ( GH="$D/bin/gh"; REPO=owner/repo; main_guard_passed "$1" 0 ) 2>&1; }
check "main_guard_passed: a successful run" test "$(mgp "$S40")" = "ok $S40 passed the main guard"
check "main_guard_passed: no run after the guard existed" test "$(STUB_RUNS= mgp "$S40")" = "missing $S40 (runs: none)"
check "main_guard_passed: a cancelled run" test "$(STUB_RUNS=completed/cancelled mgp "$S40")" = "missing $S40 (runs: completed/cancelled)"
mgp2() { ( GH="$D/bin/gh"; REPO=owner/repo; export "${@:2}"; main_guard_passed "$1" 0 ) 2>&1; }
FLOOR=596905e54f7ae8385c90f6d334db5f18a4427e28
check "MAIN_GUARD_FLOOR is main's head when the guard was written" test "$MAIN_GUARD_FLOOR" = "$FLOOR"
case "$(mgp2 "$S40" STUB_RUNS= STUB_REL=ahead)" in "ok $S40 is on the default branch before the main guard existed (floor $FLOOR)") t PASS "main_guard_passed: older than the floor (compare: ahead)";; *) t FAIL "main_guard_passed: before the floor";; esac
case "$(mgp2 "$S40" STUB_RUNS= STUB_REL=identical)" in "ok $S40 is on the default branch before"*) t PASS "main_guard_passed: the floor commit itself";; *) t FAIL "main_guard_passed: identical";; esac
check "main_guard_passed: diverged history is missing" test "$(mgp2 "$S40" STUB_RUNS= STUB_REL=diverged)" = "missing $S40 (runs: none)"
check "main_guard_passed: behind the floor with no run is missing" test "$(mgp2 "$S40" STUB_RUNS= STUB_REL=behind)" = "missing $S40 (runs: none)"
check "main_guard_passed: the compare call fails" test "$(mgp2 "$S40" STUB_RUNS= STUB_REL_RC=1)" = "ERROR: could not compare $S40 with the main guard's floor commit $FLOOR."
check "main_guard_passed: the compare asks for <sha>...<floor>" bash -c '( GH="$1/bin/gh"; REPO=owner/repo; STUB_RUNS=; STUB_REL=ahead; export STUB_RUNS STUB_REL; . "$2/check-accounts-lib.sh"; . "$2/check-github-lib.sh"; STUB_GH_LOG="$1/log" main_guard_passed "$3" 0 >/dev/null ); grep -q "compare/$3...$4" "$1/log"' _ "$D" "$HERE" "$S40" "$FLOOR"
mhp() { ( GH="$D/bin/gh"; REPO=owner/repo; [ $# -lt 2 ] || export "${@:2}"; main_head_passed 0 "$1" ) 2>&1; }
check "main_head_passed: the head passed" test "$(mhp 'anything runs')" = "ok $S40 passed the main guard"
check "main_head_passed: names who must not run" test "$(mhp 'any agent runs' STUB_RUNS=)" = "ERROR: the default branch's head ($S40) has no successful main-guard run (missing $S40 (runs: none)). A founder checks that push (was the run cancelled, the workflow disabled, or the commit message marked [skip ci]?) before any agent runs."
check "main_head_passed: the head cannot be read" test "$(mhp x STUB_HEAD_RC=1)" = "ERROR: could not read the default branch's head commit."
check "main_head_passed: odd head text" test "$(mhp x 'STUB_HEAD=not a sha')" = "ERROR: could not read the default branch's head commit."
mgr() { ( GH="$D/bin/gh"; REPO=owner/repo; export "${@:2}"; main_guard_runs "$1" ) 2>&1; }
check "main_guard_runs: the runs of a head sha" test "$(mgr "$S40" 'STUB_RUNS=completed/failure completed/success')" = "completed/failure completed/success"
check "main_guard_runs: an API error returns 1" bash -c '! ( GH="$1/bin/gh"; REPO=owner/repo; STUB_RUNS_RC=1; export STUB_RUNS_RC; . "$2/check-accounts-lib.sh"; . "$2/check-github-lib.sh"; main_guard_runs "$3" )' _ "$D" "$HERE" "$S40"
case "$(mgp2 "$S40" STUB_RUNS=in_progress/)" in "ERROR: the main-guard run for $S40 has not finished after 0s"*) t PASS "main_guard_passed: a run still going with no wait left is an error";; *) t FAIL "main_guard_passed: still going";; esac
check "main_guard_passed: a bad sha" test "$(mgp nope)" = "ERROR: bad commit sha: 'nope'"
# The guards/main-guard status (the guard's own revert commit, or a commit a founder accepted) stands in for a run
check "main_guard_passed: no run but the status" test "$(mgp2 "$S40" STUB_RUNS= STUB_MARKS=1)" = "ok $S40 carries the guards/main-guard status (the main guard's revert, or accepted by a founder)"
check "main_guard_passed: a cancelled run and the status: the status wins" test "$(mgp2 "$S40" STUB_RUNS=completed/cancelled STUB_MARKS=1)" = "ok $S40 carries the guards/main-guard status (the main guard's revert, or accepted by a founder)"
check "main_guard_passed: the status is asked before the floor compare (no compare when marked)" bash -c '( GH="$1/bin/gh"; REPO=owner/repo; STUB_RUNS=; STUB_MARKS=1; export STUB_RUNS STUB_MARKS; . "$2/check-accounts-lib.sh"; . "$2/check-github-lib.sh"; STUB_GH_LOG="$1/log2" main_guard_passed "$3" 0 >/dev/null ); ! grep -q "compare/" "$1/log2"' _ "$D" "$HERE" "$S40"
check "main_guard_passed: the status call fails" test "$(mgp2 "$S40" STUB_RUNS= STUB_MARKS_RC=1)" = "ERROR: could not read the commit statuses of $S40."
check "main_guard_passed: odd status text" test "$(mgp2 "$S40" STUB_RUNS= STUB_MARKS=lots)" = "ERROR: could not read the commit statuses of $S40."
check "main_guard_status asks the combined status for context guards/main-guard, state success, creator 41898282" bash -c '( GH="$1/bin/gh"; REPO=owner/repo; . "$2/check-accounts-lib.sh"; . "$2/check-github-lib.sh"; STUB_GH_LOG="$1/log3" main_guard_status "$3" >/dev/null ); grep -qF "gh api repos/owner/repo/commits/$3/status --jq [.statuses[] | select(.context == \"guards/main-guard\" and .state == \"success\" and .creator.id == 41898282)] | length" "$1/log3"' _ "$D" "$HERE" "$S40"
check "mark_main_guard_passed posts a success status with the context and the description" bash -c '( GH="$1/bin/gh"; REPO=owner/repo; . "$2/check-accounts-lib.sh"; . "$2/check-github-lib.sh"; STUB_GH_LOG="$1/log4" mark_main_guard_passed "$3" "revert by main-guard run 7" ); grep -qF "gh api -X POST repos/owner/repo/statuses/$3 -f state=success -f context=guards/main-guard -f description=revert by main-guard run 7" "$1/log4"' _ "$D" "$HERE" "$S40"
check "mark_main_guard_passed: a failed post returns 1" bash -c '! ( GH="$1/bin/gh"; REPO=owner/repo; STUB_MARK_RC=1; export STUB_MARK_RC; . "$2/check-accounts-lib.sh"; . "$2/check-github-lib.sh"; mark_main_guard_passed "$3" x )' _ "$D" "$HERE" "$S40"
check "main_guard_runs counts push runs only (the schedule and workflow_dispatch runs of the same head are left out)" bash -c '( GH="$1/bin/gh"; REPO=owner/repo; . "$2/check-accounts-lib.sh"; . "$2/check-github-lib.sh"; STUB_GH_LOG="$1/log5" main_guard_runs "$3" >/dev/null ); grep -qF "select(.event == \"push\")" "$1/log5"' _ "$D" "$HERE" "$S40"
# The two jq filters run for real (STUB_JSON_RUNS/STUB_JSON_STATUS make the stub apply the --jq filter to that file with jq): a schedule run and a
# by-hand run of the same head are left out; only a success status in the guards/main-guard context created by
# github-actions[bot] counts, never one the agents' account posted, a pending one, or another context.
cat > "$D/bin/gh-extra" <<'EXTRA'
case "$2" in *'/runs?'*) f="${STUB_JSON_RUNS:-}";; */status) f="${STUB_JSON_STATUS:-}";; *) f="";; esac
[ -z "$f" ] || [ "$3" != --jq ] || { jq -r "$4" "$f"; exit $?; }
EXTRA
cat > "$D/runs.json" <<'JSON'
{"workflow_runs":[{"event":"schedule","status":"in_progress","conclusion":null},{"event":"workflow_dispatch","status":"completed","conclusion":"success"},{"event":"push","status":"completed","conclusion":"failure"},{"event":"push","status":"completed","conclusion":"success"}]}
JSON
check "main_guard_runs with real jq: push runs only, in order" test "$(mgr "$S40" STUB_JSON_RUNS="$D/runs.json")" = "completed/failure completed/success"
printf '{"workflow_runs":[{"event":"schedule","status":"in_progress","conclusion":null}]}\n' > "$D/runs2.json"
check "main_guard_runs with real jq: only the schedule run of this head -> none (the hourly run never finds itself)" test "$(mgr "$S40" STUB_JSON_RUNS="$D/runs2.json")" = ""
mgs() { ( GH="$D/bin/gh"; REPO=owner/repo; export "${@:2}"; main_guard_status "$1" ) 2>&1; }
cat > "$D/st0.json" <<'JSON'
{"statuses":[{"context":"guards/main-guard","state":"success","creator":{"id":333}},{"context":"guards/main-guard","state":"pending","creator":{"id":41898282}},{"context":"guards/pusher","state":"success","creator":{"id":41898282}},{"context":"guards/main-guard","state":"failure","creator":{"id":41898282}}]}
JSON
check "main_guard_status with real jq: the agents' status, a pending one, a failed one and another context count 0" test "$(mgs "$S40" STUB_JSON_STATUS="$D/st0.json")" = 0
jq '.statuses += [{"context":"guards/main-guard","state":"success","creator":{"id":41898282}}]' "$D/st0.json" > "$D/st1.json"
check "main_guard_status with real jq: one success status by github-actions[bot] counts 1" test "$(mgs "$S40" STUB_JSON_STATUS="$D/st1.json")" = 1
check "main_guard_passed with real jq: the agents' forged status does not pass" test "$(mgp2 "$S40" STUB_REL=behind STUB_JSON_RUNS="$D/runs2.json" STUB_JSON_STATUS="$D/st0.json")" = "missing $S40 (runs: none)"
check "main_guard_passed with real jq: the bot's status passes" test "$(mgp2 "$S40" STUB_JSON_RUNS="$D/runs2.json" STUB_JSON_STATUS="$D/st1.json")" = "ok $S40 carries the guards/main-guard status (the main guard's revert, or accepted by a founder)"
rm -f "$D/bin/gh-extra"
# Lineage: the commit must be the newest checked head (the newest successful push run's head) or descend from it
L40=$(printf 'd%.0s' {1..40})
check "main_guard_passed: no successful run yet (empty latest) skips the lineage check" test "$(mgp2 "$S40" "STUB_LATEST=")" = "ok $S40 passed the main guard"
check "main_guard_passed: the commit is the newest checked head" test "$(mgp2 "$S40" STUB_LATEST="$S40")" = "ok $S40 passed the main guard"
check "main_guard_passed: descends from the newest checked head (compare: ahead)" test "$(mgp2 "$S40" STUB_LATEST="$L40" STUB_REL=ahead)" = "ok $S40 passed the main guard"
check "main_guard_passed: behind the newest checked head = rolled back" test "$(mgp2 "$S40" STUB_LATEST="$L40" STUB_REL=behind)" = "rolled back $S40 (behind the last checked head $L40, compare: behind): the default branch was moved back to an older commit"
check "main_guard_passed: diverged from the newest checked head = rolled back" test "$(mgp2 "$S40" STUB_LATEST="$L40" STUB_REL=diverged)" = "rolled back $S40 (behind the last checked head $L40, compare: diverged): the default branch was moved back to an older commit"
check "main_guard_passed: the newest-run lookup fails" test "$(mgp2 "$S40" STUB_LATEST_RC=1)" = "ERROR: could not read the newest main-guard run."
check "main_guard_passed: odd newest-run text" test "$(mgp2 "$S40" "STUB_LATEST=not a sha")" = "ERROR: could not read the newest main-guard run."
check "main_guard_passed: the lineage compare fails" test "$(mgp2 "$S40" STUB_LATEST="$L40" STUB_REL_RC=1)" = "ERROR: could not compare $S40 with the last checked head $L40."
check "main_guard_passed: the lineage is asked after the run/status/floor checks (a missing commit is reported as missing)" test "$(mgp2 "$S40" STUB_RUNS= STUB_REL=behind STUB_LATEST="$L40")" = "missing $S40 (runs: none)"
check "main_guard_latest asks for the newest successful push run" bash -c '( GH="$1/bin/gh"; REPO=owner/repo; . "$2/check-accounts-lib.sh"; . "$2/check-github-lib.sh"; STUB_GH_LOG="$1/log6" STUB_LATEST=x main_guard_latest >/dev/null ); grep -qF "runs?event=push&status=success&per_page=1 --jq .workflow_runs[0].head_sha // empty" "$1/log6"' _ "$D" "$HERE"
check "main_head_passed: a rolled-back head names the move" test "$(mhp 'any agent runs' STUB_LATEST="$L40" STUB_REL=behind)" = "ERROR: the default branch's head ($S40) is behind the last checked head (rolled back $S40 (behind the last checked head $L40, compare: behind): the default branch was moved back to an older commit). A founder checks who moved the default branch back (the repository's audit log; the workflow disabled or a run cancelled meanwhile?) before any agent runs."
# Deleted runs: the retained main-guard runs other than this one must be one unbroken sequence ending just before it
mri() { ( GH="$D/bin/gh"; REPO=owner/repo; export "${@:2}"; main_guard_runs_intact "$1" ) 2>&1; }
check "main_guard_runs_intact: unbroken up to this run" test "$(mri 12 'STUB_NUMBERS=9 10 11 12')" = "ok main-guard runs #9..#11 are all retained"
check "main_guard_runs_intact: unordered and repeated numbers (pages) are fine" test "$(mri 12 'STUB_NUMBERS=11 9 10 10')" = "ok main-guard runs #9..#11 are all retained"
check "main_guard_runs_intact: no other run" test "$(mri 1 'STUB_NUMBERS=1')" = "ok no earlier main-guard run is retained"
check "main_guard_runs_intact: a gap in the middle" test "$(mri 12 'STUB_NUMBERS=9 11')" = "deleted main-guard run(s) between #9 and #11: someone deleted workflow runs"
check "main_guard_runs_intact: the newest runs gone" test "$(mri 12 'STUB_NUMBERS=9 10')" = "deleted main-guard run(s) between #10 and this run #12: someone deleted workflow runs"
check "main_guard_runs_intact: the API fails" test "$(mri 12 STUB_NUMBERS_RC=1)" = "ERROR: could not list the main-guard runs."
check "main_guard_runs_intact: a bad run number" test "$(mri x STUB_NUMBERS=)" = "ERROR: bad run number: 'x'"
check "no MAIN_GUARD_FLOOR_OVERRIDE: the floor is the constant" bash -c '! grep -q "FLOOR_OVERRIDE" "$1/check-github-lib.sh"' _ "$HERE"
summary
