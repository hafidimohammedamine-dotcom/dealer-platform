#!/usr/bin/env bash
# Tests scripts/check-scrub-probe.sh: it counts a token-looking value in its environment and never prints it.
set -uo pipefail
COVENV=(); [ -n "${COV_TRACE:-}" ] && COVENV=(COV_TRACE="$COV_TRACE" BASH_ENV="$BASH_ENV")   # scripts/check-coverage.sh
SCRIPT="$(cd "$(dirname "$0")" && pwd)/check-scrub-probe.sh"
pass=0; failed=0
out=$(env -i "${COVENV[@]}" PATH=/usr/bin:/bin bash "$SCRIPT"); grep -q 'SCRUB-PROBE env-tokens=0 ' <<<"$out" && { pass=$((pass+1)); echo "PASS  clean environment"; } || { failed=$((failed+1)); echo "FAIL  clean env: $out"; }
out=$(env -i "${COVENV[@]}" PATH=/usr/bin:/bin FAKE=sk-ant-test-123 bash "$SCRIPT"); grep -q 'SCRUB-PROBE env-tokens=1 proc-tokens=[1-9]' <<<"$out" && { pass=$((pass+1)); echo "PASS  token in its environment is counted (env and its own /proc)"; } || { failed=$((failed+1)); echo "FAIL  token env: $out"; }
! grep -q 'sk-ant-test' <<<"$out" && { pass=$((pass+1)); echo "PASS  never prints the token"; } || { failed=$((failed+1)); echo "FAIL  printed token"; }

# A token in ANOTHER process's environment is counted (the probe must look beyond itself)
env -i FAKE=sk-ant-other-process sleep 30 & other=$!
out=$(env -i "${COVENV[@]}" PATH=/usr/bin:/bin bash "$SCRIPT"); kill "$other" 2>/dev/null; wait "$other" 2>/dev/null
grep -q 'SCRUB-PROBE env-tokens=0 proc-tokens=[1-9]' <<<"$out" && { pass=$((pass+1)); echo "PASS  token in another process is counted"; } || { failed=$((failed+1)); echo "FAIL  other process: $out"; }
echo "$pass passed, $failed failed"
[ "$failed" = 0 ]
