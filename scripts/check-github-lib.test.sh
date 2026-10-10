#!/usr/bin/env bash
# Tests scripts/check-github-lib.sh (gh_context, token_account, main_guard_runs, main_guard_passed, main_head_passed) with a
# stubbed gh; the scripts that use them have their own tests.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/check-testlib.sh"
. "$HERE/check-accounts-lib.sh"
. "$HERE/check-github-lib.sh"
A=$(mktemp "${TMPDIR:-/tmp}/gl-accounts.XXXXXX"); printf '111 founder-one founder\n333 agents-bot agent\n' > "$A"; rows=$(accounts_rows "$A"); rm -f "$A"
# The GitHub helpers the token-holding guards share
D=$(mktemp -d "${TMPDIR:-/tmp}/al.XXXXXX"); trap 'rm -rf "$D"' EXIT; mkdir -p "$D/bin"
cat > "$D/bin/gh" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  'api user --jq "\(.id) \(.login)"') printf '%s\n' "${STUB_WHO-333 agents-bot}"; exit "${STUB_RC:-0}";;
  "api repos/owner/repo/actions/workflows/main-guard.yml/runs?head_sha="*) [ "${STUB_RUNS_RC:-0}" = 0 ] || exit 1; printf '%s\n' "${STUB_RUNS-completed/success}";;
  "api repos/owner/repo/compare/"*) [ -z "${STUB_LOG:-}" ] || echo "$*" >> "$STUB_LOG"; [ "${STUB_REL_RC:-0}" = 0 ] || exit 1; printf '%s\n' "${STUB_REL:-behind}";;
  "api repos/owner/repo/commits/HEAD --jq .sha") printf '%s\n' "${STUB_HEAD-cccccccccccccccccccccccccccccccccccccccc}"; exit "${STUB_HEAD_RC:-0}";;
  *) exit 9;;
esac
STUB
chmod +x "$D/bin/gh"
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
check "main_guard_passed: the compare asks for <sha>...<floor>" bash -c '( GH="$1/bin/gh"; REPO=owner/repo; STUB_RUNS=; STUB_REL=ahead; export STUB_RUNS STUB_REL; . "$2/check-accounts-lib.sh"; . "$2/check-github-lib.sh"; STUB_LOG="$1/log" main_guard_passed "$3" 0 >/dev/null ); grep -q "compare/$3...$4" "$1/log"' _ "$D" "$HERE" "$S40" "$FLOOR"
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
summary
