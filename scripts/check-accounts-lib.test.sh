#!/usr/bin/env bash
# Tests scripts/check-accounts-lib.sh directly: accounts_rows (format, duplicates, comments, founders) and account_field.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/check-testlib.sh"
. "$HERE/check-accounts-lib.sh"
W=$(mktemp -d "${TMPDIR:-/tmp}/al.XXXXXX") || exit 2; trap 'rm -rf "$W"' EXIT
rows_of() { printf '%b' "$1" > "$W/a"; accounts_rows "$W/a"; }
expect() { # expect <ok|fail> <name> <file text> <message or exact rows>
  out=$(rows_of "$3" 2>&1); rc=$?
  if [ "$2" = ok ]; then [ $rc = 0 ] && [ "$out" = "$(printf '%b' "$4")" ] && t PASS "$1" || { t FAIL "$1 (rc=$rc)"; echo "$out"; }
  else [ $rc = 1 ] && grep -qF -- "$4" <<<"$out" && t PASS "$1" || { t FAIL "$1 (rc=$rc)"; echo "$out"; }; fi; }
expect "plain rows" ok '111 founder-one founder\n333 agents-bot agent\n' '111 founder-one founder\n333 agents-bot agent'
expect "comments, blanks, indentation, no final newline" ok '# c\n\n  222  f-two   founder  # x\n333 agents-bot agent' '222 f-two founder\n333 agents-bot agent'
out=$(accounts_rows "$W/none" 2>&1); rc=$?; [ $rc = 1 ] && grep -q "accounts file not found" <<<"$out" && t PASS "missing file" || t FAIL "missing file"
expect "no founder" fail '333 agents-bot agent\n' "no founder listed in"
expect "line without a role" fail '111 founder-one\n' "bad line 1 in"
expect "non-numeric ID with extra fields" fail 'abc founder-one founder extra\n' "bad line 1 in"
expect "extra field" fail '111 founder-one founder extra\n' "bad line 1 in"
expect "bad role" fail '111 founder-one owner\n' "bad line 1 in"
expect "login with a # is cut at the comment and fails" fail '111 founder#one founder\n' "bad line 1 in"
expect "CRLF line endings" fail '111 founder-one founder\r\n' "bad line 1 in"
expect "login with other characters" fail '111 founder_one founder\n' "bad line 1 in"
expect "duplicate ID (founder twice)" fail '111 founder-one founder\n111 founder-two founder\n' "user ID 111 is listed twice in"
expect "duplicate ID as founder and agent" fail '111 founder-one founder\n111 agents-bot agent\n' "user ID 111 is listed twice in"
expect "duplicate ID reports the second line" fail '111 a founder\n222 b founder\n111 c agent\n' "(line 3)"
rows=$(rows_of '111 founder-one founder\n333 agents-bot agent\n')
check "account_field: login" test "$(account_field "$rows" 333 2)" = agents-bot
check "account_field: role" test "$(account_field "$rows" 111 3)" = founder
check "account_field: unknown ID is empty" test -z "$(account_field "$rows" 999 3)"
check "account_field: no prefix match" test -z "$(account_field "$rows" 11 3)"
# The GitHub helpers the token-holding guards share
D=$(mktemp -d "${TMPDIR:-/tmp}/al.XXXXXX"); trap 'rm -rf "$D"' EXIT; mkdir -p "$D/bin"
cat > "$D/bin/gh" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  'api user --jq "\(.id) \(.login)"') printf '%s\n' "${STUB_WHO-333 agents-bot}"; exit "${STUB_RC:-0}";;
  "api repos/owner/repo/actions/workflows/main-guard.yml/runs?head_sha="*) printf '%s\n' "${STUB_RUNS-completed/success}";;
  "api repos/owner/repo/actions/workflows/main-guard.yml --jq .created_at") echo 2026-10-01T00:00:00Z;;
  "api repos/owner/repo/commits/"*) printf '%s\n' "${STUB_DATE:-2026-10-10T00:00:00Z}";;
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
case "$(mgp2 "$S40" STUB_RUNS= STUB_DATE=2026-09-01T00:00:00Z)" in "ok $S40 was committed before the main guard existed"*) t PASS "main_guard_passed: committed before the guard existed";; *) t FAIL "main_guard_passed: before the guard";; esac
case "$(mgp2 "$S40" STUB_RUNS=in_progress/)" in "ERROR: the main-guard run for $S40 has not finished after 0s"*) t PASS "main_guard_passed: a run still going with no wait left is an error";; *) t FAIL "main_guard_passed: still going";; esac
check "main_guard_passed: a bad sha" test "$(mgp nope)" = "ERROR: bad commit sha: 'nope'"
summary
