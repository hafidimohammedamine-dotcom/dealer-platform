#!/usr/bin/env bash
# Tests scripts/check-workflows.sh on the real workflows and on broken copies.
set -uo pipefail
SCRIPT="$(cd "$(dirname "$0")" && pwd)/check-workflows.sh"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMPROOT="${TMPDIR:-/tmp}"
W=.github/workflows
pass=0; failed=0
fresh() { T=$(mktemp -d "$TMPROOT/cw.XXXXXX") || exit 2; mkdir -p "$T/.github"; cp -r "$REPO/$W" "$T/.github/"; }
expect() { out=$(bash "$SCRIPT" "$T" 2>&1); rc=$?; got=$([ $rc = 0 ] && echo ok || echo fail)
  if [ "$got" = "$1" ] && grep -qF -- "$3" <<<"$out"; then pass=$((pass+1)); echo "PASS  $2"; else failed=$((failed+1)); echo "FAIL  $2 ($got)"; echo "$out"; fi; rm -rf "$T"; }
drop() { sed -i "s/\([\", ]\)$2,/\1/; s/,$2\"/\"/" "$T/$W/$1"; }   # remove one deny item from a workflow (first or middle, or last)
ACTION='anthropics/claude-code-action@2dca132ff0e0c4094ce6048b422c6915a071210b'
step() { printf '      - uses: %s\n        with:\n          claude_args: |\n%s\n' "$ACTION" "$1"; }
DENY='            --disallowedTools "Skill(payload),WebFetch"'

fresh;                                                       expect ok   "current workflows pass" "Workflow denies OK"
# Skill(payload) deny removed from each claude workflow
for wf in agent-daily-report.yml agent-weekly-audit.yml review.yml claude.yml agent-manager.yml; do
  fresh; drop "$wf" 'Skill(payload)';                        expect fail "$wf without Skill(payload) deny" "$wf claude step 1: --disallowedTools does not deny Skill(payload)"
done
# Every manager deny is required (one test per item)
IFS=, read -r -a MD <<<"$(sed -n "s/^MANAGER_DENIES='\(.*\)'$/\1/p" "$SCRIPT")"
[ "${#MD[@]}" = 25 ] || { echo "FAIL  expected 25 manager denies, got ${#MD[@]}"; failed=$((failed+1)); }
for d in "${MD[@]}"; do
  [ "$d" = 'Skill(payload)' ] && continue
  esc=$(printf '%s' "$d" | sed 's/[][\/.*^$]/\\&/g')
  fresh; drop agent-manager.yml "$esc";                      expect fail "manager missing $d" "missing deny $d"
done
# The deny only counts as an exact item on the step's own --disallowedTools line
fresh; sed -i 's/--disallowedTools "Skill(payload),/--disallowedTools "Skill(payload)x,/' "$T/$W/claude.yml"
                                                             expect fail "near-miss item Skill(payload)x" "claude.yml claude step 1: --disallowedTools does not deny"
fresh; sed -i 's/Skill(payload),//' "$T/$W/claude.yml"; sed -i '1i # --disallowedTools "Skill(payload)"' "$T/$W/claude.yml"
                                                             expect fail "deny only in a comment" "claude.yml claude step 1: --disallowedTools does not deny"
fresh; { printf 'name: x\non: workflow_dispatch\njobs:\n  a:\n    runs-on: ubuntu-latest\n    steps:\n'; step "$DENY"; step '            --allowedTools "Read,Skill"'; } > "$T/$W/two.yml"
                                                             expect fail "two steps, second has no deny" "two.yml claude step 2: needs exactly one --disallowedTools line (found 0)"
fresh; { printf 'name: x\non: workflow_dispatch\njobs:\n  a:\n    runs-on: ubuntu-latest\n    steps:\n'; step '            --model opus'; } > "$T/$W/noskill.yml"
                                                             expect fail "step with no Skill grant and no deny line still fails" "noskill.yml claude step 1: needs exactly one --disallowedTools line (found 0)"
fresh; { printf 'name: x\non: workflow_dispatch\njobs:\n  a:\n    runs-on: ubuntu-latest\n    steps:\n'; step "$DENY"; } > "$T/$W/other.yaml"
sed -i 's/Skill(payload),//' "$T/$W/other.yaml";              expect fail ".yaml files are checked too" "other.yaml claude step 1"
fresh; { printf 'name: x\non: workflow_dispatch\njobs:\n  a:\n    runs-on: ubuntu-latest\n    steps:\n'; step "$DENY$(printf '\n%s' "$DENY")"; } > "$T/$W/dup.yml"
                                                             expect fail "two --disallowedTools lines in one step" "dup.yml claude step 1: needs exactly one --disallowedTools line (found 2)"
fresh; { printf 'name: x\non: workflow_dispatch\njobs:\n  a:\n    runs-on: ubuntu-latest\n    steps:\n'; step "$DENY"; printf '          allowed_tools: "Skill"\n'; } > "$T/$W/route.yml"
                                                             expect fail "tools granted by allowed_tools: input" "route.yml claude step 1: tools set outside"
fresh; { printf 'name: x\non: workflow_dispatch\njobs:\n  a:\n    runs-on: ubuntu-latest\n    steps:\n'; step "$DENY$(printf '\n%s' '            --allowed-tools "Skill"')"; } > "$T/$W/route2.yml"
                                                             expect fail "tools granted by --allowed-tools" "route2.yml claude step 1: tools set outside"
fresh; { printf 'name: x\non: workflow_dispatch\njobs:\n  a:\n    runs-on: ubuntu-latest\n    steps:\n'; step "$DENY$(printf '\n%s' '            --settings /tmp/s.json')"; } > "$T/$W/route3.yml"
                                                             expect fail "tools set by --settings" "route3.yml claude step 1: tools set outside"
fresh; { printf 'name: x\non: workflow_dispatch\njobs:\n  a:\n    runs-on: ubuntu-latest\n    steps:\n'; step '            --disallowedTools=Skill(payload)'; } > "$T/$W/eq.yml"
                                                             expect fail "unquoted --disallowedTools= form" "eq.yml claude step 1: tools set outside"
fresh; sed -i 's|anthropics/claude-code-action@|anthropics/claude-code-base-action@|' "$T/$W/claude.yml"; drop claude.yml 'Skill(payload)'
                                                             expect fail "other claude-code actions are checked too" "claude.yml claude step 1"
# Workflows without a claude step are skipped (ci.yml, guards.yml); the manager's claude step must exist
fresh; printf 'name: y\non: push\njobs:\n  a:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo hi\n' > "$T/$W/plain.yml"
                                                             expect ok   "workflow with no claude step is skipped" "Workflow denies OK"
fresh; sed -i 's|anthropics/claude-code-action@[0-9a-f]*|actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803|' "$T/$W/agent-manager.yml"
                                                             expect fail "manager claude step missing" "expected exactly one claude step in agent-manager.yml (found 0)"
fresh; rm -rf "$T/$W";                                       expect fail "missing workflows folder" "no workflows folder"
echo "$pass passed, $failed failed"
[ "$failed" = 0 ]
