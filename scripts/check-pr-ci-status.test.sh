#!/usr/bin/env bash
# Tests scripts/check-pr-ci-status.sh with a stub 'gh' that returns canned run lists.
set -uo pipefail
SCRIPT="$(cd "$(dirname "$0")" && pwd)/check-pr-ci-status.sh"
TMPROOT="${TMPDIR:-/tmp}"
command -v jq >/dev/null || { echo "ERROR: jq required"; exit 2; }
W=$(mktemp -d "$TMPROOT/ps.XXXXXX") || exit 2; trap 'rm -rf "$W"' EXIT
SHA=0123456789abcdef0123456789abcdef01234567; OTHER=fedcba9876543210fedcba9876543210fedcba98
# Stub: reads $W/ci.json or $W/guards.json depending on --workflow, applies the --jq filter with real jq.
cat > "$W/gh" <<STUB
#!/usr/bin/env bash
wf=""; q=""; while [ \$# -gt 0 ]; do case "\$1" in --workflow) wf=\$2; shift;; --jq) q=\$2; shift;; esac; shift; done
f="$W/\${wf%.yml}.json"; [ -f "\$f" ] || echo '[]' > "\$f"
jq -r "\$q" "\$f"
STUB
chmod +x "$W/gh"
pass=0; failed=0
run() { # run <name> <expected-output> [timeout]
  out=$(GH_BIN="$W/gh" bash "$SCRIPT" 21 "$SHA" "${3:-0}" 0 2>/dev/null); rc=$?
  if [ $rc = 0 ] && [ "$out" = "$2" ]; then pass=$((pass+1)); echo "PASS  $1"; else failed=$((failed+1)); echo "FAIL  $1: got '$out' (rc $rc), want '$2'"; fi
}
ci()     { printf '%s' "$1" > "$W/ci.json"; }
guards() { printf '%s' "$1" > "$W/guards.json"; }
ci "[{\"headSha\":\"$SHA\",\"displayTitle\":\"x\",\"status\":\"completed\",\"conclusion\":\"success\",\"createdAt\":\"2026-10-09T10:00:00Z\"}]"
guards "[{\"headSha\":\"$OTHER\",\"displayTitle\":\"Guards PR #21 @ $SHA\",\"status\":\"completed\",\"conclusion\":\"success\",\"createdAt\":\"2026-10-09T10:00:00Z\"}]"
run "both completed" "ci=success guards=success"
guards "[{\"headSha\":\"$OTHER\",\"displayTitle\":\"Guards PR #21 @ $SHA\",\"status\":\"completed\",\"conclusion\":\"failure\",\"createdAt\":\"2026-10-09T10:00:00Z\"}]"
run "guards failed" "ci=success guards=failure"
guards "[{\"headSha\":\"$OTHER\",\"displayTitle\":\"Guards PR #21 @ $SHA\",\"status\":\"in_progress\",\"conclusion\":null,\"createdAt\":\"2026-10-09T10:00:00Z\"}]"
run "guards still running at timeout" "ci=success guards=pending"
guards '[]'
run "guards missing at timeout" "ci=success guards=pending"
guards "[{\"headSha\":\"$SHA\",\"displayTitle\":\"Guards PR #22 @ $SHA\",\"status\":\"completed\",\"conclusion\":\"success\",\"createdAt\":\"2026-10-09T10:00:00Z\"}]"
run "another PR's guards run is ignored" "ci=success guards=pending"
guards "[{\"headSha\":\"$OTHER\",\"displayTitle\":\"Guards PR #21 @ $SHA\",\"status\":\"completed\",\"conclusion\":\"failure\",\"createdAt\":\"2026-10-09T10:00:00Z\"},{\"headSha\":\"$OTHER\",\"displayTitle\":\"Guards PR #21 @ $SHA\",\"status\":\"completed\",\"conclusion\":\"success\",\"createdAt\":\"2026-10-09T11:00:00Z\"}]"
run "newest run wins (re-run)" "ci=success guards=success"
ci "[{\"headSha\":\"$OTHER\",\"displayTitle\":\"x\",\"status\":\"completed\",\"conclusion\":\"success\",\"createdAt\":\"2026-10-09T10:00:00Z\"}]"
run "CI for another commit is ignored" "ci=pending guards=success"
out=$(GH_BIN="$W/gh" bash "$SCRIPT" "21 x" "$SHA" 0 0 2>&1); [ $? != 0 ] && pass=$((pass+1)) && echo "PASS  bad PR number rejected" || { failed=$((failed+1)); echo "FAIL  bad PR number"; }
out=$(GH_BIN="$W/gh" bash "$SCRIPT" 21 "abc" 0 0 2>&1); [ $? != 0 ] && pass=$((pass+1)) && echo "PASS  bad sha rejected" || { failed=$((failed+1)); echo "FAIL  bad sha"; }
# guards.yml must produce exactly the run title this script looks for (an unquoted '#' in YAML starts a comment).
REPO="$(cd "$(dirname "$SCRIPT")/.." && pwd)"
want='Guards PR #${{ github.event.pull_request.number }} @ ${{ github.event.pull_request.head.sha }}'
got=$(python3 -c 'import sys,yaml; print(yaml.safe_load(open(sys.argv[1]))["run-name"])' "$REPO/.github/workflows/guards.yml" 2>&1)
[ "$got" = "$want" ] && { pass=$((pass+1)); echo "PASS  guards.yml run-name matches what this script looks for"; } || { failed=$((failed+1)); echo "FAIL  guards.yml run-name is '$got'"; }
# Polls again (after sleeping) until both runs finish: the guards run finishes on the second poll.
ci "[{\"headSha\":\"$SHA\",\"displayTitle\":\"x\",\"status\":\"completed\",\"conclusion\":\"success\",\"createdAt\":\"2026-10-09T10:00:00Z\"}]"; rm -f "$W/polls"
guards "[{\"headSha\":\"$OTHER\",\"displayTitle\":\"Guards PR #21 @ $SHA\",\"status\":\"in_progress\",\"conclusion\":null,\"createdAt\":\"2026-10-09T10:00:00Z\"}]"
cat > "$W/gh-later" <<STUB
#!/usr/bin/env bash
case "\$*" in *guards.yml*) n=\$(cat "$W/polls" 2>/dev/null || echo 0); echo \$((n+1)) > "$W/polls"
  [ "\$n" -ge 1 ] && sed -i 's/"in_progress","conclusion":null/"completed","conclusion":"success"/' "$W/guards.json";; esac
exec "$W/gh" "\$@"
STUB
chmod +x "$W/gh-later"
out=$(GH_BIN="$W/gh-later" bash "$SCRIPT" 21 "$SHA" 60 0 2>/dev/null); rc=$?
if [ $rc = 0 ] && [ "$out" = "ci=success guards=success" ] && [ "$(cat "$W/polls")" = 2 ]; then pass=$((pass+1)); echo "PASS  polls again until both finish"
else failed=$((failed+1)); echo "FAIL  polls again: got '$out' (rc $rc, polls $(cat "$W/polls" 2>/dev/null))"; fi
echo "$pass passed, $failed failed"
[ "$failed" = 0 ]
