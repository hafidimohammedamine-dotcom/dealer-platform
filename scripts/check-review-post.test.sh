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
cat > "$W/gitleaks" <<STUB
#!/usr/bin/env bash
src=""; for a in "\$@"; do case "\$a" in --source=*) src=\${a#--source=};; esac; done
grep -q "LEAKME" "\$src"/* && exit 3; exit \${GL_RC:-0}
STUB
chmod +x "$W/gh" "$W/gitleaks"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-testlib.sh"
A=""; answer() { A="$1"; }   # the answer the next run posts (ANSWER in the post jobs)
run() { # run <name> <expect-rc 0|1> <posted-first-line> <label-arg-expected>
  rm -f "$W/gh.log" "$W/posted.md"
  ANSWER="$A" GH_BIN="$W/gh" GITLEAKS_BIN="$W/gitleaks" bash "$SCRIPT" pr 21 >/dev/null 2>&1; rc=$?
  posted=$(head -n1 "$W/posted.md" 2>/dev/null); labels=$(grep 'pr edit' "$W/gh.log" 2>/dev/null)
  if [ $rc = "$2" ] && [ "$posted" = "$3" ] && grep -qF -- "$4" <<<"$labels$([ "$4" = none ] && echo none)"; then t PASS "$1"
  else t FAIL "$1 (rc=$rc posted='$posted' labels='$labels')"; fi
}
answer $'REVIEW TEAM RESULT: PASS\nall good';  run "PASS posts and labels ready-to-merge" 0 "REVIEW TEAM RESULT: PASS" "--add-label ready-to-merge"
answer $'REVIEW TEAM RESULT: FAIL\n1. x';      run "FAIL posts and labels changes-requested" 0 "REVIEW TEAM RESULT: FAIL" "--add-label changes-requested"
answer $'Looks fine to me\nREVIEW TEAM RESULT: PASS'; run "wrong first line becomes FAIL" 0 "REVIEW TEAM RESULT: FAIL" "--add-label changes-requested"
answer $'REVIEW TEAM RESULT: PASS\nkey LEAKME'; run "secret in answer is withheld and FAILs" 0 "REVIEW TEAM RESULT: FAIL" "--add-label changes-requested"
grep -q LEAKME "$W/posted.md" && { t FAIL "secret text was posted"; } || { t PASS "secret text not posted"; }
answer ""; run "an empty answer becomes FAIL" 0 "REVIEW TEAM RESULT: FAIL" "--add-label changes-requested"
answer $'REVIEW TEAM RESULT: PASS\nok'; export GL_RC=2; run "gitleaks error stops without posting" 1 "" none; unset GL_RC
out=$(ANSWER="$A" GH_BIN="$W/gh" GITLEAKS_BIN="$W/gitleaks" bash "$SCRIPT" pr "1;x" 2>&1); [ $? != 0 ] && { t PASS "bad PR number rejected"; } || { t FAIL "bad PR number"; }
issue_run() { rm -f "$W/gh.log" "$W/posted.md"; ANSWER="$A" GH_BIN="$W/gh" GITLEAKS_BIN="$W/gitleaks" bash "$SCRIPT" issue 2 >/dev/null 2>&1; }
answer $'DAILY REPORT\nall quiet'; issue_run; rc=$?
[ $rc = 0 ] && grep -q '^issue comment 2' "$W/gh.log" && ! grep -q 'pr edit' "$W/gh.log" && { t PASS "issue mode posts a comment, no labels"; } || { t FAIL "issue mode"; cat "$W/gh.log"; }
answer $'report with LEAKME'; issue_run
grep -q LEAKME "$W/posted.md" && { t FAIL "issue mode posted a secret"; } || { t PASS "issue mode withholds secrets"; }
out=$(ANSWER="$A" GH_BIN="$W/gh" GITLEAKS_BIN="$W/gitleaks" bash "$SCRIPT" other 2 2>&1); [ $? != 0 ] && { t PASS "bad mode rejected"; } || { t FAIL "bad mode"; }
# The answer from the environment (the post jobs), and the daily-reports target
rm -f "$W/gh.log" "$W/posted.md"; ANSWER=$'REVIEW TEAM RESULT: PASS\nfrom env' GH_BIN="$W/gh" GITLEAKS_BIN="$W/gitleaks" bash "$SCRIPT" pr 21 >/dev/null 2>&1; rc=$?
[ $rc = 0 ] && grep -q "from env" "$W/posted.md" && grep -q "add-label ready-to-merge" "$W/gh.log" && t PASS "ANSWER from the environment" || t FAIL "ANSWER env ($rc)"
rm -f "$W/gh.log" "$W/posted.md"; ANSWER="report text" STUB_DAILY_NUMBER=42 GH_BIN="$W/gh" GITLEAKS_BIN="$W/gitleaks" bash "$SCRIPT" daily-reports >/dev/null 2>&1; rc=$?
[ $rc = 0 ] && grep -q "issue comment 42" "$W/gh.log" && grep -q "report text" "$W/posted.md" && ! grep -q "issue create" "$W/gh.log" && t PASS "daily-reports: posts on the existing Daily reports issue" || { t FAIL "daily-reports existing ($rc)"; cat "$W/gh.log"; }
rm -f "$W/gh.log" "$W/posted.md"; ANSWER="report text" STUB_CREATED_NUMBER=77 GH_BIN="$W/gh" GITLEAKS_BIN="$W/gitleaks" bash "$SCRIPT" daily-reports >/dev/null 2>&1; rc=$?
[ $rc = 0 ] && grep -q "issue create --title Daily reports" "$W/gh.log" && grep -q "issue comment 77" "$W/gh.log" && t PASS "daily-reports: creates the issue when missing" || { t FAIL "daily-reports create ($rc)"; cat "$W/gh.log"; }
rm -f "$W/gh.log"; out=$(ANSWER="x" STUB_CREATED_NUMBER=nope GH_BIN="$W/gh" GITLEAKS_BIN="$W/gitleaks" bash "$SCRIPT" daily-reports 2>&1); rc=$?
[ $rc = 1 ] && grep -q "could not find or create the Daily reports issue" <<<"$out" && t PASS "daily-reports: a bad issue number fails" || t FAIL "daily-reports bad number ($rc)"
rm -f "$W/gh.log" "$W/posted.md"; ANSWER="" GH_BIN="$W/gh" GITLEAKS_BIN="$W/gitleaks" bash "$SCRIPT" issue 2 >/dev/null 2>&1; rc=$?
[ $rc = 0 ] && grep -q "did not produce an answer" "$W/posted.md" && t PASS "issue mode with an empty answer posts the placeholder" || t FAIL "empty answer ($rc)"
summary
