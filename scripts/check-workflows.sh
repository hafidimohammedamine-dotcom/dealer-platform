#!/usr/bin/env bash
# Checks the agent workflows keep their deny entries:
#  - every claude-code-action step that can use skills (allows Skill, or runs bypassPermissions) denies Skill(payload),
#    so the upstream Payload skill is only ever loaded together with its override (as an agent preload);
#  - the manager job keeps its command denies.
# Usage: scripts/check-workflows.sh [repo-root]
set -euo pipefail
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT/.github/workflows"
fail=0; err() { echo "ERROR: $*"; fail=1; }
for f in *.yml; do
  grep -q 'anthropics/claude-code-action' "$f" || continue
  if grep -qE 'bypassPermissions|--allowedTools "[^"]*\bSkill\b' "$f"; then
    grep -qE -- '--disallowedTools "[^"]*Skill\(payload\)' "$f" || err "$f: can use skills but does not deny Skill(payload)"
  fi
done
for deny in 'Bash(npx:*)' 'Bash(npm:*)' 'Bash(yarn dlx:*)' 'Bash(yarn create:*)' 'Bash(node -e:*)' 'Bash(node -p:*)' \
            'Bash(curl:*)' 'Bash(wget:*)' 'Bash(env:*)' 'Bash(printenv:*)' 'Bash(gh pr merge:*)' 'Bash(gh secret:*)' 'Read(//proc/**)'; do
  grep -qF -- "$deny" agent-manager.yml || err "agent-manager.yml: missing deny $deny"
done
[ "$fail" = 0 ] && echo "Workflow denies OK"
exit "$fail"
