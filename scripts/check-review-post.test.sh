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
STUB
cat > "$W/gitleaks" <<STUB
#!/usr/bin/env bash
src=""; for a in "\$@"; do case "\$a" in --source=*) src=\${a#--source=};; esac; done
grep -q "LEAKME" "\$src"/* && exit 3; exit \${GL_RC:-0}
STUB
chmod +x "$W/gh" "$W/gitleaks"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-testlib.sh"
exec_file() { jq -n --arg t "$1" '[{"type":"system"},{"type":"result","subtype":"success","result":$t}]' > "$W/exec.json"; }
run() { # run <name> <expect-rc 0|1> <posted-first-line> <label-arg-expected>
  rm -f "$W/gh.log" "$W/posted.md"
  GH_BIN="$W/gh" GITLEAKS_BIN="$W/gitleaks" bash "$SCRIPT" pr 21 "$W/exec.json" >/dev/null 2>&1; rc=$?
  posted=$(head -n1 "$W/posted.md" 2>/dev/null); labels=$(grep 'pr edit' "$W/gh.log" 2>/dev/null)
  if [ $rc = "$2" ] && [ "$posted" = "$3" ] && grep -qF -- "$4" <<<"$labels$([ "$4" = none ] && echo none)"; then t PASS "$1"
  else t FAIL "$1 (rc=$rc posted='$posted' labels='$labels')"; fi
}
exec_file $'REVIEW TEAM RESULT: PASS\nall good';  run "PASS posts and labels ready-to-merge" 0 "REVIEW TEAM RESULT: PASS" "--add-label ready-to-merge"
exec_file $'REVIEW TEAM RESULT: FAIL\n1. x';      run "FAIL posts and labels changes-requested" 0 "REVIEW TEAM RESULT: FAIL" "--add-label changes-requested"
exec_file $'Looks fine to me\nREVIEW TEAM RESULT: PASS'; run "wrong first line becomes FAIL" 0 "REVIEW TEAM RESULT: FAIL" "--add-label changes-requested"
exec_file $'REVIEW TEAM RESULT: PASS\nkey LEAKME'; run "secret in answer is withheld and FAILs" 0 "REVIEW TEAM RESULT: FAIL" "--add-label changes-requested"
grep -q LEAKME "$W/posted.md" && { t FAIL "secret text was posted"; } || { t PASS "secret text not posted"; }
rm -f "$W/exec.json"; run "missing execution file becomes FAIL" 0 "REVIEW TEAM RESULT: FAIL" "--add-label changes-requested"
echo 'not json' > "$W/exec.json"; run "broken execution file becomes FAIL" 0 "REVIEW TEAM RESULT: FAIL" "--add-label changes-requested"
exec_file $'REVIEW TEAM RESULT: PASS\nok'; export GL_RC=2; run "gitleaks error stops without posting" 1 "" none; unset GL_RC
out=$(GH_BIN="$W/gh" GITLEAKS_BIN="$W/gitleaks" bash "$SCRIPT" pr "1;x" "$W/exec.json" 2>&1); [ $? != 0 ] && { t PASS "bad PR number rejected"; } || { t FAIL "bad PR number"; }
issue_run() { rm -f "$W/gh.log" "$W/posted.md"; GH_BIN="$W/gh" GITLEAKS_BIN="$W/gitleaks" bash "$SCRIPT" issue 2 "$W/exec.json" >/dev/null 2>&1; }
exec_file $'DAILY REPORT\nall quiet'; issue_run; rc=$?
[ $rc = 0 ] && grep -q '^issue comment 2' "$W/gh.log" && ! grep -q 'pr edit' "$W/gh.log" && { t PASS "issue mode posts a comment, no labels"; } || { t FAIL "issue mode"; cat "$W/gh.log"; }
exec_file $'report with LEAKME'; issue_run
grep -q LEAKME "$W/posted.md" && { t FAIL "issue mode posted a secret"; } || { t PASS "issue mode withholds secrets"; }
out=$(GH_BIN="$W/gh" GITLEAKS_BIN="$W/gitleaks" bash "$SCRIPT" other 2 "$W/exec.json" 2>&1); [ $? != 0 ] && { t PASS "bad mode rejected"; } || { t FAIL "bad mode"; }
summary
