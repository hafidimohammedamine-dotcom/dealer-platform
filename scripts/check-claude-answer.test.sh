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
# handed <exec.json>: the answer text the post job would receive (the lines between the delimiters), in $H; bytes in $HB
handed() { local out; out=$(bash "$SCRIPT" answer "$1"); rc=$?; H=$(handoff_text "$out"); HB=$(printf '%s' "$H" | wc -c); }
utf8ok() { printf '%s' "$1" | python3 -c 'import sys; sys.stdin.buffer.read().decode("utf-8")' 2>/dev/null; }
rep 250000 a | mk "$W/long.json"
WITHHELD="(answer withheld: no line break or blank before the 120000-byte limit)"$'\n\n(truncated)'
(set -o pipefail; handed "$W/long.json"; [ "$rc" = 0 ] && [ "$H" = "$WITHHELD" ]) \
  && t PASS "answer: 250000 characters with no line break or blank are withheld (notice plus marker), exit 0 (no SIGPIPE: a long review must still be posted)" || t FAIL "answer: cut"
rep 90000 a | mk "$W/mid.json"; handed "$W/mid.json"
[ "$HB" = 90000 ] && ! grep -q "(truncated)" <<<"$H" && t PASS "answer: 90000 characters pass whole, no marker (the 60000 comment cut is the post script's, scanned before posting)" || t FAIL "answer: 90000 ($HB)"
{ rep 59999 x; echo; } | mk "$W/nl.json"; handed "$W/nl.json"; [ "$HB" = 59999 ] && t PASS "answer: a trailing newline is not kept" || t FAIL "answer: trailing newline ($HB)"
python3 -c 'print("\U0001F600"*60000, end="")' | mk "$W/wide.json"   # 60000 four-byte characters = 240000 bytes
handed "$W/wide.json"; [ "$H" = "$WITHHELD" ] && t PASS "answer: 240000 bytes of four-byte characters with no blank are withheld (never cut inside, never over 128 KiB)" || t FAIL "answer: wide ($HB)"
{ rep 119985 a; printf ' ééééééééééé'; } | mk "$W/edge.json"; handed "$W/edge.json"   # 120008 bytes; a blank, then é on the cut byte
[ "$H" = "$(rep 119985 a)"$'\n\n(truncated)' ] && utf8ok "$H" && t PASS "answer: the cut at the last blank drops the multibyte run after it whole, never split" || t FAIL "answer: boundary ($HB)"
# A token across the cap: the cut moves back to the last line break, so the token is dropped whole (never handed in part,
# where a cut-off prefix would slip past an exact-length gitleaks rule in the post job).
{ echo "REVIEW TEAM RESULT: FAIL"; rep 110000 y; echo; printf 'TOKEN_AAAAAAAAAAAAAAAAAAAA'; rep 20000 z; } | mk "$W/tok.json"
handed "$W/tok.json"
[ "$H" = "REVIEW TEAM RESULT: FAIL"$'\n'"$(rep 110000 y)"$'\n\n(truncated)' ] && t PASS "answer: the cut is at the last line break or blank before 120000 bytes; a token straddling the cap is dropped whole" || t FAIL "answer: line cut ($HB)"
{ echo "REVIEW TEAM RESULT: PASS"; rep 118975 x; printf ' '; rep 5000 y; } | mk "$W/blank.json"; handed "$W/blank.json"
[ "$H" = "REVIEW TEAM RESULT: PASS"$'\n'"$(rep 118975 x)"$'\n\n(truncated)' ] && t PASS "answer: a blank after the last line break is where the cut goes (the later of the two)" || t FAIL "answer: blank cut ($HB)"
python3 -c 'print("\u00e9"*59980+"TOKEN_AAAAAAAAAAAAAAAAAAAA"+"\u00e9"*50, end="")' | mk "$W/toklim.json"   # a token right at byte 119960, no blank anywhere
handed "$W/toklim.json"; [ "$H" = "$WITHHELD" ] && t PASS "answer: a no-blank multibyte answer with a token at the limit hands over no body text and no TOKEN_ prefix" || t FAIL "answer: token at limit ($HB)"
# A BEGIN/END block across the cap (a key or certificate in real life; a neutral name here so no scanner trips on this
# file or on a review quoting it): the cut moves to before its BEGIN line, as a partial block passes the private-key rule.
PEM=$'-----BEGIN TEST BLOCK-----\nBLOCKBODY0000000000000000000000000000000000000000000000000000\n'
{ echo "REVIEW TEAM RESULT: FAIL"; rep 119000 y; echo; printf '%s' "$PEM"; rep 5000 z; echo; echo '-----END TEST BLOCK-----'; } | mk "$W/pem.json"
handed "$W/pem.json"
[ "$H" = "REVIEW TEAM RESULT: FAIL"$'\n'"$(rep 119000 y)"$'\n\n(truncated)' ] && t PASS "answer: a key block across the cap is dropped whole (the cut moves to before its BEGIN line)" || t FAIL "answer: pem ($HB)"
{ printf '%s' "$PEM"; rep 130000 z; echo; echo '-----END TEST BLOCK-----'; } | mk "$W/pem0.json"; handed "$W/pem0.json"
[ "$H" = "$WITHHELD" ] && t PASS "answer: a key block that starts on the first line and crosses the cap: withheld" || t FAIL "answer: pem first line ($HB)"
{ echo "REVIEW TEAM RESULT: PASS"; printf '%s' "$PEM"; echo '-----END TEST BLOCK-----'; rep 119000 y; echo; rep 5000 z; } | mk "$W/pem1.json"; handed "$W/pem1.json"
grep -q "^-----END TEST" <<<"$H" && grep -q "^yyyy" <<<"$H" && [ "$(tail -n1 <<<"$H")" = "(truncated)" ] && t PASS "answer: a closed key block before the cap is not a reason to move the cut" || t FAIL "answer: closed pem ($HB)"
{ rep 130000 a; echo; echo '-----BEGIN TEST BLOCK-----'; echo '-----END TEST BLOCK-----'; } | mk "$W/pem2.json"; handed "$W/pem2.json"
[ "$H" = "$WITHHELD" ] && [ "$HB" -le 120000 ] && t PASS "answer: no blank before the cap, then a line break and a block: withheld (the block guard never widens the cut)" || t FAIL "answer: pem after cap ($HB)"
{ rep 300000 a; echo; echo '-----BEGIN TEST BLOCK-----'; } | mk "$W/pem3.json"; handed "$W/pem3.json"
[ "$H" = "$WITHHELD" ] && [ "$HB" -le 120000 ] && t PASS "answer: the same with a BEGIN and no END: withheld, under the cap" || t FAIL "answer: begin no end ($HB)"
# The cut landing on a blank inside the END line (8 and 13 bytes into "-----END TEST BLOCK-----"): the block is not closed
# before the cut, so the cut moves to before its BEGIN line. keep = 120000 - 13 = 119987 bytes.
for off in 8 13; do
  n=$((119987 - off - 25 - 1 - 27 - 10 - 1))   # header 25, newline, BEGIN line 27, BLOCKBODY line 10, newline, y filler
  { echo "REVIEW TEAM RESULT: PASS"; rep "$n" y; echo; echo '-----BEGIN TEST BLOCK-----'; echo BLOCKBODY; printf -- '-----END TEST BLOCK-----\n'; rep 5000 z; } | mk "$W/endline.json"
  handed "$W/endline.json"
  [ "$H" = "REVIEW TEAM RESULT: PASS"$'\n'"$(rep "$n" y)"$'\n\n(truncated)' ] && t PASS "answer: the cut on the blank $off bytes into the END line: the block is open, the cut moves before BEGIN" || t FAIL "answer: END line blank $off ($HB)"
done
{ echo "REVIEW TEAM RESULT: PASS"; rep 119000 y; echo; echo '-----begin test block-----'; echo BLOCKBODY; rep 5000 z; echo; echo '-----end test block-----'; } | mk "$W/lower.json"; handed "$W/lower.json"
[ "$H" = "REVIEW TEAM RESULT: PASS"$'\n'"$(rep 119000 y)"$'\n\n(truncated)' ] && t PASS "answer: lowercase BEGIN/END markers are a block too (the private-key rule ignores case)" || t FAIL "answer: lowercase ($HB)"
printf '[{"type":"result","result":"ab\xffcd\\u0000ef"}]' > "$W/badutf.json"; handed "$W/badutf.json"
[ "$rc" = 0 ] && [ "$H" = $'ab\xef\xbf\xbdcdef' ] && t PASS "answer: a byte that is not UTF-8 becomes U+FFFD, a NUL is removed, nothing else is dropped" || t FAIL "answer: bad utf-8 ($rc)"
# More than 120000 bytes that are not UTF-8: cleaned to U+FFFD (3 bytes each) BEFORE the cap is measured, so the handed text
# can never pass 120000 bytes (one environment variable over 128 KiB fails at exec time in the post job).
S=$(mktemp -d "$W/stub.XXXXXX")
printf '#!/usr/bin/env bash\n[ "$1" = -r ] && { head -c 130000 /dev/zero | tr "\\0" "\\377"; exit 0; }\nexec %s "$@"\n' "$(command -v jq)" > "$S/jq"; chmod +x "$S/jq"
PATH="$S:$PATH" handed "$W/mid.json"
[ "$rc" = 0 ] && [ "$HB" -le 120000 ] && utf8ok "$H" && [ "$H" = "$WITHHELD" ] && t PASS "answer: 130000 bytes that are not UTF-8 (390000 bytes once cleaned) stay under the cap: cleaned first, then withheld (no blank)" || t FAIL "answer: 130000 bad bytes (rc=$rc, $HB)"
printf '#!/usr/bin/env bash\n[ "$1" = -r ] && { head -c 30000 /dev/zero | tr "\\0" "\\377"; echo; head -c 50000 /dev/zero | tr "\\0" x; exit 0; }\nexec %s "$@"\n' "$(command -v jq)" > "$S/jq"
PATH="$S:$PATH" handed "$W/mid.json"
[ "$rc" = 0 ] && [ "$HB" -le 120000 ] && utf8ok "$H" && [ "$H" = "$(rep 30000 x | sed 's/x/\xef\xbf\xbd/g')"$'\n\n(truncated)' ] \
  && t PASS "answer: 30000 bad bytes (90000 once cleaned) then a line break and 50000 more: the cap counts the cleaned bytes, cut at the line break, valid UTF-8" || t FAIL "answer: 30000 bad bytes (rc=$rc, $HB)"
rm -rf "$S"
# Failures mid-way: exit non-zero, no half-written answer<< block, no temp file.
S=$(mktemp -d "$W/stub.XXXXXX"); E=$(mktemp -d "$W/tmp.XXXXXX")
printf '#!/usr/bin/env bash\nexit 1\n' > "$S/python3"; chmod +x "$S/python3"
out=$(PATH="$S:$PATH" TMPDIR="$E" bash "$SCRIPT" answer "$W/mid.json" 2>&1); rc=$?
[ "$rc" != 0 ] && ! grep -q "answer<<\|has_result" <<<"$out" && [ -z "$(ls -A "$E")" ] && t PASS "answer: python3 failing exits non-zero, prints no output block, leaves no file" || { t FAIL "answer: python3 failure (rc=$rc)"; echo "$out"; }
rm -f "$S/python3"; printf '#!/usr/bin/env bash\n[ "$1" = -r ] && exit 1\nexec %s "$@"\n' "$(command -v jq)" > "$S/jq"; chmod +x "$S/jq"
out=$(PATH="$S:$PATH" TMPDIR="$E" bash "$SCRIPT" answer "$W/mid.json" 2>&1); rc=$?
[ "$rc" != 0 ] && ! grep -q "answer<<\|has_result" <<<"$out" && [ -z "$(ls -A "$E")" ] && t PASS "answer: jq failing on the text exits non-zero, prints no output block, leaves no file" || { t FAIL "answer: jq failure (rc=$rc)"; echo "$out"; }
summary
