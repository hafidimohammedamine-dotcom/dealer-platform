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
expect "login with other characters" fail '111 founder_one founder\n' "bad line 1 in"
expect "duplicate ID (founder twice)" fail '111 founder-one founder\n111 founder-two founder\n' "user ID 111 is listed twice in"
expect "duplicate ID as founder and agent" fail '111 founder-one founder\n111 agents-bot agent\n' "user ID 111 is listed twice in"
expect "duplicate ID reports the second line" fail '111 a founder\n222 b founder\n111 c agent\n' "(line 3)"
rows=$(rows_of '111 founder-one founder\n333 agents-bot agent\n')
check "account_field: login" test "$(account_field "$rows" 333 2)" = agents-bot
check "account_field: role" test "$(account_field "$rows" 111 3)" = founder
check "account_field: unknown ID is empty" test -z "$(account_field "$rows" 999 3)"
check "account_field: no prefix match" test -z "$(account_field "$rows" 11 3)"
summary
