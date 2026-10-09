#!/usr/bin/env bash
# Tests scripts/check-workflows.sh on the real workflows and on broken copies.
set -uo pipefail
SCRIPT="$(cd "$(dirname "$0")" && pwd)/check-workflows.sh"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMPROOT="${TMPDIR:-/tmp}"
pass=0; failed=0
fresh() { T=$(mktemp -d "$TMPROOT/cw.XXXXXX") || exit 2; mkdir -p "$T/.github"; cp -r "$REPO/.github/workflows" "$T/.github/"; }
expect() { out=$(bash "$SCRIPT" "$T" 2>&1); rc=$?; got=$([ $rc = 0 ] && echo ok || echo fail)
  if [ "$got" = "$1" ] && grep -qF -- "$3" <<<"$out"; then pass=$((pass+1)); echo "PASS  $2"; else failed=$((failed+1)); echo "FAIL  $2 ($got)"; echo "$out"; fi; rm -rf "$T"; }
fresh;                                                                         expect ok   "current workflows pass" "Workflow denies OK"
fresh; sed -i 's/Skill(payload),//' "$T/.github/workflows/agent-daily-report.yml"; expect fail "daily report without Skill(payload) deny" "agent-daily-report.yml: can use skills"
fresh; sed -i 's/Skill(payload),//' "$T/.github/workflows/agent-manager.yml"; expect fail "manager (bypass) without Skill(payload) deny" "agent-manager.yml: can use skills"
fresh; sed -i 's/Bash(yarn dlx:\*),//' "$T/.github/workflows/agent-manager.yml"; expect fail "manager missing a command deny" "missing deny Bash(yarn dlx:*)"
echo "$pass passed, $failed failed"
[ "$failed" = 0 ]
