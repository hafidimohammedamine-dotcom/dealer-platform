#!/usr/bin/env bash
# Tests scripts/check-review-post.sh with stub gh and gitleaks.
set -uo pipefail
SCRIPT="$(cd "$(dirname "$0")" && pwd)/check-review-post.sh"
TMPROOT="${TMPDIR:-/tmp}"
command -v jq >/dev/null || { echo "ERROR: jq required"; exit 2; }
W=$(mktemp -d "$TMPROOT/rpt.XXXXXX") || exit 2; trap 'rm -rf "$W"' EXIT
cat > "$W/gh" <<STUB
#!/usr/bin/env bash
echo "\$*" >> "$W/gh.log"
if [ "\$1 \$2" = "pr comment" ] || [ "\$1 \$2" = "issue comment" ]; then while [ \$# -gt 0 ]; do [ "\$1" = --body-file ] && cp "\$2" "$W/posted.md"; shift; done; fi
[ "\$1 \$2" = "issue list" ] && printf '%s\n' "\${STUB_DAILY_NUMBER:-}"
[ "\$1 \$2" = "issue create" ] && printf 'https://github.com/o/r/issues/%s\n' "\${STUB_CREATED_NUMBER:-77}"
exit 0
STUB
chmod +x "$W/gh"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-testlib.sh"
write_gitleaks_stub "$W"; export GITLEAKS_SHA256=$(sha256sum "$W/gitleaks" | cut -c1-64)   # the scan checks the hash
A=""; answer() { A="$1"; }   # the answer the next run posts (ANSWER in the post jobs)
run() { # run <name> <expect-rc 0|1> <posted-first-line> <label-arg-expected>
  rm -f "$W/gh.log" "$W/posted.md"
  ANSWER="$A" GH_BIN="$W/gh" GITLEAKS_BIN="$W/gitleaks" bash "$SCRIPT" pr 21 >/dev/null 2>&1; rc=$?
  posted=$(head -n1 "$W/posted.md" 2>/dev/null); labels=$(grep 'pr edit' "$W/gh.log" 2>/dev/null)
  if [ $rc = "$2" ] && [ "$posted" = "$3" ] && grep -qF -- "$4" <<<"$labels$([ "$4" = none ] && echo none)"; then t PASS "$1"
  else t FAIL "$1 (rc=$rc posted='$posted' labels='$labels')"; fi
}
# The locale probe at the top of the script: under a byte-counting locale "é" is 2 characters and the script must stop.
LC_ALL=C bash -c 'p=$'"'"'\xc3\xa9'"'"'; [ "${#p}" = 2 ]' && t PASS "locale probe: a byte-counting locale makes the probe fail (what the script checks before cutting)" || t FAIL "locale probe"
LC_ALL=C.UTF-8 bash -c 'p=$'"'"'\xc3\xa9'"'"'; [ "${#p}" = 1 ]' && t PASS "locale probe: C.UTF-8 counts characters on this runner" || t FAIL "locale probe utf-8"
# The probe inside the real script: a byte-counting locale stops it before anything is posted.
rm -f "$W/gh.log" "$W/posted.md"; out=$(LOCALE_PROBE=ab ANSWER=$'REVIEW TEAM RESULT: PASS\nok' GH_BIN="$W/gh" GITLEAKS_BIN="$W/gitleaks" bash "$SCRIPT" pr 21 2>&1); rc=$?
[ $rc = 1 ] && grep -q "C.UTF-8 locale is missing" <<<"$out" && [ ! -f "$W/posted.md" ] && [ ! -f "$W/gh.log" ] && t PASS "locale probe inside the script: exit 1, nothing posted, no label change" || t FAIL "locale probe in script (rc=$rc)"
# A missing scanner in every mode: exit non-zero, no comment, no label change.
for m in "pr 21" "issue 2" "daily-reports"; do
  rm -f "$W/gh.log" "$W/posted.md"; out=$(ANSWER=$'REVIEW TEAM RESULT: PASS\nok' STUB_DAILY_NUMBER=42 GH_BIN="$W/gh" GITLEAKS_BIN="$W/no-such" bash "$SCRIPT" $m 2>&1); rc=$?
  [ $rc != 0 ] && grep -q "no gitleaks at" <<<"$out" && [ ! -f "$W/posted.md" ] && ! grep -q "comment\|pr edit" "$W/gh.log" 2>/dev/null && t PASS "no scanner ($m): exit non-zero, nothing posted, no label change" || t FAIL "no scanner ($m) rc=$rc"
done
rm -f "$W/gh.log" "$W/posted.md"; out=$(ANSWER=$'REVIEW TEAM RESULT: PASS\nok' GH_BIN="$W/gh" GITLEAKS_BIN="$W/gitleaks" GITLEAKS_SHA256=0000000000000000000000000000000000000000000000000000000000000000 bash "$SCRIPT" pr 21 2>&1); rc=$?
[ $rc != 0 ] && grep -q "has sha256" <<<"$out" && [ ! -f "$W/posted.md" ] && t PASS "a scanner with the wrong sha256: exit non-zero, nothing posted" || t FAIL "wrong hash rc=$rc"
answer $'REVIEW TEAM RESULT: PASS\nall good';  run "PASS posts and labels ready-to-merge" 0 "REVIEW TEAM RESULT: PASS" "--add-label ready-to-merge"
answer $'REVIEW TEAM RESULT: FAIL\n1. x';      run "FAIL posts and labels changes-requested" 0 "REVIEW TEAM RESULT: FAIL" "--add-label changes-requested"
answer $'Looks fine to me\nREVIEW TEAM RESULT: PASS'; run "wrong first line becomes FAIL" 0 "REVIEW TEAM RESULT: FAIL" "--add-label changes-requested"
answer $'REVIEW TEAM RESULT: PASS\nkey LEAKME'; run "secret in answer is withheld and FAILs" 0 "REVIEW TEAM RESULT: FAIL" "--add-label changes-requested"
grep -q LEAKME "$W/posted.md" && { t FAIL "secret text was posted"; } || { t PASS "secret text not posted"; }
answer ""; run "an empty answer becomes FAIL" 0 "REVIEW TEAM RESULT: FAIL" "--add-label changes-requested"
answer $'REVIEW TEAM RESULT: PASS\nok'; export GL_RC=2; run "gitleaks error stops without posting" 1 "" none; unset GL_RC
# 119900 x after the first line: the largest answer the hand-off can deliver (120000 bytes, one environment variable), far past
# the 64 KiB pipe buffer, so the old `printf | head -n1` always died of SIGPIPE here (rc 141, nothing posted).
answer "REVIEW TEAM RESULT: FAIL"$'\n'"$(rep 119900 x)"; run "a long answer (over 60000 characters) is still posted: no SIGPIPE on the first-line cut" 0 "REVIEW TEAM RESULT: FAIL" "--add-label changes-requested"
chars() { python3 -c 'import sys; print(len(open(sys.argv[1], encoding="utf-8").read()))' "$1"; }   # characters, not bytes
check "long answer: the posted body is exactly 60000 characters plus the marker" bash -c 'grep -q "(truncated)" "$1" && [ "$2" = 60014 ]' _ "$W/posted.md" "$(chars "$W/posted.md")"
answer "REVIEW TEAM RESULT: PASS"$'\n'"$(rep 90000 x)"; run "a long PASS answer is posted with the pass labels" 0 "REVIEW TEAM RESULT: PASS" "--add-label ready-to-merge"
answer "$(rep 90000 x)"; run "a long answer with no newline is the invalid-format FAIL, not posted as is" 0 "REVIEW TEAM RESULT: FAIL" "--add-label changes-requested"
check "long single-line answer: the placeholder was posted, not the text" bash -c '! grep -q "xxxxxxxxxx" "$1"' _ "$W/posted.md"
answer $'REVIEW TEAM RESULT: PASS\r\nall good'; run "a CR on the first line still matches PASS" 0 $'REVIEW TEAM RESULT: PASS\r' "--add-label ready-to-merge"
# The first line plus its newline is 25 characters: 25 + 59972 x puts LEAKME at characters 59997-60002, across the cut.
answer "REVIEW TEAM RESULT: FAIL"$'\n'"$(rep 59972 x)LEAKME"; run "a secret straddling the 60000 cut is caught: the whole answer is scanned before the cut" 0 "REVIEW TEAM RESULT: FAIL" "--add-label changes-requested"
check "straddling secret: nothing of the answer was posted" bash -c '! grep -q "LEAK\|xxxxxxxxxx" "$1" && grep -q "looks like a secret" "$1"' _ "$W/posted.md"
answer "REVIEW TEAM RESULT: FAIL"$'\n'"$(rep 59997 x)LEAKME"; run "a secret after the cut is caught" 0 "REVIEW TEAM RESULT: FAIL" "--add-label changes-requested"
check "secret after the cut: nothing of the answer was posted" bash -c '! grep -q "LEAK\|xxxxxxxxxx" "$1"' _ "$W/posted.md"
# A minimum-length rule (TOKEN_ + 20 characters): the whole token sits across the cut, so the cut text alone is too short for it
answer "REVIEW TEAM RESULT: FAIL"$'\n'"$(rep 59965 x)TOKEN_ABCDEFGHIJKLMNOPQRST"; run "a long token across the cut is too short for its rule in the cut text, caught in the whole answer" 0 "REVIEW TEAM RESULT: FAIL" "--add-label changes-requested"
check "long token across the cut: not posted" bash -c '! grep -q "TOKEN_" "$1"' _ "$W/posted.md"
# A rule that matches only at the end of a file: the post body ends with the cut text, the whole answer does not
answer "REVIEW TEAM RESULT: FAIL"$'\n'"$(rep 59969 x)ENDTOK$(rep 100 y)"; run "the posted text itself is scanned too (a rule that matches only the cut-off text)" 0 "REVIEW TEAM RESULT: FAIL" "--add-label changes-requested"
check "post-body-only match: not posted" bash -c '! grep -q "ENDTOK\|xxxxxxxxxx" "$1" && grep -q "looks like a secret" "$1"' _ "$W/posted.md"
# Boundaries: exactly 60000 characters is posted whole; 60001 is cut; multibyte characters count as characters
answer "REVIEW TEAM RESULT: PASS"$'\n'"$(rep 59975 x)"; run "exactly 60000 characters: posted whole" 0 "REVIEW TEAM RESULT: PASS" "--add-label ready-to-merge"
check "60000: not truncated" bash -c '! grep -q "(truncated)" "$1" && [ "$2" = 60001 ]' _ "$W/posted.md" "$(chars "$W/posted.md")"
answer "REVIEW TEAM RESULT: PASS"$'\n'"$(rep 59976 x)"; run "60001 characters: truncated" 0 "REVIEW TEAM RESULT: PASS" "--add-label ready-to-merge"
check "60001: cut at 60000 characters plus the marker" bash -c 'grep -q "(truncated)" "$1" && [ "$2" = 60014 ]' _ "$W/posted.md" "$(chars "$W/posted.md")"
answer "REVIEW TEAM RESULT: PASS"$'\n'"$(python3 -c 'print("é" * 30000 + "x" * 40000, end="")')"; run "a multibyte answer is cut by characters, not bytes" 0 "REVIEW TEAM RESULT: PASS" "--add-label ready-to-merge"
check "multibyte: 60000 characters kept" bash -c '[ "$2" = 60014 ] && grep -q "(truncated)" "$1"' _ "$W/posted.md" "$(chars "$W/posted.md")"
answer "REVIEW TEAM RESULT: PASS"$'\n'"$(python3 -c 'print("x" * 59974 + "\U0001F600" * 3, end="")')"; run "a four-byte character at character 59999 (on the cut)" 0 "REVIEW TEAM RESULT: PASS" "--add-label ready-to-merge"
check "four-byte on the cut: posted text is valid UTF-8, 60000 characters kept, the emoji at 59999 whole" bash -c 'python3 -c "import sys; t=open(sys.argv[1],encoding=\"utf-8\").read(); assert len(t)==60014, len(t); assert t[59999]==\"\U0001F600\" and t[60000]==\"\n\"" "$1"' _ "$W/posted.md"
# gitleaks failing or finding on a long answer
answer "REVIEW TEAM RESULT: PASS"$'\n'"$(rep 90000 x)"; export GL_RC=2; run "a long answer with a gitleaks error: exit 1, nothing posted" 1 "" none; unset GL_RC
answer "REVIEW TEAM RESULT: PASS"$'\n'"$(rep 90000 x)LEAKME"; run "a long answer with a secret: the placeholder, labels changes-requested" 0 "REVIEW TEAM RESULT: FAIL" "--add-label changes-requested"
out=$(ANSWER="$A" GH_BIN="$W/gh" GITLEAKS_BIN="$W/gitleaks" bash "$SCRIPT" pr "1;x" 2>&1); [ $? != 0 ] && { t PASS "bad PR number rejected"; } || { t FAIL "bad PR number"; }
issue_run() { rm -f "$W/gh.log" "$W/posted.md"; ANSWER="$A" GH_BIN="$W/gh" GITLEAKS_BIN="$W/gitleaks" bash "$SCRIPT" issue 2 >/dev/null 2>&1; }
daily_run() { rm -f "$W/gh.log" "$W/posted.md"; ANSWER="$A" STUB_DAILY_NUMBER=42 GH_BIN="$W/gh" GITLEAKS_BIN="$W/gitleaks" bash "$SCRIPT" daily-reports >/dev/null 2>&1; }
answer $'DAILY REPORT\nall quiet'; issue_run; rc=$?
[ $rc = 0 ] && grep -q '^issue comment 2' "$W/gh.log" && ! grep -q 'pr edit' "$W/gh.log" && { t PASS "issue mode posts a comment, no labels"; } || { t FAIL "issue mode"; cat "$W/gh.log"; }
answer $'report with LEAKME'; issue_run
grep -q LEAKME "$W/posted.md" && { t FAIL "issue mode posted a secret"; } || { t PASS "issue mode withholds secrets"; }
answer "DAILY REPORT"$'\n'"$(rep 90000 x)"; issue_run; rc=$?
[ $rc = 0 ] && grep -q "(truncated)" "$W/posted.md" && ! grep -q 'pr edit' "$W/gh.log" && [ "$(chars "$W/posted.md")" -lt 60100 ] && t PASS "issue mode: a long answer is posted cut, no labels" || t FAIL "issue mode long ($rc)"
answer "DAILY REPORT"$'\n'"$(rep 59985 x)LEAKME"; issue_run; rc=$?
[ $rc = 0 ] && ! grep -q "LEAK\|xxxxxxxxxx" "$W/posted.md" && grep -q "looks like a secret" "$W/posted.md" && t PASS "issue mode: a secret straddling the cut is withheld" || t FAIL "issue mode straddle ($rc)"
answer "DAILY REPORT"$'\n'"$(rep 90000 x)"; daily_run; rc=$?
[ $rc = 0 ] && grep -q "issue comment 42" "$W/gh.log" && grep -q "(truncated)" "$W/posted.md" && t PASS "daily-reports: a long report is posted cut" || t FAIL "daily-reports long ($rc)"
answer "DAILY REPORT"$'\n'"$(rep 59985 x)LEAKME"; daily_run; rc=$?
[ $rc = 0 ] && ! grep -q "LEAK\|xxxxxxxxxx" "$W/posted.md" && t PASS "daily-reports: a secret straddling the cut is withheld" || t FAIL "daily-reports straddle ($rc)"
answer ""; daily_run; rc=$?
[ $rc = 0 ] && grep -q "issue comment 42" "$W/gh.log" && grep -q "did not produce an answer" "$W/posted.md" && t PASS "daily-reports: an empty report posts the placeholder" || t FAIL "daily-reports empty ($rc)"
answer "Weekly audit"$'\r\n'"$(rep 90000 x)"; issue_run; rc=$?
[ $rc = 0 ] && grep -q "^Weekly audit" "$W/posted.md" && grep -q "(truncated)" "$W/posted.md" && ! grep -q 'pr edit' "$W/gh.log" && t PASS "issue mode: a long answer with a CR first line and no REVIEW header is posted as is (cut), no format check" || t FAIL "issue mode CR long ($rc)"
answer "DAILY REPORT"$'\n'"$(rep 90000 x)"; export GL_RC=2; issue_run; rc=$?; unset GL_RC
[ $rc = 1 ] && [ ! -f "$W/posted.md" ] && t PASS "issue mode: a long answer with a gitleaks error posts nothing, exit 1" || t FAIL "issue mode long gitleaks error ($rc)"
# End to end: the hand-off script (check-claude-answer.sh) then this script.
HANDOFF="$(cd "$(dirname "$0")" && pwd)/check-claude-answer.sh"
e2e() { # e2e <exec.json>: hand off, then post what was handed (A = the handed text)
  A=$(handoff_text "$(GITLEAKS_BIN="$W/gitleaks" bash "$HANDOFF" answer "$1")"); rm -f "$W/gh.log" "$W/posted.md"
  ANSWER="$A" GH_BIN="$W/gh" GITLEAKS_BIN="$W/gitleaks" bash "$SCRIPT" pr 21 >/dev/null 2>&1; rc=$?; }
python3 -c 'print("REVIEW TEAM RESULT: FAIL\n"+"x"*59972+"LEAKME"+"y"*30000, end="")' | mk_exec "$W/e2e.json"
e2e "$W/e2e.json"
[ $rc = 0 ] && [ "$A" = "(answer withheld: it contained something that looks like a secret)" ] && ! grep -q "LEAK\|xxxxxxxxxx" "$W/posted.md" && grep -q "did not produce a valid result" "$W/posted.md" && grep -q "add-label changes-requested" "$W/gh.log" \
  && t PASS "end to end: the hand-off's own scan withholds the whole answer with a secret; the post job posts the invalid-result FAIL (its own straddle scan is tested above)" || t FAIL "end to end (rc=$rc, handed ${#A} characters)"
# 70000 four-byte characters (280000 bytes) in blank-separated runs: the hand-off keeps under 120000 bytes, which is under
# 60000 characters, so this script's own cut never runs; the hand-off's (truncated) line tells the reader the end is missing.
python3 -c 'print("REVIEW TEAM RESULT: PASS\n"+("\U0001F600"*100+" ")*700, end="")' | mk_exec "$W/wide.json"
e2e "$W/wide.json"
[ $rc = 0 ] && [ "$(chars "$W/posted.md")" -lt 60000 ] && [ "$(chars "$W/posted.md")" -gt 29000 ] && [ "$(tail -n1 "$W/posted.md")" = "(truncated)" ] && grep -q "add-label ready-to-merge" "$W/gh.log" \
  && t PASS "end to end: 70000 four-byte characters are posted under 60000 characters with the hand-off's (truncated) line" || t FAIL "end to end wide (rc=$rc, $(chars "$W/posted.md") characters)"
# A token straddling the hand-off's 120000-byte cap is dropped whole at the hand-off (the cut moves back to the line break),
# so nothing of it reaches gitleaks or the comment; the comment is the 60000 cut with its marker.
python3 -c 'print("REVIEW TEAM RESULT: FAIL\n"+"y"*119900+"\nTOKEN_AAAAAAAAAAAAAAAAAAAA"+"z"*100, end="")' | mk_exec "$W/cap.json"
e2e "$W/cap.json"
[ $rc = 0 ] && ! grep -q "TOKEN" <<<"$A" && [ "$(chars "$W/posted.md")" = 60014 ] && grep -q "^yyyy" "$W/posted.md" && grep -q "add-label changes-requested" "$W/gh.log" \
  && t PASS "end to end: a token across the 120000-byte cap is never handed over, and the long text is posted cut at 60000" || t FAIL "end to end cap (rc=$rc, $(chars "$W/posted.md") characters)"
# A key block across the 120000-byte cap after multibyte filler (under 60000 characters, so this script's own cut never
# runs): the hand-off drops the block whole, so no BEGIN line reaches gitleaks or the comment.
python3 -c 'print("REVIEW TEAM RESULT: PASS\n"+("\U0001F600"*100+" ")*280+"\n-----BEGIN TEST BLOCK-----\nBLOCKBODY"+"0"*60000+"\n-----END TEST BLOCK-----\n", end="")' | mk_exec "$W/pem.json"
e2e "$W/pem.json"
[ $rc = 0 ] && ! grep -q "BEGIN\|BLOCKBODY" <<<"$A" && ! grep -q "BEGIN\|BLOCKBODY" "$W/posted.md" && [ "$(tail -n1 "$W/posted.md")" = "(truncated)" ] && grep -q "add-label ready-to-merge" "$W/gh.log" \
  && t PASS "end to end: a key block across the hand-off cap after multibyte filler is never handed over or posted" || t FAIL "end to end pem (rc=$rc)"
# The cut landing inside the END line of a block (8 bytes in, on its first blank): the block is open at the cut, so the
# hand-off drops it whole and nothing of it is posted.
n=$((119987 - 8 - 25 - 1 - 27 - 10 - 1)); { echo "REVIEW TEAM RESULT: PASS"; rep "$n" y; echo; echo '-----BEGIN TEST BLOCK-----'; echo BLOCKBODY; printf -- '-----END TEST BLOCK-----\n'; rep 5000 z; } | mk_exec "$W/endline.json"
e2e "$W/endline.json"
[ $rc = 0 ] && ! grep -q "BEGIN\|BLOCKBODY" <<<"$A" && ! grep -q "BEGIN\|BLOCKBODY" "$W/posted.md" && grep -q "(truncated)" "$W/posted.md" && grep -q "add-label ready-to-merge" "$W/gh.log" \
  && t PASS "end to end: a block whose END line straddles the hand-off cap is never handed over or posted" || t FAIL "end to end END line (rc=$rc)"
# With the real pinned gitleaks and the repo's .gitleaks.toml (skipped when the binary is not installed): a fake key block
# across the 120000-byte cap and a fake Claude token across the 60000-character cut are both kept out of the comment
# (the key markers are spelled in pieces so this file itself never matches the private-key rule in the commit scan).
REAL="${GITLEAKS:-/tmp/gitleaks}"
if [ -x "$REAL" ]; then
  python3 -c 'print("REVIEW TEAM RESULT: PASS\n"+"x"*59980+"sk-ant-api03-"+"A"*40+"\n"+"y"*59900+"\n-----BEGIN RSA "+"PRIV"+"ATE KEY-----\n"+"MIIE"+"A"*60+"\n"+"B"*64+"\n-----END RSA "+"PRIV"+"ATE KEY-----\n", end="")' | mk_exec "$W/real.json"
  A=$(handoff_text "$(GITLEAKS_BIN="$REAL" GITLEAKS_SHA256= bash "$HANDOFF" answer "$W/real.json")"); rm -f "$W/gh.log" "$W/posted.md"
  ANSWER="$A" GH_BIN="$W/gh" GITLEAKS_BIN="$REAL" GITLEAKS_SHA256= bash "$SCRIPT" pr 21 >/dev/null 2>&1; rc=$?
  [ $rc = 0 ] && ! grep -q "sk-ant\|BEGIN\|MIIE" "$W/posted.md" && grep -q "add-label changes-requested" "$W/gh.log" \
    && t PASS "real gitleaks: a fake Claude token across the 60000 cut and a key block across the 120000 cap never reach the comment" || t FAIL "real gitleaks end to end (rc=$rc)"
else t PASS "real gitleaks end to end: skipped (no binary at $REAL)"; fi
out=$(ANSWER="$A" GH_BIN="$W/gh" GITLEAKS_BIN="$W/gitleaks" bash "$SCRIPT" other 2 2>&1); [ $? != 0 ] && { t PASS "bad mode rejected"; } || { t FAIL "bad mode"; }
# The answer from the environment (the post jobs), and the daily-reports target
rm -f "$W/gh.log" "$W/posted.md"; ANSWER=$'REVIEW TEAM RESULT: PASS\nfrom env' GH_BIN="$W/gh" GITLEAKS_BIN="$W/gitleaks" bash "$SCRIPT" pr 21 >/dev/null 2>&1; rc=$?
[ $rc = 0 ] && grep -q "from env" "$W/posted.md" && grep -q "add-label ready-to-merge" "$W/gh.log" && t PASS "ANSWER from the environment" || t FAIL "ANSWER env ($rc)"
answer "report text"; daily_run; rc=$?
[ $rc = 0 ] && grep -q "issue comment 42" "$W/gh.log" && grep -q "report text" "$W/posted.md" && ! grep -q "issue create" "$W/gh.log" && t PASS "daily-reports: posts on the existing Daily reports issue" || { t FAIL "daily-reports existing ($rc)"; cat "$W/gh.log"; }
rm -f "$W/gh.log" "$W/posted.md"; ANSWER="report text" STUB_CREATED_NUMBER=77 GH_BIN="$W/gh" GITLEAKS_BIN="$W/gitleaks" bash "$SCRIPT" daily-reports >/dev/null 2>&1; rc=$?
[ $rc = 0 ] && grep -q "issue create --title Daily reports" "$W/gh.log" && grep -q "issue comment 77" "$W/gh.log" && t PASS "daily-reports: creates the issue when missing" || { t FAIL "daily-reports create ($rc)"; cat "$W/gh.log"; }
rm -f "$W/gh.log"; out=$(ANSWER="x" STUB_CREATED_NUMBER=nope GH_BIN="$W/gh" GITLEAKS_BIN="$W/gitleaks" bash "$SCRIPT" daily-reports 2>&1); rc=$?
[ $rc = 1 ] && grep -q "could not find or create the Daily reports issue" <<<"$out" && t PASS "daily-reports: a bad issue number fails" || t FAIL "daily-reports bad number ($rc)"
rm -f "$W/gh.log" "$W/posted.md"; ANSWER="" GH_BIN="$W/gh" GITLEAKS_BIN="$W/gitleaks" bash "$SCRIPT" issue 2 >/dev/null 2>&1; rc=$?
[ $rc = 0 ] && grep -q "did not produce an answer" "$W/posted.md" && t PASS "issue mode with an empty answer posts the placeholder" || t FAIL "empty answer ($rc)"
summary
