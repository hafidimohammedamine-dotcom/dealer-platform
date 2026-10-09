#!/usr/bin/env bash
# Tests scripts/check-workflows.sh (YAML-based) on the real workflows, broken copies and small fixture workflows.
set -uo pipefail
SCRIPT="$(cd "$(dirname "$0")" && pwd)/check-workflows.sh"
PY="$(cd "$(dirname "$0")" && pwd)/check-workflows.py"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMPROOT="${TMPDIR:-/tmp}"
W=.github/workflows
pass=0; failed=0
fresh() { T=$(mktemp -d "$TMPROOT/cw.XXXXXX") || exit 2; mkdir -p "$T/.github"; cp -r "$REPO/$W" "$T/.github/"; }
expect() { # expect <ok|fail> <name> <message> [extra args]
  local want=$1 name=$2 msg=$3; shift 3
  out=$(bash "$SCRIPT" "$T" "$@" 2>&1); rc=$?; got=$([ $rc = 0 ] && echo ok || echo fail)
  if [ "$got" = "$want" ] && grep -qF -- "$msg" <<<"$out"; then pass=$((pass+1)); echo "PASS  $name"
  else failed=$((failed+1)); echo "FAIL  $name ($got)"; echo "$out"; fi; rm -rf "$T"; }
drop() { python3 - "$T/$W/$1" "$2" <<'EOF'
import sys
p, item = sys.argv[1], sys.argv[2]
s = open(p).read()
for a, b in ((item + ",", ""), ("," + item + '"', '"')):
    if a in s:
        s = s.replace(a, b, 1); break
else:
    sys.exit("item not found: " + item)
open(p, "w").write(s)
EOF
}
# A small valid workflow; tests edit it with sed.
mk() { cat > "$T/$W/t.yml" <<'EOF'
name: t
on: workflow_dispatch
jobs:
  a:
    runs-on: ubuntu-latest
    env:
      CLAUDE_CODE_SUBPROCESS_ENV_SCRUB: "1"
    steps:
      - uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803
        with:
          ref: main
          persist-credentials: false
      - id: lock
        uses: ./.github/actions/agent-egress-lock
      - id: claude
        uses: anthropics/claude-code-action@2dca132ff0e0c4094ce6048b422c6915a071210b
        with:
          claude_code_oauth_token: ${{ secrets.CLAUDE_TOKEN_REVIEW }}
          path_to_claude_code_executable: ${{ steps.lock.outputs.claude-path }}
          path_to_bun_executable: ${{ steps.lock.outputs.bun-path }}
          prompt: "Do the task."
          claude_args: |
            --model haiku
            --disallowedTools "Skill(payload),Write"
      - name: After
        if: always() && steps.claude.outputs.execution_file != ''
        run: echo "steps.claude.outputs are fine, and so are refs/remotes/pr/head:.claude and @claude"
EOF
}
t() { fresh; mk; }   # fresh copy of the real workflows plus the small fixture

fresh;                                                  expect ok   "current workflows pass" "Workflow denies OK"
t;                                                      expect ok   "fixture workflow passes (harmless mentions of claude)" "Workflow denies OK"
# Skill(payload) is required in every claude step
for wf in agent-daily-report.yml agent-weekly-audit.yml review.yml claude.yml agent-manager.yml; do
  fresh; drop "$wf" 'Skill(payload)';                   expect fail "$wf without Skill(payload)" "--disallowedTools does not deny Skill(payload)"
done
# Every manager deny is required
mapfile -t MD < <(python3 -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1]))["manager_denies"]))' "$(dirname "$PY")/check-workflows-policy.json")
[ "${#MD[@]}" = 29 ] || { echo "FAIL  expected 29 manager denies, got ${#MD[@]}"; failed=$((failed+1)); }
for d in "${MD[@]}"; do
  [ "$d" = 'Skill(payload)' ] && continue
  fresh; drop agent-manager.yml "$d";                   expect fail "manager missing $d" "missing deny $d"
done
# Only claude_args counts: a decoy deny in the prompt and a "- " list line do not help
t; python3 - "$T/$W/t.yml" <<'EOF'
import sys; p=sys.argv[1]; s=open(p).read()
s=s.replace('prompt: "Do the task."', 'prompt: |\n            --disallowedTools "Skill(payload)"\n            - x')
s=s.replace('            --disallowedTools "Skill(payload),Write"\n', '            --permission-mode bypassPermissions\n')
open(p,"w").write(s)
EOF
                                                        expect fail "decoy deny in prompt, list line, no deny in claude_args" "needs exactly one --disallowedTools (found 0)"
for flag in '--settings /tmp/s.json' '--mcp-config /tmp/m.json' '--permission-prompt-tool mcp__x' '--dangerously-skip-permissions x' '--allowed-tools Skill' '--disallowed-tools Read' '--allowedTools=Skill' '--disallowedTools=Read'; do
  t; sed -i "s|            --model haiku|            --model haiku\n            $flag|" "$T/$W/t.yml"; expect fail "claude_args flag ${flag%% *}" "not allowed"
done
for key in allowed_tools disallowed_tools settings plugins plugin_marketplaces; do
  t; sed -i "s|          prompt: \"Do the task.\"|          prompt: \"Do the task.\"\n          $key: x|" "$T/$W/t.yml"; expect fail "claude input $key" "input '$key' not allowed"
done
t; sed -i 's|            --model haiku|            --model haiku\n            --disallowedTools "Read"|' "$T/$W/t.yml"; expect fail "two --disallowedTools" "needs exactly one --disallowedTools (found 2)"
t; sed -i 's|Skill(payload),Write|Skill(payload)x,Write|' "$T/$W/t.yml"; expect fail "near-miss Skill(payload)x" "does not deny Skill(payload)"
t; sed -i 's|            --model haiku|            --model|' "$T/$W/t.yml"; sed -i 's|            --disallowedTools|            --disallowedTools|' "$T/$W/t.yml"; expect fail "flag without a value" "needs a value"
t; sed -i "s|prompt: \"Do the task.\"|prompt: \"unbalanced 'quote\"|; s|--model haiku|--model 'haiku|" "$T/$W/t.yml"; expect fail "claude_args that cannot be parsed" "cannot be parsed"
# Every third-party skill in the manifests must be denied too
t; printf 'payload-cms third-party requires=x\n' > "$T/m.txt"; expect fail "second third-party skill name must be denied" "does not deny Skill(payload-cms)" --manifest "$T/m.txt"
t; printf '# old third-party\npayload-cms third-party requires=x\n' > "$T/m.txt"; for f in "$T/$W"/*.yml; do sed -i 's|--disallowedTools "Skill(payload),|--disallowedTools "Skill(payload),Skill(payload-cms),|' "$f"; done
                                                        expect ok   "second third-party skill denied everywhere" "Skill denies: payload, payload-cms" --manifest "$T/m.txt"
t; mkdir -p "$T/.claude/skills"; printf 'other third-party requires=x\n' > "$T/.claude/skills/manifest.txt"; expect fail "the root's own manifest is read too" "does not deny Skill(other)"
t; sed -i 's|          prompt: "Do the task."|          prompt: "Do the task."\n          allowed_bots: github-actions|' "$T/$W/t.yml"; expect fail "allowed_bots outside the manager" "allowed_bots may only be"
fresh; sed -i 's|allowed_bots: github-actions|allowed_bots: "*"|' "$T/$W/agent-manager.yml"; expect fail "manager allowing every bot" "allowed_bots may only be"
# Structure: duplicate keys, the lock step and the pinned action
t; sed -i 's|          prompt: "Do the task."|          prompt: "Do the task."\n          claude_args: "--model haiku"|' "$T/$W/t.yml"; expect fail "duplicate claude_args key" "duplicate key"
t; sed -i '/- id: lock/,+1d' "$T/$W/t.yml";              expect fail "claude job without the lock" "must start with actions/checkout, then ./.github/actions/agent-egress-lock"
t; sed -i 's|      - uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803|      - run: echo first\n      - uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803|' "$T/$W/t.yml"; expect fail "a step before checkout" "must start with actions/checkout"
t; sed -i 's|        uses: ./.github/actions/agent-egress-lock|        uses: ./.github/actions/agent-egress-lock\n        continue-on-error: true|' "$T/$W/t.yml"; expect fail "lock that may fail silently" "may only have id/uses/name (found continue-on-error)"
t; sed -i 's|      - id: lock|      -|' "$T/$W/t.yml";        expect fail "lock without an id" "needs an id"
t; sed -i '/path_to_claude_code_executable/d' "$T/$W/t.yml"; expect fail "claude step not using the pre-installed Claude" "path_to_claude_code_executable must be"
t; sed -i 's|steps.lock.outputs.claude-path|steps.other.outputs.claude-path|' "$T/$W/t.yml"; expect fail "path from another step" "path_to_claude_code_executable must be"
t; sed -i '/path_to_bun_executable/d' "$T/$W/t.yml"; expect fail "claude step letting the action download Bun" "path_to_bun_executable must be"
t; sed -i 's|steps.lock.outputs.bun-path|steps.other.outputs.bun-path|' "$T/$W/t.yml"; expect fail "Bun path from another step" "path_to_bun_executable must be"
t; sed -i 's|claude-code-action@2dca132ff0e0c4094ce6048b422c6915a071210b|claude-code-action@v1|' "$T/$W/t.yml"; expect fail "unpinned claude action" "claude action must be one of"
t; sed -i 's|anthropics/claude-code-action@|anthropics/claude-code-base-action@|' "$T/$W/t.yml"; expect fail "other claude-code action" "claude action must be one of"
t; sed -i 's|      - id: claude|      - id: claude\n        shell: bash|' "$T/$W/t.yml"; expect fail "unexpected key on a claude step" "key 'shell' not allowed"
# Claude runs nowhere else
for cmd in 'claude -p hi' 'npx @anthropic-ai/claude-code -p hi' '~/.local/bin/claude -p hi' 'echo x | claude --print' 'X=$(claude -p hi)'; do
  t; printf '      - run: %s\n' "$cmd" >> "$T/$W/t.yml";  expect fail "Claude CLI in a run step: $cmd" "runs Claude outside the pinned claude-code-action"
done
t; printf '      - uses: someone/claude-code-runner@v1\n' >> "$T/$W/t.yml"; expect fail "another claude-code action" "claude action must be one of"
# Claude credentials go nowhere else
for v in '${{ secrets.CLAUDE_TOKEN_BUILD }}' "\${{ secrets['CLAUDE_TOKEN_BUILD'] }}" '${{ toJSON(secrets) }}' '${{ secrets.anthropic_key }}'; do
  t; printf '      - run: echo hi\n        env:\n          X: %s\n' "$v" >> "$T/$W/t.yml"; expect fail "credential in another step: $v" "outside a claude step's claude_code_oauth_token"
done
t; printf '      - uses: actions/github-script@v7\n        with:\n          script: x\n          github-token: ${{ secrets.CLAUDE_TOKEN_BUILD }}\n' >> "$T/$W/t.yml"; expect fail "credential passed to another action" "secrets.CLAUDE_TOKEN_BUILD outside"
t; sed -i 's|^jobs:|env:\n  CLAUDE_CODE_OAUTH_TOKEN: x\njobs:|' "$T/$W/t.yml"; expect fail "workflow-level credential env" "t.yml env: Claude/Anthropic credential"
t; printf '  b:\n    runs-on: ubuntu-latest\n    env:\n      K: ${{ secrets.CLAUDE_TOKEN_BUILD }}\n    steps:\n      - run: echo hi\n' >> "$T/$W/t.yml"; expect fail "credential in a later job's env" "t.yml job b env: Claude/Anthropic credential"
t; sed -i 's|      - id: claude|      - id: claude\n        env:\n          ANTHROPIC_API_KEY: x|' "$T/$W/t.yml"; expect fail "any env on the claude step" "env not allowed on a claude step"
t; sed -i 's|prompt: "Do the task."|prompt: "${{ toJSON(secrets) }}"|' "$T/$W/t.yml"; expect fail "credential in the prompt" "in input 'prompt'"
# Actions and jobs
t; printf '      - uses: "./.github/actions/evil"\n' >> "$T/$W/t.yml"; expect fail "quoted local action not on the allow-list" "local action not on the allow-list: ./.github/actions/evil"
t; printf '      - uses: ./.github/actions/install-gitleaks\n' >> "$T/$W/t.yml"; expect fail "local action after the claude step" "no local action after the claude step"
t; printf '      - uses: docker://alpine:3\n' >> "$T/$W/t.yml"; expect fail "docker:// action" "not allowed: docker://alpine:3"
t; printf '  r:\n    uses: org/repo/.github/workflows/w.yml@v1\n' >> "$T/$W/t.yml"; expect fail "reusable workflow job" "reusable workflow not allowed"
t; sed -i 's|    runs-on: ubuntu-latest|    runs-on: ubuntu-latest\n    container: node:20|' "$T/$W/t.yml"; expect fail "container job" "'container' not allowed"
# Files and the manager
fresh; printf 'name: y\non: push\njobs: [\n' > "$T/$W/bad.yml"; expect fail "invalid YAML" "bad.yml: not valid YAML"
fresh; printf 'name: y\non: push\n' > "$T/$W/nojobs.yml"; expect fail "workflow without jobs" "no jobs mapping"
fresh; cp "$T/$W/claude.yml" "$T/$W/other.yaml"; drop other.yaml 'Skill(payload)'; expect fail ".yaml files are checked too" "other.yaml"
fresh; python3 - "$T/$W/agent-manager.yml" <<'EOF'
import sys,yaml; p=sys.argv[1]; s=open(p).read(); d=yaml.safe_load(s)
steps=d["jobs"]["shift"]["steps"]; i=next(k for k,x in enumerate(steps) if "claude-code" in str(x.get("uses","")))
lines=s.split("\n"); start=next(k for k,l in enumerate(lines) if l.strip()=="- id: claude")
end=next(k for k in range(start+1,len(lines)) if lines[k].startswith("      - "))
lines[end:end]=lines[start:end]; open(p,"w").write("\n".join(lines))
EOF
                                                        expect fail "two claude steps in the manager" "expected exactly one claude step in agent-manager.yml (found 2)"
fresh; sed -i 's|anthropics/claude-code-action@[0-9a-f]*|actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803|' "$T/$W/agent-manager.yml"; expect fail "no claude step in the manager" "(found 0)"
fresh; rm -f "$T/$W"/*;                                 expect fail "empty workflows folder" "no workflow files in"
fresh; rm -rf "$T/$W";                                  expect fail "missing workflows folder" "no workflows folder"
fresh;                                                  expect fail "unknown argument" "bad argument" --bogus
# secrets only as secrets.<NAME>
for v in "\${{ secrets[format('{0}_TOKEN_BUILD','CLAUDE')] }}" '${{ secrets[env.X] }}' '${{ secrets }}' '${{ join(secrets) }}'; do
  t; printf '      - run: echo hi\n        env:\n          X: %s\n' "$v" >> "$T/$W/t.yml"; expect fail "dynamic secrets use: $v" "secrets used other than as secrets.<NAME>"
done
t; printf '      - run: echo hi\n        env:\n          X: ${{ secrets.OTHER_TOKEN }}\n' >> "$T/$W/t.yml"; expect ok "a non-Claude secret by name is fine" "Workflow denies OK"
t; sed -i 's|^jobs:|permissions: "${{ secrets.CLAUDE_TOKEN_BUILD }}"\njobs:|' "$T/$W/t.yml"; expect fail "credential in workflow-level permissions" "t.yml permissions: Claude/Anthropic credential"
# The pre-installed binary may only run through the action
for cmd in '${{ steps.lock.outputs.claude-path }} -p hi' '$HOME/.local/bin/claude -p hi'; do
  t; printf '      - run: %s\n' "$cmd" >> "$T/$W/t.yml"; expect fail "pre-installed Claude in a run step: $cmd" "runs Claude outside the pinned claude-code-action"
done
t; printf '      - run: echo hi\n        env:\n          B: ${{ steps.lock.outputs.claude-path }}\n' >> "$T/$W/t.yml"; expect ok "binary path in env alone does not run it" "Workflow denies OK"
t; printf '      - uses: anthropics/other-action@v1\n' >> "$T/$W/t.yml"; expect fail "another anthropic action" "runs Claude outside the pinned claude-code-action (anthropics/other-action@v1)"
t; printf '      - uses: org/repo/.github/workflows/w.yml@v1\n' >> "$T/$W/t.yml"; expect fail "reusable workflow as a step" "not allowed: org/repo/.github/workflows/w.yml@v1"
# The checkout before the lock
t; sed -i '/          ref: main/d' "$T/$W/t.yml";             expect fail "checkout without an explicit ref" "needs an explicit ref of the default branch"
t; sed -i 's|          ref: main|          ref: ${{ github.event.pull_request.head.sha }}|' "$T/$W/t.yml"; expect fail "checkout of the PR head" "needs an explicit ref"
t; sed -i 's|          ref: main|          ref: ${{ github.base_ref }}|' "$T/$W/t.yml"; expect fail "base_ref outside pull_request_target" "needs an explicit ref"
t; sed -i 's|          ref: main|          ref: ${{ github.base_ref }}|; s|^on: workflow_dispatch|on: pull_request_target|' "$T/$W/t.yml"; expect ok "base_ref in a pull_request_target workflow" "Workflow denies OK"
t; sed -i 's|          ref: main|          ref: ${{ github.event.repository.default_branch }}|' "$T/$W/t.yml"; expect ok "default-branch expression" "Workflow denies OK"
t; sed -i '/          persist-credentials: false/d' "$T/$W/t.yml"; expect fail "checkout keeping credentials" "needs persist-credentials: false"
t; sed -i 's|        uses: ./.github/actions/agent-egress-lock|        uses: ./.github/actions/agent-egress-lock\n        with:\n          extra-domains: blob.core.windows.net|' "$T/$W/t.yml"; expect fail "lock step with inputs" "may only have id/uses/name (found with)"
t; sed -i 's|        uses: ./.github/actions/agent-egress-lock|        uses: ./.github/actions/agent-egress-lock\n        env:\n          AGENT_LOCK_SELFTEST_BREAK: "0"|' "$T/$W/t.yml"; expect fail "lock step with env" "(found env)"
t; sed -i 's|        uses: ./.github/actions/agent-egress-lock|        uses: ./.github/actions/agent-egress-lock\n        if: false|' "$T/$W/t.yml"; expect fail "lock step with if" "(found if)"
t; sed -i 's|      CLAUDE_CODE_SUBPROCESS_ENV_SCRUB: "1"|      CLAUDE_CODE_SUBPROCESS_ENV_SCRUB: "1"\n      AGENT_LOCK_TEST_DOCKER_SOCK: /x|' "$T/$W/t.yml"; expect fail "lock test hook in a claude job" "env 'AGENT_LOCK_TEST_DOCKER_SOCK' not allowed"
t; sed -i 's|^jobs:|env:\n  AGENT_LOCK_SELFTEST_BREAK: "1"\njobs:|' "$T/$W/t.yml"; expect fail "workflow-level env in a claude workflow" "no workflow-level env in a workflow with a claude step"
# Job env: allow-list, and the subprocess scrub must be on
t; sed -i '/      CLAUDE_CODE_SUBPROCESS_ENV_SCRUB: "1"/d; /    env:$/d' "$T/$W/t.yml"; expect fail "subprocess scrub missing" 'needs env CLAUDE_CODE_SUBPROCESS_ENV_SCRUB: "1"'
t; sed -i 's|      CLAUDE_CODE_SUBPROCESS_ENV_SCRUB: "1"|      CLAUDE_CODE_SUBPROCESS_ENV_SCRUB: "0"|' "$T/$W/t.yml"; expect fail "subprocess scrub turned off" 'needs env CLAUDE_CODE_SUBPROCESS_ENV_SCRUB: "1"'
for v in NODE_OPTIONS BASH_ENV ANTHROPIC_BASE_URL LD_PRELOAD; do
  t; sed -i "s|      CLAUDE_CODE_SUBPROCESS_ENV_SCRUB: \"1\"|      CLAUDE_CODE_SUBPROCESS_ENV_SCRUB: \"1\"\n      $v: x|" "$T/$W/t.yml"; expect fail "job env $v" "env '$v' not allowed in a job with a claude step"
done
# claude_args values are limited per workflow
t; sed -i 's|            --model haiku|            --model haiku\n            --permission-mode bypassPermissions|' "$T/$W/t.yml"; expect fail "bypassPermissions outside the manager" "--permission-mode bypassPermissions not allowed"
t; sed -i 's|            --model haiku|            --model haiku\n            --permission-mode acceptEdits|' "$T/$W/t.yml"; expect fail "another permission mode" "--permission-mode acceptEdits not allowed"
t; sed -i 's|            --model haiku|            --model haiku\n            --add-dir /tmp/pr|' "$T/$W/t.yml"; expect fail "--add-dir outside review.yml" "--add-dir /tmp/pr not allowed"
fresh; sed -i 's|--add-dir /tmp/pr|--add-dir /etc|' "$T/$W/review.yml"; expect fail "--add-dir elsewhere in review.yml" "--add-dir /etc not allowed"
for tool in 'Bash' 'Bash(*)' 'Write' 'Edit' 'WebFetch' 'Bash(find /tmp/pr:*)' 'Bash(git -C /tmp/pr grep:*)' 'Bash(yarn install:*)'; do
  t; sed -i "s|            --model haiku|            --model haiku\n            --allowedTools \"Read,$tool\"|" "$T/$W/t.yml"; expect fail "allowedTools $tool outside the manager" "--allowedTools item '$tool' not allowed"
done
t; sed -i 's|            --model haiku|            --model haiku\n            --allowedTools "Read,Grep,Bash(gh pr view:*),Bash(gh issue view:*)"|' "$T/$W/t.yml"; expect ok "read-only allowedTools" "Workflow denies OK"
fresh; python3 - "$T/$W/agent-manager.yml" <<'PYEOF'
import sys; p=sys.argv[1]; s=open(p).read()
s=s.replace("--permission-mode bypassPermissions", "--permission-mode bypassPermissions\n            --allowedTools \"Bash(*),Write\"", 1)
open(p,"w").write(s)
PYEOF
                                                        expect ok "the manager may allow write tools" "Workflow denies OK"
# No PR code in a claude job after the lock
t; printf '      - uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803\n        with:\n          ref: ${{ github.event.pull_request.head.sha }}\n' >> "$T/$W/t.yml"; expect fail "later checkout of the PR head" "the checkout needs an explicit ref of the default branch"
t; printf '      - uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803\n        with:\n          ref: main\n          persist-credentials: false\n' >> "$T/$W/t.yml"; expect ok "later checkout of main" "Workflow denies OK"
t; printf '      - uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803\n        with:\n          ref: main\n          path: other\n          persist-credentials: false\n' >> "$T/$W/t.yml"; expect fail "later checkout with a path" "checkout input(s) path not allowed"
for cmd in 'cd /tmp/pr && yarn install' 'yarn --cwd /tmp/pr install' 'bash /tmp/pr/scripts/x.sh' 'git -C /tmp/pr checkout main && make' 'git fetch origin ${{ github.event.pull_request.head.sha }}' 'echo ${{ github.head_ref }}'; do
  t; printf '      - run: %s\n' "$cmd" >> "$T/$W/t.yml"; expect fail "PR code in a run step: $cmd" "runs or checks out PR code in a job with a claude step"
done
t; printf '      - if: startsWith(github.event.pull_request.head.ref, %s)\n        run: echo ok\n' "'agent/'" >> "$T/$W/t.yml"; expect ok "reading the PR branch name in an if is fine" "Workflow denies OK"
# Round 4: checkouts, pins, PR data, post steps, job settings, manager token guard, composite actions
before() { python3 - "$T/$W/t.yml" "$1" <<'PYEOF'
import sys; p, add = sys.argv[1], sys.argv[2]; s = open(p).read()
s = s.replace("      - id: claude\n", add.replace("\\n", "\n") + "\n      - id: claude\n", 1); open(p, "w").write(s)
PYEOF
}
t; before '      - uses: ./.github/actions/install-gitleaks'; expect ok "allow-listed local action before the claude step" "Workflow denies OK"
t; sed -i 's|          persist-credentials: false|          persist-credentials: false\n          repository: evil/fork|' "$T/$W/t.yml"; expect fail "first checkout from another repository" "checkout input(s) repository not allowed"
t; sed -i 's|          persist-credentials: false|          persist-credentials: false\n          token: x|' "$T/$W/t.yml"; expect fail "first checkout with a token" "checkout input(s) token not allowed"
t; sed -i 's|      - uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803|      - uses: actions/checkout@v6|' "$T/$W/t.yml"; expect fail "unpinned first checkout" "step 1: action must be pinned to a full commit SHA: actions/checkout@v6"
t; before '      - uses: actions/setup-node@v4'; expect fail "unpinned action in a claude job" "action must be pinned to a full commit SHA: actions/setup-node@v4"
t; before '      - run: echo hi\n        working-directory: /tmp'; expect fail "working-directory in a claude job" "'working-directory' not allowed"
t; before '      - run: echo hi\n        shell: python'; expect fail "custom shell in a claude job" "'shell' not allowed"
t; sed -i 's|    runs-on: ubuntu-latest|    runs-on: ubuntu-latest\n    defaults:\n      run:\n        working-directory: /tmp/pr|' "$T/$W/t.yml"; expect fail "job defaults in a claude job" "'defaults' not allowed"
t; sed -i 's|    runs-on: ubuntu-latest|    runs-on: self-hosted|' "$T/$W/t.yml"; expect fail "self-hosted runner" "runs-on must be ubuntu-latest"
t; sed -i 's|    runs-on: ubuntu-latest|    runs-on: ubuntu-latest\n    permissions: write-all|' "$T/$W/t.yml"; expect fail "write-all permissions" "permissions must be a mapping"
t; sed -i 's|    runs-on: ubuntu-latest|    runs-on: ubuntu-latest\n    permissions:\n      packages: write|' "$T/$W/t.yml"; expect fail "unknown permission scope" "permission packages: write not allowed"
for cmd in 'cd "/tmp/pr" \&\& make' 'pushd /tmp/pr' 'make -C /tmp/pr' 'yarn --cwd=/tmp/pr install' 'bash -c "$(cat /tmp/pr/x)"' 'source /tmp/pr/env.sh' 'gh pr checkout ${{ github.event.pull_request.head.ref }}'; do
  t; before "      - run: $cmd"; expect fail "PR data in a run step: $cmd" "only the reviewed prepare step may touch /tmp/pr"
done
t; before '      - run: bash scripts/check-review-prepare.sh "$PR_NUMBER" /tmp/pr "origin/$BASE_REF"'; expect ok "the reviewed prepare step may use /tmp/pr" "Workflow denies OK"
t; before '      - run: echo /tmp/pr-meta/log.txt'; expect ok "/tmp/pr-meta is not PR code" "Workflow denies OK"
t; printf '      - run: bash scripts/check-review-post.sh pr 1 x\n' >> "$T/$W/t.yml"; expect fail "post step without the pin check" "must check its pinned files"
t; printf '      - env:\n          PINS: x\n        run: |\n          printf "%%s\\n" "$PINS" | sha256sum --check --strict --quiet\n          bash scripts/check-review-post.sh pr 1 x\n' >> "$T/$W/t.yml"; expect ok "post step that checks its pins first" "Workflow denies OK"
t; printf '      - run: /tmp/gitleaks detect\n' >> "$T/$W/t.yml"; expect fail "gitleaks after the claude step without the pin check" "must check its pinned files"
t; sed -i 's|      - id: claude|      - id: claude\n        if: always()|' "$T/$W/t.yml"; expect fail "claude step running after a failure" "may not run after a failure"
t; sed -i 's|      - id: claude|      - id: claude\n        continue-on-error: true|' "$T/$W/t.yml"; expect fail "claude step with continue-on-error" "key 'continue-on-error' not allowed"
fresh; sed -i '/check-agent-token.sh/d' "$T/$W/agent-manager.yml"; sed -i '/Agents must run on their own GitHub token/d' "$T/$W/agent-manager.yml"; expect fail "manager without the founder-token guard" "needs a step running 'bash scripts/check-agent-token.sh ...' before the claude step"
fresh; mkdir -p "$T/.github/actions/x"; printf 'name: x\nruns:\n  using: composite\n  steps:\n    - uses: actions/setup-node@v4\n' > "$T/.github/actions/x/action.yml"; expect fail "unpinned action inside a composite action" ".github/actions/x/action.yml step 1: action must be pinned"
fresh; mkdir -p "$T/.github/actions/x"; printf 'name: x\nruns:\n  using: composite\n  steps:\n    - run: echo ${{ secrets.CLAUDE_TOKEN_BUILD }}\n      shell: bash\n' > "$T/.github/actions/x/action.yml"; expect fail "Claude credential inside a composite action" ".github/actions/x/action.yml step 1: Claude/Anthropic credential"
fresh; mkdir -p "$T/.github/actions/x"; printf 'name: x\nruns:\n  using: node20\n  main: index.js\n' > "$T/.github/actions/x/action.yml"; expect fail "non-composite local action" "not a composite action with steps"
fresh; cp -r "$REPO/.github/actions" "$T/.github/"; expect ok "the real composite actions pass" "Workflow denies OK"
# Claude never runs in a pull_request workflow
t; sed -i 's|^on: workflow_dispatch|on:\n  pull_request:\n  workflow_dispatch:|' "$T/$W/t.yml"; expect fail "claude step in a pull_request workflow" "must not run on pull_request"
t; sed -i 's|^on: workflow_dispatch|on: [push, pull_request]|' "$T/$W/t.yml"; expect fail "pull_request in a trigger list" "must not run on pull_request"
# Malformed workflows
t; sed -i 's|^          claude_code_oauth_token: .*|XX|' "$T/$W/t.yml"; sed -i '/^XX$/,/^      - name: After/{/^      - name: After/!d}' "$T/$W/t.yml"; sed -i 's|^        with:$|        with: just-a-string|' "$T/$W/t.yml"; sed -i '0,/        with: just-a-string/s||        with:|' "$T/$W/t.yml"
                                                        expect fail "claude 'with' not a mapping" "'with' must be a mapping"
fresh; printf 'name: y\non: push\njobs:\n  a:\n    runs-on: ubuntu-latest\n    steps: "x"\n' > "$T/$W/s.yml"; expect fail "steps not a list" "steps must be a list"
fresh; printf 'name: y\non: push\njobs:\n  a: "x"\n' > "$T/$W/s.yml"; expect fail "job not a mapping" "s.yml job a: not a mapping"
fresh; printf 'name: y\non: push\njobs:\n  a:\n    runs-on: ubuntu-latest\n    steps:\n      - "echo"\n' > "$T/$W/s.yml"; expect fail "step not a mapping" "s.yml job a step 1: not a mapping"
fresh; printf 'name: y\non: push\njobs:\n  a:\n    runs-on: ubuntu-latest\n    services:\n      db: {image: postgres}\n    steps:\n      - run: echo\n' > "$T/$W/s.yml"; expect fail "services job" "'services' not allowed"
fresh; printf -- '- a\n- b\n' > "$T/$W/s.yml";              expect fail "top level not a mapping" "s.yml: no jobs mapping"
# Arguments
fresh;                                                  expect fail "--manifest without a value" "--manifest needs a file" --manifest
fresh;                                                  expect fail "explicit --manifest that does not exist" "manifest not found" --manifest /nonexistent/manifest.txt
fresh;                                                  expect fail "two root arguments" "bad argument" "$REPO"
fresh; out=$(python3 -I -S "$PY" "$T" 2>&1); rc=$?
if [ $rc != 0 ] && grep -q "PyYAML is required" <<<"$out"; then pass=$((pass+1)); echo "PASS  fails closed without PyYAML"; else failed=$((failed+1)); echo "FAIL  without PyYAML"; echo "$out"; fi; rm -rf "$T"
# Round 5: more PR-data forms, git moves, workflow_run, id-token, tag mode, pin check order
for cmd in 'git fetch origin pull/7/head:pr' 'git fetch origin refs/pull/7/merge' 'gh pr checkout 7' 'echo ${{ github.event.pull_request.merge_commit_sha }}' 'echo ${{ github.event.issue.number }}'; do
  t; before "      - run: $cmd"; expect fail "PR data in a run step: $cmd" "only the reviewed prepare step may touch /tmp/pr"
done
for cmd in 'git checkout feature' 'git -C . switch x' 'git fetch origin' 'git worktree add /tmp/w' 'git reset --hard origin/x' 'git pull'; do
  t; before "      - run: $cmd"; expect fail "git move in a claude job: $cmd" "not allowed in a job with a claude step (the checkout must stay on the default branch)"
done
t; before '      - run: git log --oneline -5'; expect ok "git log is not a checkout move" "Workflow denies OK"
t; sed -i 's/^on: workflow_dispatch$/on:\n  workflow_run:\n    workflows: [CI]\n    types: [completed]/' "$T/$W/t.yml"; expect fail "claude step in a workflow_run workflow" "must not run on workflow_run"
fresh; sed -i 's/^      issues: write$/      issues: write\n      id-token: write/' "$T/$W/agent-manager.yml"; expect fail "id-token in agent-manager.yml" "permission id-token: write not allowed"
fresh; grep -q 'id-token: write' "$T/$W/claude.yml" && expect ok "id-token stays allowed in claude.yml" "Workflow denies OK"
fresh; sed -i 's/^  issue_comment:$/  pull_request_review_comment:\n    types: [created]\n  issue_comment:/' "$T/$W/claude.yml"; expect fail "tag mode on PR review comments" "a claude step without a prompt (tag mode) may run only on issue_comment, issues (found pull_request_review_comment)"
fresh; sed -i 's/ \&\& !github.event.issue.pull_request//' "$T/$W/claude.yml"; expect fail "tag mode answering on PRs" "needs the job if to contain '!github.event.issue.pull_request'"
t; printf '      - run: |\n          /tmp/gitleaks detect\n          printf x | sha256sum --check --strict\n' >> "$T/$W/t.yml"; expect fail "pin check after /tmp/gitleaks does not count" "must check its pinned files"
# Missing or broken policy file: fails closed
P0=$(mktemp -d "$TMPROOT/cwp.XXXXXX"); P2="$P0/scripts"; mkdir "$P2"; cp "$(dirname "$PY")"/check-workflows*.py "$P2/"
out=$(python3 -I "$P2/check-workflows.py" "$REPO" 2>&1); rc=$?
if [ $rc != 0 ] && grep -q "cannot read check-workflows-policy.json" <<<"$out"; then pass=$((pass+1)); echo "PASS  missing policy file fails closed"; else failed=$((failed+1)); echo "FAIL  missing policy file"; echo "$out"; fi
echo '{not json' > "$P2/check-workflows-policy.json"; out=$(python3 -I "$P2/check-workflows.py" "$REPO" 2>&1); rc=$?
if [ $rc != 0 ] && grep -q "cannot read check-workflows-policy.json" <<<"$out"; then pass=$((pass+1)); echo "PASS  broken policy file fails closed"; else failed=$((failed+1)); echo "FAIL  broken policy file"; echo "$out"; fi
rm -rf "$P0"
echo "$pass passed, $failed failed"
[ "$failed" = 0 ]
