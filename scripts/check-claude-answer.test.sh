#!/usr/bin/env bash
# Tests scripts/check-claude-answer.sh: blocked calls listing and the answer hand-off as GitHub job outputs.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; SCRIPT="$HERE/check-claude-answer.sh"
. "$HERE/check-testlib.sh"
command -v jq >/dev/null || { echo "ERROR: jq required"; exit 2; }
W=$(mktemp -d "${TMPDIR:-/tmp}/ca.XXXXXX") || exit 2; trap 'rm -rf "$W"' EXIT
jq -n '[{"type":"system"},{"type":"result","result":"old"},{"type":"result","result":"REVIEW TEAM RESULT: PASS\nline two","permission_denials":[{"tool_name":"Bash","tool_input":{"command":"curl https://x"}},{"tool_name":"Read","tool_input":{"file_path":"/etc/passwd"}},{"tool_name":"WebFetch","tool_input":{"url":"https://e.com"}},{"tool_name":"Skill","tool_input":{"skill":"payload"}}]}]' > "$W/exec.json"
run() { local want=$1 name=$2 msg=$3; shift 3; out=$(bash "$SCRIPT" "$@" 2>&1); rc=$?; assert_result "$want" "$rc" "$name" "$msg" "$out"; }
run fail "usage" "usage: check-claude-answer.sh blocked|answer" --
run fail "unknown subcommand" "usage:" nope "$W/exec.json"
run ok "blocked: every denial, by tool, command/path/url, 300 chars" "BLOCKED Bash: curl https://x" blocked "$W/exec.json"
check "blocked: all four denials in order, the Skill one with an empty input" bash -c 'bash "$1" blocked "$2" | tr "\n" "|" | grep -q "^BLOCKED Bash: curl https://x|BLOCKED Read: /etc/passwd|BLOCKED WebFetch: https://e.com|BLOCKED Skill: |$"' _ "$SCRIPT" "$W/exec.json"
run ok "blocked: no execution file" "no execution file" blocked "$W/none.json"
run ok "blocked: empty file name" "no execution file" blocked ""
jq -n '[{"type":"result","result":"x"}]' > "$W/nodeny.json"; out=$(bash "$SCRIPT" blocked "$W/nodeny.json"); [ $? = 0 ] && [ -z "$out" ] && t PASS "blocked: no denials prints nothing" || t FAIL "blocked: no denials"
out=$(bash "$SCRIPT" answer "$W/exec.json"); rc=$?
d=$(sed -n '2s/^answer<<//p' <<<"$out")
[ $rc = 0 ] && [ "$(sed -n 1p <<<"$out")" = has_result=true ] && [[ "$d" =~ ^ANSWER_[0-9a-f]{16}$ ]] && [ "$(sed -n '3,4p' <<<"$out")" = $'REVIEW TEAM RESULT: PASS\nline two' ] && [ "$(tail -n1 <<<"$out")" = "$d" ] \
  && t PASS "answer: has_result, the last result as a delimited multi-line output" || { t FAIL "answer outputs ($rc)"; echo "$out"; }
out=$(bash "$SCRIPT" answer "$W/none.json"); [ "$out" = "has_result=false" ] && t PASS "answer: missing file" || t FAIL "answer: missing file"
printf 'not json' > "$W/bad.json"; out=$(bash "$SCRIPT" answer "$W/bad.json"); [ "$out" = "has_result=false" ] && t PASS "answer: not an execution file" || t FAIL "answer: bad json"
jq -n '[{"type":"result","result":"no text here" | ascii_upcase}]' > /dev/null; jq -n '[{"type":"result"}]' > "$W/noresult.json"; out=$(bash "$SCRIPT" answer "$W/noresult.json")
[ "$(sed -n 1p <<<"$out")" = has_result=true ] && [ "$(sed -n 3p <<<"$out")" = "" ] && t PASS "answer: a result without text gives an empty answer (the post script posts the placeholder)" || { t FAIL "answer: no text"; echo "$out"; }
python3 -c 'import json; json.dump([{"type":"result","result":"a"*70000}], open("'"$W/long.json"'","w"))'
out=$(set -o pipefail; bash "$SCRIPT" answer "$W/long.json"); rc=$?
[ "$rc" = 0 ] && [ "$(sed -n 3p <<<"$out" | wc -c)" = 60001 ] && t PASS "answer: cut at 60000 characters and exit 0 (no SIGPIPE: a long review must still be posted)" || t FAIL "answer: cut (rc=$rc)"
python3 -c 'import json; json.dump([{"type":"result","result":"x"*59999+"\n"}], open("'"$W/nl.json"'","w"))'
out=$(bash "$SCRIPT" answer "$W/nl.json"); [ "$(sed -n 3p <<<"$out" | wc -c)" = 60000 ] && t PASS "answer: a trailing newline inside the cap is kept as is" || t FAIL "answer: trailing newline"
summary
