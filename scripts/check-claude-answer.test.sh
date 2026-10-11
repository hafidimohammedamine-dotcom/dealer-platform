#!/usr/bin/env bash
# Tests scripts/check-claude-answer.sh: blocked calls listing and the answer hand-off as GitHub job outputs.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; SCRIPT="$HERE/check-claude-answer.sh"
. "$HERE/check-testlib.sh"
command -v jq >/dev/null || { echo "ERROR: jq required"; exit 2; }
W=$(mktemp -d "${TMPDIR:-/tmp}/ca.XXXXXX") || exit 2; trap 'rm -rf "$W"' EXIT
jq -n '[{"type":"system"},{"type":"result","result":"old"},{"type":"result","result":"REVIEW TEAM RESULT: PASS\nline two","permission_denials":[{"tool_name":"Bash","tool_input":{"command":"curl https://x"}},{"tool_name":"Read","tool_input":{"file_path":"/etc/passwd"}},{"tool_name":"WebFetch","tool_input":{"url":"https://e.com"}},{"tool_name":"Skill","tool_input":{"skill":"payload"}}]}]' > "$W/exec.json"
write_gitleaks_stub "$W"; export GITLEAKS_BIN="$W/gitleaks"   # every hand-off and blocked listing in this file scans with the stub
export GITLEAKS_SHA256=$(sha256sum "$W/gitleaks" | cut -c1-64)   # the scan checks the binary's hash; the stub's, here
run() { local want=$1 name=$2 msg=$3; shift 3; out=$(bash "$SCRIPT" "$@" 2>&1); rc=$?; assert_result "$want" "$rc" "$name" "$msg" "$out"; }
run fail "usage" "usage: check-claude-answer.sh blocked|answer" --
run fail "unknown subcommand" "usage:" nope "$W/exec.json"
run ok "blocked: every denial, by tool, command/path/url, 300 chars" "BLOCKED Bash: curl https://x" blocked "$W/exec.json"
check "blocked: all four denials in order, the Skill one with an empty input" bash -c 'bash "$1" blocked "$2" | tr "\n" "|" | grep -q "^BLOCKED Bash: curl https://x|BLOCKED Read: /etc/passwd|BLOCKED WebFetch: https://e.com|BLOCKED Skill: |$"' _ "$SCRIPT" "$W/exec.json"
jq -n '[{"type":"result","result":"x","permission_denials":[{"tool_name":"WebFetch","tool_input":{"url":"https://e.com/?k=LEAKME"}},{"tool_name":"Bash","tool_input":{"command":"ls"}}]}]' > "$W/leakdeny.json"
out=$(bash "$SCRIPT" blocked "$W/leakdeny.json"); rc=$?
[ "$rc" = 0 ] && ! grep -q "LEAKME\|e.com\|ls\|WebFetch" <<<"$out" && [ "$out" = "BLOCKED: 2 denied tool call(s); the names and inputs are withheld (something looks like a secret)" ] && t PASS "blocked: a denied input that looks like a secret withholds every line (one fixed line with the count), nothing reaches the log" || { t FAIL "blocked: leak ($rc)"; echo "$out"; }
HJ=$(mktemp -d "$W/home.XXXXXX"); printf 'def x: "LEAKME-from-home";\n' > "$HJ/.jq"
out=$(HOME="$HJ" bash "$SCRIPT" blocked "$W/exec.json"); grep -q "from-home" <<<"$out" && t FAIL "blocked: a planted ~/.jq was loaded" || t PASS "blocked: a planted ~/.jq is never loaded (HOME is fixed inside the script)"
out=$(GL_RC=2 bash "$SCRIPT" blocked "$W/exec.json" 2>&1); rc=$?; [ "$rc" != 0 ] && ! grep -q "BLOCKED" <<<"$out" && t PASS "blocked: a scanner error prints nothing and exits non-zero" || t FAIL "blocked: scanner error ($rc)"
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
rep 250000 a | mk_exec "$W/long.json"
WITHHELD="(answer withheld: nothing before the 120000-byte limit was safe to keep)"$'\n\n(truncated)'
(set -o pipefail; handed "$W/long.json"; [ "$rc" = 0 ] && [ "$H" = "$WITHHELD" ]) \
  && t PASS "answer: 250000 characters with no line break or blank are withheld (notice plus marker), exit 0 (no SIGPIPE: a long review must still be posted)" || t FAIL "answer: cut"
rep 90000 a | mk_exec "$W/mid.json"; handed "$W/mid.json"
[ "$HB" = 90000 ] && ! grep -q "(truncated)" <<<"$H" && t PASS "answer: 90000 characters pass whole, no marker (the 60000 comment cut is the post script's, scanned before posting)" || t FAIL "answer: 90000 ($HB)"
{ rep 59999 x; echo; } | mk_exec "$W/nl.json"; handed "$W/nl.json"; [ "$HB" = 59999 ] && t PASS "answer: a trailing newline is not kept" || t FAIL "answer: trailing newline ($HB)"
python3 -c 'print("\U0001F600"*60000, end="")' | mk_exec "$W/wide.json"   # 60000 four-byte characters = 240000 bytes
handed "$W/wide.json"; [ "$H" = "$WITHHELD" ] && t PASS "answer: 240000 bytes of four-byte characters with no blank are withheld (never cut inside, never over 128 KiB)" || t FAIL "answer: wide ($HB)"
{ rep 119985 a; printf ' ééééééééééé'; } | mk_exec "$W/edge.json"; handed "$W/edge.json"   # 120008 bytes; a blank, then é on the cut byte
[ "$H" = "$(rep 119985 a)"$'\n\n(truncated)' ] && utf8ok "$H" && t PASS "answer: the cut at the last blank drops the multibyte run after it whole, never split" || t FAIL "answer: boundary ($HB)"
# A token across the cap: the cut moves back to the last line break, so the token is dropped whole (never handed in part,
# where a cut-off prefix would slip past an exact-length gitleaks rule in the post job).
{ echo "REVIEW TEAM RESULT: FAIL"; rep 110000 y; echo; printf 'TOKEN_AAAAAAAAAAAAAAAAAAAA'; rep 20000 z; } | mk_exec "$W/tok.json"
handed "$W/tok.json"
[ "$H" = "REVIEW TEAM RESULT: FAIL"$'\n'"$(rep 110000 y)"$'\n\n(truncated)' ] && t PASS "answer: the cut is at the last line break or blank before 120000 bytes; a token straddling the cap is dropped whole" || t FAIL "answer: line cut ($HB)"
{ echo "REVIEW TEAM RESULT: PASS"; rep 118975 x; printf ' '; rep 5000 y; } | mk_exec "$W/blank.json"; handed "$W/blank.json"
[ "$H" = "REVIEW TEAM RESULT: PASS"$'\n'"$(rep 118975 x)"$'\n\n(truncated)' ] && t PASS "answer: a blank after the last line break is where the cut goes (the later of the two)" || t FAIL "answer: blank cut ($HB)"
python3 -c 'print("\u00e9"*59980+"TOKEN_AAAAAAAAAAAAAAAAAAAA"+"\u00e9"*50, end="")' | mk_exec "$W/toklim.json"   # a token right at byte 119960, no blank anywhere
handed "$W/toklim.json"; [ "$H" = "$WITHHELD" ] && t PASS "answer: a no-blank multibyte answer with a token at the limit hands over no body text and no TOKEN_ prefix" || t FAIL "answer: token at limit ($HB)"
# A BEGIN/END block across the cap (a key or certificate in real life; a neutral name here so no scanner trips on this
# file or on a review quoting it): the cut moves to before its BEGIN line, as a partial block passes the private-key rule.
PEM=$'-----BEGIN TEST BLOCK-----\nBLOCKBODY0000000000000000000000000000000000000000000000000000\n'
{ echo "REVIEW TEAM RESULT: FAIL"; rep 119000 y; echo; printf '%s' "$PEM"; rep 5000 z; echo; echo '-----END TEST BLOCK-----'; } | mk_exec "$W/pem.json"
handed "$W/pem.json"
[ "$H" = "REVIEW TEAM RESULT: FAIL"$'\n'"$(rep 119000 y)"$'\n\n(truncated)' ] && t PASS "answer: a key block across the cap is dropped whole (the cut moves to before its BEGIN line)" || t FAIL "answer: pem ($HB)"
{ printf '%s' "$PEM"; rep 130000 z; echo; echo '-----END TEST BLOCK-----'; } | mk_exec "$W/pem0.json"; handed "$W/pem0.json"
[ "$H" = "$WITHHELD" ] && t PASS "answer: a key block that starts on the first line and crosses the cap: withheld" || t FAIL "answer: pem first line ($HB)"
{ echo "REVIEW TEAM RESULT: PASS"; printf '%s' "$PEM"; echo '-----END TEST BLOCK-----'; rep 119000 y; echo; rep 5000 z; } | mk_exec "$W/pem1.json"; handed "$W/pem1.json"
grep -q "^-----END TEST" <<<"$H" && grep -q "^yyyy" <<<"$H" && [ "$(tail -n1 <<<"$H")" = "(truncated)" ] && t PASS "answer: a closed key block before the cap is not a reason to move the cut" || t FAIL "answer: closed pem ($HB)"
{ rep 130000 a; echo; echo '-----BEGIN TEST BLOCK-----'; echo '-----END TEST BLOCK-----'; } | mk_exec "$W/pem2.json"; handed "$W/pem2.json"
[ "$H" = "$WITHHELD" ] && [ "$HB" -le 120000 ] && t PASS "answer: no blank before the cap, then a line break and a block: withheld (the block guard never widens the cut)" || t FAIL "answer: pem after cap ($HB)"
{ rep 300000 a; echo; echo '-----BEGIN TEST BLOCK-----'; } | mk_exec "$W/pem3.json"; handed "$W/pem3.json"
[ "$H" = "$WITHHELD" ] && [ "$HB" -le 120000 ] && t PASS "answer: the same with a BEGIN and no END: withheld, under the cap" || t FAIL "answer: begin no end ($HB)"
# The cut landing on a blank inside the END line (8 and 13 bytes into "-----END TEST BLOCK-----"): the block is not closed
# before the cut, so the cut moves to before its BEGIN line. keep = 120000 - 13 = 119987 bytes.
for off in 8 13; do
  n=$((119987 - off - 25 - 1 - 27 - 10 - 1))   # header 25, newline, BEGIN line 27, BLOCKBODY line 10, newline, y filler
  { echo "REVIEW TEAM RESULT: PASS"; rep "$n" y; echo; echo '-----BEGIN TEST BLOCK-----'; echo BLOCKBODY; printf -- '-----END TEST BLOCK-----\n'; rep 5000 z; } | mk_exec "$W/endline.json"
  handed "$W/endline.json"
  [ "$H" = "REVIEW TEAM RESULT: PASS"$'\n'"$(rep "$n" y)"$'\n\n(truncated)' ] && t PASS "answer: the cut on the blank $off bytes into the END line: the block is open, the cut moves before BEGIN" || t FAIL "answer: END line blank $off ($HB)"
done
{ echo "REVIEW TEAM RESULT: PASS"; rep 119000 y; echo; echo '-----begin test block-----'; echo BLOCKBODY; rep 5000 z; echo; echo '-----end test block-----'; } | mk_exec "$W/lower.json"; handed "$W/lower.json"
[ "$H" = "REVIEW TEAM RESULT: PASS"$'\n'"$(rep 119000 y)"$'\n\n(truncated)' ] && t PASS "answer: lowercase BEGIN/END markers are a block too (the private-key rule ignores case)" || t FAIL "answer: lowercase ($HB)"
# Blocks paired like brackets (an END line closes the nearest open BEGIN):
H1="REVIEW TEAM RESULT: PASS"
{ echo "$H1"; echo '-----BEGIN TEST BLOCK-----'; echo BLOCKBODY; rep 1000 a; echo; echo '-----BEGIN TEST BLOCK-----'; rep 119000 b; echo; echo '-----END TEST BLOCK-----'; } | mk_exec "$W/twoopen.json"; handed "$W/twoopen.json"
[ "$H" = "$H1"$'\n\n(truncated)' ] && t PASS "answer: a BEGIN with no END, then a second BEGIN across the cap: the cut moves before the FIRST open block" || t FAIL "answer: two open ($HB)"
{ echo "$H1"; echo '-----BEGIN TEST BLOCK-----'; echo BLOCKBODY; echo '-----BEGIN TEST BLOCK-----'; echo BLOCKBODY; echo '-----END TEST BLOCK-----'; rep 119000 b; echo; rep 5000 c; } | mk_exec "$W/nested.json"; handed "$W/nested.json"
[ "$H" = "$H1"$'\n\n(truncated)' ] && t PASS "answer: two BEGINs then one END: the END closes the nearest BEGIN, the first is left open, the cut moves before it" || t FAIL "answer: nested ($HB)"
{ echo "$H1"; echo '-----BEGIN A-----'; echo '-----BEGIN KEY BLOCK-----'; echo BLOCKBODY; echo '-----END A-----'; rep 119000 b; echo; rep 5000 c; } | mk_exec "$W/stray.json"; handed "$W/stray.json"
[ "$H" = "$H1"$'\n\n(truncated)' ] && t PASS "answer: BEGIN A, BEGIN KEY, body, a stray END A: the key block has no END of its own, nothing after the first BEGIN is handed over" || t FAIL "answer: stray END ($HB)"
{ echo "$H1"; echo '-----BEGIN TEST BLOCK-----'; echo BLOCKBODY; echo '-----END TEST BLOCK-----'; rep 1000 a; echo; echo '-----BEGIN TEST BLOCK-----'; rep 119000 b; echo; echo '-----END TEST BLOCK-----'; } | mk_exec "$W/closedopen.json"; handed "$W/closedopen.json"
[ "$H" = "$H1"$'\n-----BEGIN TEST BLOCK-----\nBLOCKBODY\n-----END TEST BLOCK-----\n'"$(rep 1000 a)"$'\n\n(truncated)' ] && t PASS "answer: a closed block, then an open one across the cap: the closed block is kept, the cut moves before the open one" || t FAIL "answer: closed then open ($HB)"
{ echo "$H1"; rep 119000 a; echo; printf 'prose then -----BEGIN TEST BLOCK----- on one line '; rep 5000 b; } | mk_exec "$W/inline.json"; handed "$W/inline.json"
[ "$H" = "$H1"$'\n'"$(rep 119000 a)"$'\n\n(truncated)' ] && t PASS "answer: prose and BEGIN on one line across the cap: that whole line is dropped, the cut is at the line break before it" || t FAIL "answer: inline BEGIN ($HB)"
# The exact cap boundaries (LIMIT 120000, keep = LIMIT - 13 = 119987):
{ rep 119999 a; echo; } | mk_exec "$W/b0.json"; handed "$W/b0.json"; [ "$HB" = 119999 ] && ! grep -q "(truncated)" <<<"$H" && t PASS "answer: 119999 bytes plus a trailing newline (120000) pass whole, no marker" || t FAIL "answer: 120000 ($HB)"
{ rep 60000 a; echo; rep 59999 b; } | mk_exec "$W/b1.json"; handed "$W/b1.json"; [ "$HB" = 120000 ] && ! grep -q "(truncated)" <<<"$H" && t PASS "answer: exactly 120000 bytes pass whole, no marker" || t FAIL "answer: exactly 120000 ($HB)"
{ rep 60000 a; echo; rep 60000 b; } | mk_exec "$W/b2.json"; handed "$W/b2.json"; [ "$H" = "$(rep 60000 a)"$'\n\n(truncated)' ] && t PASS "answer: 120001 bytes are cut (at the line break)" || t FAIL "answer: 120001 ($HB)"
{ rep 119987 a; echo; rep 100 b; } | mk_exec "$W/b3.json"; handed "$W/b3.json"; [ "$HB" = 120000 ] && [ "$H" = "$(rep 119987 a)"$'\n\n(truncated)' ] && t PASS "answer: a line break at byte 119987 (= keep) is used: exactly 120000 bytes with the marker" || t FAIL "answer: keep boundary ($HB)"
{ rep 119988 a; echo; rep 100 b; } | mk_exec "$W/b4.json"; handed "$W/b4.json"; [ "$H" = "$WITHHELD" ] && t PASS "answer: a line break at byte 119988 (= keep + 1) is past the cap and not used: withheld" || t FAIL "answer: keep+1 boundary ($HB)"
{ rep 100 a; echo; rep 119886 b; printf ' '; rep 100 c; } | mk_exec "$W/b5.json"; handed "$W/b5.json"; [ "$H" = "$(rep 100 a)"$'\n'"$(rep 119886 b)"$'\n\n(truncated)' ] && t PASS "answer: a blank at byte 119987 is used (the later of line break and blank)" || t FAIL "answer: blank at keep ($HB)"
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
# The scan before the hand-off (the post job's log header shows the handed text, and the repo is public):
printf 'REVIEW TEAM RESULT: PASS\nkey LEAKME here\n' | mk_exec "$W/leak.json"; handed "$W/leak.json"
[ "$rc" = 0 ] && [ "$H" = "(answer withheld: it contained something that looks like a secret)" ] && t PASS "answer: a secret in the answer never reaches the job output; a fixed notice is handed over" || t FAIL "answer: leak ($rc) $H"
out=$(bash "$SCRIPT" answer "$W/leak.json" 2>&1); grep -q "LEAKME" <<<"$out" && t FAIL "answer: the secret text appeared in the output" || t PASS "answer: nothing of the secret is printed"
{ rep 100 a; echo; rep 119900 y; echo; echo "key LEAKME here"; } | mk_exec "$W/leak2.json"; handed "$W/leak2.json"   # the secret is past the cut: the scan sees the cut text
[ "$H" = "$(rep 100 a)"$'\n\n(truncated)' ] && t PASS "answer: the scan runs on the cut text (a secret dropped by the cut is not there to withhold)" || t FAIL "answer: leak after cut ($HB)"
out=$(GL_RC=2 bash "$SCRIPT" answer "$W/exec.json" 2>&1); rc=$?
[ "$rc" != 0 ] && ! grep -q "answer<<\|has_result" <<<"$out" && grep -q "secret scan failed with exit code 2" <<<"$out" && t PASS "answer: a scanner error exits non-zero and hands nothing over" || t FAIL "answer: scanner error (rc=$rc)"
out=$(GITLEAKS_SHA256=0000000000000000000000000000000000000000000000000000000000000000 bash "$SCRIPT" answer "$W/exec.json" 2>&1); rc=$?
[ "$rc" != 0 ] && ! grep -q "answer<<\|has_result\|REVIEW TEAM" <<<"$out" && grep -q "has sha256" <<<"$out" && t PASS "answer: a scanner whose sha256 is not the pinned one is an error: nothing handed over, the mismatch in the log" || t FAIL "answer: wrong hash (rc=$rc)"
out=$(GITLEAKS_SHA256=0000000000000000000000000000000000000000000000000000000000000000 bash "$SCRIPT" blocked "$W/exec.json" 2>&1); rc=$?
[ "$rc" != 0 ] && ! grep -q "BLOCKED" <<<"$out" && t PASS "blocked: a scanner with the wrong sha256 prints no denial line" || t FAIL "blocked: wrong hash (rc=$rc)"
# The scan runs a private copy: a stub that overwrites the original with something else on its first run still gets the
# hash check (on the copy) and the scan (the copy) right, and the original's later content never matters.
S3=$(mktemp -d "$W/swap.XXXXXX"); printf '#!/usr/bin/env bash\nprintf "#!/usr/bin/env bash\\nexit 0\\n" > "%s/gitleaks"; src=""; for a in "$@"; do case "$a" in --source=*) src=${a#--source=};; esac; done; grep -q LEAKME "$src"/* && exit 3; exit 0\n' "$S3" > "$S3/gitleaks"; chmod +x "$S3/gitleaks"
printf 'REVIEW TEAM RESULT: PASS\nkey LEAKME\n' | mk_exec "$W/swapleak.json"
out=$(GITLEAKS_BIN="$S3/gitleaks" GITLEAKS_SHA256=$(sha256sum "$S3/gitleaks" | cut -c1-64) bash "$SCRIPT" answer "$W/swapleak.json"); H=$(handoff_text "$out")
[ "$H" = "(answer withheld: it contained something that looks like a secret)" ] && t PASS "answer: the scan runs a private copy of the scanner (a self-replacing original still scans with the checked copy)" || t FAIL "answer: private copy: $H"
S2=$(mktemp -d "$W/fake.XXXXXX"); printf '#!/usr/bin/env bash\necho 0000000000000000000000000000000000000000000000000000000000000000  x\n' > "$S2/sha256sum"; chmod +x "$S2/sha256sum"
out=$(PATH="$S2:$PATH" bash "$SCRIPT" answer "$W/exec.json"); H=$(handoff_text "$out")
[ "$H" = $'REVIEW TEAM RESULT: PASS\nline two' ] && t PASS "answer: a fake sha256sum first on PATH is not used (the scan calls /usr/bin/sha256sum)" || t FAIL "answer: fake sha256sum on PATH: $H"
out=$(GITLEAKS_BIN="$W/no-such-gitleaks" bash "$SCRIPT" answer "$W/exec.json" 2>&1); rc=$?
[ "$rc" != 0 ] && ! grep -q "answer<<\|has_result\|REVIEW TEAM" <<<"$out" && grep -q "no gitleaks at" <<<"$out" && t PASS "answer: no scanner at all is an error: exit non-zero, nothing handed over, the cause in the log" || t FAIL "answer: no scanner (rc=$rc)"
# The cutter's own edge cases (through the hand-off, with the stub scanner):
{ echo "REVIEW TEAM RESULT: PASS"; echo '-----END TEST BLOCK-----'; rep 119900 y; echo; rep 5000 z; } | mk_exec "$W/strayend.json"; handed "$W/strayend.json"
[ "$H" = "REVIEW TEAM RESULT: PASS"$'\n-----END TEST BLOCK-----\n'"$(rep 119900 y)"$'\n\n(truncated)' ] && t PASS "answer: a stray END line that closes nothing changes nothing" || t FAIL "answer: stray END alone ($HB)"
{ printf 'REVIEW TEAM RESULT: PASS\r\n'; rep 119950 y; printf '\r\n'; rep 5000 z; } | mk_exec "$W/crlf.json"; handed "$W/crlf.json"
[ "$H" = $'REVIEW TEAM RESULT: PASS\r\n'"$(rep 119950 y)"$'\r\n\n(truncated)' ] && t PASS "answer: CRLF line breaks: the cut is at the LF (the CR before it is kept, the first line still matches)" || t FAIL "answer: CRLF ($HB)"
{ rep 119000 y; printf '\t'; rep 5000 z; } | mk_exec "$W/tab.json"; handed "$W/tab.json"
[ "$H" = "$(rep 119000 y)"$'\n\n(truncated)' ] && t PASS "answer: with no line break or space, the cut is at the last tab" || t FAIL "answer: tab ($HB)"
# Failures mid-way: exit non-zero, no half-written answer<< block, no temp file.
S=$(mktemp -d "$W/stub.XXXXXX"); E=$(mktemp -d "$W/tmp.XXXXXX")
printf '#!/usr/bin/env bash\nexit 1\n' > "$S/python3"; chmod +x "$S/python3"
out=$(PATH="$S:$PATH" TMPDIR="$E" bash "$SCRIPT" answer "$W/mid.json" 2>&1); rc=$?
[ "$rc" != 0 ] && ! grep -q "answer<<\|has_result" <<<"$out" && [ -z "$(ls -A "$E")" ] && t PASS "answer: python3 failing exits non-zero, prints no output block, leaves no file" || { t FAIL "answer: python3 failure (rc=$rc)"; echo "$out"; }
rm -f "$S/python3"; printf '#!/usr/bin/env bash\n[ "$1" = -r ] && exit 1\nexec %s "$@"\n' "$(command -v jq)" > "$S/jq"; chmod +x "$S/jq"
out=$(PATH="$S:$PATH" TMPDIR="$E" bash "$SCRIPT" answer "$W/mid.json" 2>&1); rc=$?
[ "$rc" != 0 ] && ! grep -q "answer<<\|has_result" <<<"$out" && [ -z "$(ls -A "$E")" ] && t PASS "answer: jq failing on the text exits non-zero, prints no output block, leaves no file" || { t FAIL "answer: jq failure (rc=$rc)"; echo "$out"; }
summary
