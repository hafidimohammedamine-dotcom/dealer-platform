#!/usr/bin/env bash
# Tests scripts/check-workflows.sh (YAML-based) on the real workflows, broken copies and small fixture workflows.
# Identity and token rules are in scripts/check-workflows-people.test.sh.
set -uo pipefail
# shellcheck source=scripts/check-workflows-testlib.sh
. "$(cd "$(dirname "$0")" && pwd)/check-workflows-testlib.sh"

fresh;                                                  expect ok   "current workflows pass" "Workflow denies OK"
fx;                                                      expect ok   "fixture workflow passes (harmless mentions of claude)" "Workflow denies OK"
# Skill(payload) is required in every claude step
for wf in agent-daily-report.yml agent-weekly-audit.yml review.yml claude.yml agent-manager.yml; do
  fresh; drop "$wf" 'Skill(payload)';                   expect fail "$wf without Skill(payload)" "--disallowedTools does not deny Skill(payload)"
done
# Every manager deny is required
mapfile -t MD < <(python3 -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1]))["manager_denies"]))' "$(dirname "$PY")/check-workflows-policy.json")
[ "${#MD[@]}" = 27 ] || t FAIL "expected 27 manager denies, got ${#MD[@]} (Skill(payload) and claude_denies are required of every Claude step already)"
for d in "${MD[@]}"; do
  [ "$d" = 'Skill(payload)' ] && continue
  fresh; drop agent-manager.yml "$d";                   expect fail "manager missing $d" "missing deny $d"
done
# Only claude_args counts: a decoy deny in the prompt and a "- " list line do not help
fx; python3 - "$T/$W/t.yml" <<'EOF'
import sys; p=sys.argv[1]; s=open(p).read()
s=s.replace('prompt: "Do the task."', 'prompt: |\n            --disallowedTools "Skill(payload)"\n            - x')
s=s.replace('            --disallowedTools "Skill(payload),Write,WebFetch,WebSearch,Read(//proc/**),Read(//sys/**),Read(//home/runner/work/_temp/**),Read(//home/runner/.*/**),Read(//etc/**),Read(//dev/**),Read(//home/runner/runners/**),Read(./.git/**)"\n', '            --permission-mode bypassPermissions\n')
open(p,"w").write(s)
EOF
                                                        expect fail "decoy deny in prompt, list line, no deny in claude_args" "needs exactly one --disallowedTools (found 0)"
for flag in '--settings /tmp/s.json' '--mcp-config /tmp/m.json' '--permission-prompt-tool mcp__x' '--dangerously-skip-permissions x' '--allowed-tools Skill' '--disallowed-tools Read' '--allowedTools=Skill' '--disallowedTools=Read'; do
  fx; sed -i "s|            --model haiku|            --model haiku\n            $flag|" "$T/$W/t.yml"; expect fail "claude_args flag ${flag%% *}" "not allowed"
done
for key in allowed_tools disallowed_tools settings plugins plugin_marketplaces; do
  fx; sed -i "s|          prompt: \"Do the task.\"|          prompt: \"Do the task.\"\n          $key: x|" "$T/$W/t.yml"; expect fail "claude input $key" "input '$key' not allowed"
done
# The action's post-session step "Post buffered inline comments" runs with the GitHub token (and `bun` from PATH) after
# Claude ran, unless classify_inline_comments is "false": every claude step must say so.
fx; sed -i '/          classify_inline_comments: "false"/d' "$T/$W/t.yml"; expect fail "classify_inline_comments missing" "input 'classify_inline_comments' must be 'false' (the action's 'Post buffered inline comments' step would otherwise run after the session with the GitHub token)"
fx; sed -i 's|          classify_inline_comments: "false"|          classify_inline_comments: "true"|' "$T/$W/t.yml"; expect fail "classify_inline_comments true" "input 'classify_inline_comments' must be 'false'"
fx; sed -i 's|          classify_inline_comments: "false"|          classify_inline_comments: false|' "$T/$W/t.yml"; expect fail "classify_inline_comments unquoted (YAML boolean, not the string the action compares)" "input 'classify_inline_comments' must be 'false'"
fresh; sed -i '/          classify_inline_comments: "false"/d' "$T/$W/agent-manager.yml"; expect fail "the manager's claude step without classify_inline_comments: \"false\"" "input 'classify_inline_comments' must be 'false'"
fx; sed -i 's|            --model haiku|            --model haiku\n            --disallowedTools "Read"|' "$T/$W/t.yml"; expect fail "two --disallowedTools" "needs exactly one --disallowedTools (found 2)"
fx; sed -i 's|Skill(payload),Write|Skill(payload)x,Write|' "$T/$W/t.yml"; expect fail "near-miss Skill(payload)x" "does not deny Skill(payload)"
fx; sed -i 's|            --model haiku|            --model|' "$T/$W/t.yml"; sed -i 's|            --disallowedTools|            --disallowedTools|' "$T/$W/t.yml"; expect fail "flag without a value" "needs a value"
fx; sed -i "s|prompt: \"Do the task.\"|prompt: \"unbalanced 'quote\"|; s|--model haiku|--model 'haiku|" "$T/$W/t.yml"; expect fail "claude_args that cannot be parsed" "cannot be parsed"
# Every third-party skill in the manifests must be denied too
fx; printf 'payload-cms third-party requires=x\n' > "$T/m.txt"; expect fail "second third-party skill name must be denied" "does not deny Skill(payload-cms)" --manifest "$T/m.txt"
fx; printf '# old third-party\npayload-cms third-party requires=x\n' > "$T/m.txt"; for f in "$T/$W"/*.yml; do sed -i 's|--disallowedTools "Skill(payload),|--disallowedTools "Skill(payload),Skill(payload-cms),|' "$f"; done
                                                        expect ok   "second third-party skill denied everywhere" "Skill denies: payload, payload-cms" --manifest "$T/m.txt"
fx; mkdir -p "$T/.claude/skills"; printf 'other third-party requires=x\n' > "$T/.claude/skills/manifest.txt"; expect fail "the root's own manifest is read too" "does not deny Skill(other)"
fx; sed -i 's|          prompt: "Do the task."|          prompt: "Do the task."\n          allowed_bots: github-actions|' "$T/$W/t.yml"; expect fail "allowed_bots outside the manager" "allowed_bots may only be"
fresh; sed -i 's|allowed_bots: github-actions|allowed_bots: "*"|' "$T/$W/agent-manager.yml"; expect fail "manager allowing every bot" "allowed_bots may only be"
# Structure: duplicate keys, the lock step and the pinned action
fx; sed -i 's|          prompt: "Do the task."|          prompt: "Do the task."\n          claude_args: "--model haiku"|' "$T/$W/t.yml"; expect fail "duplicate claude_args key" "duplicate key"
fx; sed -i '/- id: lock/,+1d' "$T/$W/t.yml";              expect fail "claude job without the lock" "must start with actions/checkout, the pin step, 'bash scripts/check-main-head.sh' (name and run only), then ./.github/actions/agent-egress-lock"
fx; sed -i '/bash scripts\/check-main-head.sh/d' "$T/$W/t.yml"; expect fail "claude job without the main-head check" "must start with actions/checkout, the pin step, 'bash scripts/check-main-head.sh'"
fx; sed -i 's|        run: bash scripts/check-main-head.sh|        run: bash scripts/check-main-head.sh\n        env:\n          GH_BIN: /tmp/x|' "$T/$W/t.yml"; expect fail "main-head check with an env (name and run only)" "'bash scripts/check-main-head.sh' (name and run only)"
fx; sed -i '/- name: The repository files this job runs are the reviewed ones/,+6d' "$T/$W/t.yml"; expect fail "claude job without the pin step" "the step after the checkout must be the pin step"
fx; sed -i 's|PINS_SHA256: "[0-9a-f]*"|PINS_SHA256: "0000000000000000000000000000000000000000000000000000000000000000"|' "$T/$W/t.yml"; expect fail "pin step with a stale hash" "PINS_SHA256 is 0000000000000000000000000000000000000000000000000000000000000000 but .github/pins.txt is"
fx; sed -i 's|          sha256sum --check --strict --quiet .github/pins.txt|          true|' "$T/$W/t.yml"; expect fail "pin step with a changed run" "the pin step's run must be exactly the policy's pins_step_run"
fx; sed -i '/PINS_SHA256:/a\          EXTRA: x' "$T/$W/t.yml"; expect fail "pin step with an extra env" "the pin step may only have name, env (PINS_SHA256), run and id"
fx; printf 'x\n' >> "$T/scripts/check-pins.sh"; expect fail "a pinned file changed without a pin update" "check-pins.sh changed but its pin did not; run: bash scripts/check-pins.sh update"
fx; rm "$T/.github/pins.txt"; expect fail "pins.txt missing" ".github/pins.txt is missing; run: bash scripts/check-pins.sh update"
fx; echo "0000000000000000000000000000000000000000000000000000000000000000  scripts/check-zzz.sh" >> "$T/.github/pins.txt"; expect fail "pins.txt lists a file that is not pinned" "lists scripts/check-zzz.sh, which is not a pinned file"
fx; sed -i '/check-pins.sh/d' "$T/.github/pins.txt"; expect fail "pins.txt misses a pinned file" "does not list scripts/check-pins.sh"
fx; echo "bad line" >> "$T/.github/pins.txt"; expect fail "pins.txt with a bad line" "want '<sha256>  <path>'"
fx; printf 'name: y\non: push\njobs:\n  a:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo\n' > "$T/$W/s.yml"; expect fail "a job without a checkout" "no actions/checkout step (every job outside pins_exempt"
fx; printf 'name: y\non: push\njobs:\n  a:\n    runs-on: ubuntu-latest\n    steps:\n      - uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803\n      - run: echo\n' > "$T/$W/s.yml"; expect fail "a plain job without the pin step after checkout" "the step after the checkout must be the pin step"
fresh; plain s.yml; expect ok "a plain job with the pin step" "Workflow denies OK"
fresh; sed -i 's|^          sha256sum --check --strict --quiet .github/pins.txt$|          true|' "$T/$W/pusher-ledger.yml"; expect fail "the ledger's default-branch pin step changed" "the pin step's run must be exactly the policy's pins_step_run_default_branch"
fresh; sed -i '/^        # branch.s own guards.yml/a\        env:\n          X: y' "$T/$W/pusher-ledger.yml"; expect fail "the ledger's pin step with an env" "may only have name, run and id (the hash comes from the default branch"
fx; sed -i 's|      - uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803|      - run: echo first\n      - uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803|' "$T/$W/t.yml"; expect fail "a step before checkout" "must start with actions/checkout"
fx; sed -i 's|        uses: ./.github/actions/agent-egress-lock|        uses: ./.github/actions/agent-egress-lock\n        continue-on-error: true|' "$T/$W/t.yml"; expect fail "lock that may fail silently" "may only have id/uses/name (found continue-on-error)"
fx; sed -i 's|      - id: lock|      -|' "$T/$W/t.yml";        expect fail "lock without an id" "needs an id"
fx; sed -i '/path_to_claude_code_executable/d' "$T/$W/t.yml"; expect fail "claude step not using the pre-installed Claude" "path_to_claude_code_executable must be"
fx; sed -i 's|steps.lock.outputs.claude-path|steps.other.outputs.claude-path|' "$T/$W/t.yml"; expect fail "path from another step" "path_to_claude_code_executable must be"
fx; sed -i '/path_to_bun_executable/d' "$T/$W/t.yml"; expect fail "claude step letting the action download Bun" "path_to_bun_executable must be"
fx; sed -i 's|steps.lock.outputs.bun-path|steps.other.outputs.bun-path|' "$T/$W/t.yml"; expect fail "Bun path from another step" "path_to_bun_executable must be"
fx; sed -i 's|claude-code-action@2dca132ff0e0c4094ce6048b422c6915a071210b|claude-code-action@v1|' "$T/$W/t.yml"; expect fail "unpinned claude action" "claude action must be one of"
fx; sed -i 's|anthropics/claude-code-action@|anthropics/claude-code-base-action@|' "$T/$W/t.yml"; expect fail "other claude-code action" "claude action must be one of"
fx; sed -i 's|      - id: claude|      - id: claude\n        shell: bash|' "$T/$W/t.yml"; expect fail "unexpected key on a claude step" "key 'shell' not allowed"
# Claude runs nowhere else
for cmd in 'claude -p hi' 'npx @anthropic-ai/claude-code -p hi' '~/.local/bin/claude -p hi' 'echo x | claude --print' 'X=$(claude -p hi)'; do
  fx; printf '      - run: %s\n' "$cmd" >> "$T/$W/t.yml";  expect fail "Claude CLI in a run step: $cmd" "runs Claude outside the pinned claude-code-action"
done
fx; printf '      - uses: someone/claude-code-runner@v1\n' >> "$T/$W/t.yml"; expect fail "another claude-code action" "claude action must be one of"
# Claude credentials go nowhere else
for v in '${{ secrets.CLAUDE_TOKEN_BUILD_V2 }}' "\${{ secrets['CLAUDE_TOKEN_BUILD_V2'] }}" '${{ toJSON(secrets) }}' '${{ secrets.anthropic_key }}'; do
  fx; printf '      - run: echo hi\n        env:\n          X: %s\n' "$v" >> "$T/$W/t.yml"; expect fail "credential in another step: $v" "outside a claude step's claude_code_oauth_token"
done
fx; printf '      - uses: actions/github-script@v7\n        with:\n          script: x\n          github-token: ${{ secrets.CLAUDE_TOKEN_BUILD_V2 }}\n' >> "$T/$W/t.yml"; expect fail "credential passed to another action" "secrets.CLAUDE_TOKEN_BUILD_V2 outside"
fx; sed -i 's|^jobs:|env:\n  CLAUDE_CODE_OAUTH_TOKEN: x\njobs:|' "$T/$W/t.yml"; expect fail "workflow-level credential env" "t.yml env: Claude/Anthropic credential"
fx; printf '  b:\n    runs-on: ubuntu-latest\n    env:\n      K: ${{ secrets.CLAUDE_TOKEN_BUILD_V2 }}\n    steps:\n      - run: echo hi\n' >> "$T/$W/t.yml"; expect fail "credential in a later job's env" "t.yml job b env: Claude/Anthropic credential"
fx; sed -i 's|      - id: claude|      - id: claude\n        env:\n          ANTHROPIC_API_KEY: x|' "$T/$W/t.yml"; expect fail "any env on the claude step" "env not allowed on a claude step"
fx; sed -i 's|prompt: "Do the task."|prompt: "${{ toJSON(secrets) }}"|' "$T/$W/t.yml"; expect fail "credential in the prompt" "in input 'prompt'"
fx; sed -i 's|,WebFetch,||' "$T/$W/t.yml"; expect fail "a claude step without one of the common denies" "--disallowedTools does not deny WebFetch (every claude step must)"
# Actions and jobs
fx; printf '      - uses: "./.github/actions/evil"\n' >> "$T/$W/t.yml"; expect fail "quoted local action not on the allow-list" "local action not on the allow-list: ./.github/actions/evil"
fx; printf '      - uses: ./.github/actions/install-gitleaks\n' >> "$T/$W/t.yml"; expect fail "local action after the claude step" "no local action after the claude step"
fx; printf '      - uses: docker://alpine:3\n' >> "$T/$W/t.yml"; expect fail "docker:// action" "not allowed: docker://alpine:3"
fx; printf '  r:\n    uses: org/repo/.github/workflows/w.yml@v1\n' >> "$T/$W/t.yml"; expect fail "reusable workflow job" "reusable workflow not allowed"
fx; sed -i 's|    runs-on: \[self-hosted, agents\]|    runs-on: [self-hosted, agents]\n    container: node:20|' "$T/$W/t.yml"; expect fail "container job" "'container' not allowed"
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
  fx; printf '      - run: echo hi\n        env:\n          X: %s\n' "$v" >> "$T/$W/t.yml"; expect fail "dynamic secrets use: $v" "secrets used other than as secrets.<NAME>"
done
fx; printf '      - run: echo hi\n        env:\n          X: ${{ secrets.OTHER_TOKEN }}\n' >> "$T/$W/t.yml"; expect ok "a non-Claude secret by name is fine" "Workflow denies OK"
fx; sed -i 's|^jobs:|permissions: "${{ secrets.CLAUDE_TOKEN_BUILD_V2 }}"\njobs:|' "$T/$W/t.yml"; expect fail "credential in workflow-level permissions" "t.yml permissions: Claude/Anthropic credential"
# The pre-installed binary may only run through the action
for cmd in '${{ steps.lock.outputs.claude-path }} -p hi' '$HOME/.local/bin/claude -p hi'; do
  fx; printf '      - run: %s\n' "$cmd" >> "$T/$W/t.yml"; expect fail "pre-installed Claude in a run step: $cmd" "runs Claude outside the pinned claude-code-action"
done
fx; printf '      - run: echo hi\n        env:\n          B: ${{ steps.lock.outputs.claude-path }}\n' >> "$T/$W/t.yml"; expect ok "binary path in env alone does not run it" "Workflow denies OK"
fx; printf '      - uses: anthropics/other-action@v1\n' >> "$T/$W/t.yml"; expect fail "another anthropic action" "runs Claude outside the pinned claude-code-action (anthropics/other-action@v1)"
fx; printf '      - uses: org/repo/.github/workflows/w.yml@v1\n' >> "$T/$W/t.yml"; expect fail "reusable workflow as a step" "not allowed: org/repo/.github/workflows/w.yml@v1"
# The checkout before the lock
fx; sed -i '/          ref: main/d' "$T/$W/t.yml";             expect fail "checkout without an explicit ref" "needs an explicit ref of the default branch"
fx; sed -i 's|          ref: main|          ref: ${{ github.event.pull_request.head.sha }}|' "$T/$W/t.yml"; expect fail "checkout of the PR head" "needs an explicit ref"
fx; sed -i 's|          ref: main|          ref: ${{ github.base_ref }}|' "$T/$W/t.yml"; expect fail "base_ref outside pull_request_target" "needs an explicit ref"
fx; sed -i 's|          ref: main|          ref: ${{ github.base_ref }}|; s|^on: workflow_dispatch|on: pull_request_target|' "$T/$W/t.yml"; expect ok "base_ref in a pull_request_target workflow" "Workflow denies OK"
fx; sed -i 's|          ref: main|          ref: ${{ github.event.repository.default_branch }}|' "$T/$W/t.yml"; expect ok "default-branch expression" "Workflow denies OK"
fx; sed -i '/          persist-credentials: false/d' "$T/$W/t.yml"; expect fail "checkout keeping credentials" "needs persist-credentials: false"
fx; sed -i 's|        uses: ./.github/actions/agent-egress-lock|        uses: ./.github/actions/agent-egress-lock\n        with:\n          extra-domains: blob.core.windows.net|' "$T/$W/t.yml"; expect fail "lock step with inputs" "may only have id/uses/name (found with)"
fx; sed -i 's|        uses: ./.github/actions/agent-egress-lock|        uses: ./.github/actions/agent-egress-lock\n        env:\n          AGENT_LOCK_SELFTEST_BREAK: "0"|' "$T/$W/t.yml"; expect fail "lock step with env" "(found env)"
fx; sed -i 's|        uses: ./.github/actions/agent-egress-lock|        uses: ./.github/actions/agent-egress-lock\n        if: false|' "$T/$W/t.yml"; expect fail "lock step with if" "(found if)"
fx; sed -i 's|      CLAUDE_CODE_SUBPROCESS_ENV_SCRUB: "1"|      CLAUDE_CODE_SUBPROCESS_ENV_SCRUB: "1"\n      AGENT_LOCK_TEST_DOCKER_SOCK: /x|' "$T/$W/t.yml"; expect fail "lock test hook in a claude job" "env 'AGENT_LOCK_TEST_DOCKER_SOCK' not allowed"
fx; sed -i 's|^jobs:|env:\n  AGENT_LOCK_SELFTEST_BREAK: "1"\njobs:|' "$T/$W/t.yml"; expect fail "workflow-level env in a claude workflow" "no workflow-level env in a workflow with a claude step"
# Job env: allow-list, and the subprocess scrub must be on
fx; sed -i '/      CLAUDE_CODE_SUBPROCESS_ENV_SCRUB: "1"/d; /^    env:$/d' "$T/$W/t.yml"; expect fail "subprocess scrub missing" 'needs env CLAUDE_CODE_SUBPROCESS_ENV_SCRUB: "1"'
fx; sed -i 's|      CLAUDE_CODE_SUBPROCESS_ENV_SCRUB: "1"|      CLAUDE_CODE_SUBPROCESS_ENV_SCRUB: "0"|' "$T/$W/t.yml"; expect fail "subprocess scrub turned off" 'needs env CLAUDE_CODE_SUBPROCESS_ENV_SCRUB: "1"'
for v in NODE_OPTIONS BASH_ENV ANTHROPIC_BASE_URL LD_PRELOAD; do
  fx; sed -i "s|      CLAUDE_CODE_SUBPROCESS_ENV_SCRUB: \"1\"|      CLAUDE_CODE_SUBPROCESS_ENV_SCRUB: \"1\"\n      $v: x|" "$T/$W/t.yml"; expect fail "job env $v" "env '$v' not allowed in a job with a claude step"
done
# claude_args values are limited per workflow
fx; sed -i 's|            --model haiku|            --model haiku\n            --permission-mode bypassPermissions|' "$T/$W/t.yml"; expect fail "bypassPermissions outside the manager" "--permission-mode bypassPermissions not allowed"
fx; sed -i 's|            --model haiku|            --model haiku\n            --permission-mode acceptEdits|' "$T/$W/t.yml"; expect fail "another permission mode" "--permission-mode acceptEdits not allowed"
fx; sed -i 's|            --model haiku|            --model haiku\n            --add-dir /tmp/pr|' "$T/$W/t.yml"; expect fail "--add-dir outside review.yml" "--add-dir /tmp/pr not allowed"
fresh; sed -i 's|--add-dir /tmp/pr|--add-dir /etc|' "$T/$W/review.yml"; expect fail "--add-dir elsewhere in review.yml" "--add-dir /etc not allowed"
for tool in 'Bash' 'Bash(*)' 'Write' 'Edit' 'WebFetch' 'Bash(find /tmp/pr:*)' 'Bash(git -C /tmp/pr grep:*)' 'Bash(yarn install:*)' 'Bash(yarn npm audit:*)' 'Bash(yarn why:*)' 'Bash(date:*)' 'Bash(date -f /etc/passwd)'; do
  fx; sed -i "s|            --model haiku|            --model haiku\n            --allowedTools \"Read,$tool\"|" "$T/$W/t.yml"; expect fail "allowedTools $tool outside the manager" "--allowedTools item '$tool' not allowed"
done
fx; sed -i 's|            --model haiku|            --model haiku\n            --allowedTools "Read(./**),Grep,Glob,Bash(gh pr view:*),Bash(gh issue view:*)"|' "$T/$W/t.yml"; expect ok "read-only allowedTools" "Workflow denies OK"
fx; sed -i 's|            --model haiku|            --model haiku\n            --allowedTools "Read,Grep"|' "$T/$W/t.yml"; expect fail "a bare Read allow (anywhere on the runner) is not read-only" "--allowedTools item 'Read' not allowed"
fx; sed -i 's|            --model haiku|            --model haiku\n            --allowedTools "Read(//tmp/pr/**)"|' "$T/$W/t.yml"; expect fail "another file's extra Read scope" "--allowedTools item 'Read(//tmp/pr/**)' not allowed"
fx; sed -i 's|            --model haiku|            --model haiku\n            --allowedTools "Read(//**)"|' "$T/$W/t.yml"; expect fail "a Read allow for every path" "--allowedTools item 'Read(//**)' not allowed"
fresh; python3 - "$T/$W/agent-manager.yml" <<'PYEOF'
import sys; p=sys.argv[1]; s=open(p).read()
s=s.replace("--permission-mode bypassPermissions", "--permission-mode bypassPermissions\n            --allowedTools \"Bash(*),Write\"", 1)
open(p,"w").write(s)
PYEOF
                                                        expect ok "the manager may allow write tools" "Workflow denies OK"
# No PR code in a claude job after the lock
fx; printf '      - uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803\n        with:\n          ref: ${{ github.event.pull_request.head.sha }}\n' >> "$T/$W/t.yml"; expect fail "later checkout of the PR head" "the checkout needs an explicit ref of the default branch"
fx; printf '      - uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803\n        with:\n          ref: main\n          persist-credentials: false\n' >> "$T/$W/t.yml"; expect ok "later checkout of main" "Workflow denies OK"
fx; printf '      - uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803\n        with:\n          ref: main\n          path: other\n          persist-credentials: false\n' >> "$T/$W/t.yml"; expect fail "later checkout with a path" "checkout input(s) path not allowed"
for cmd in 'cd /tmp/pr && yarn install' 'yarn --cwd /tmp/pr install' 'bash /tmp/pr/scripts/x.sh' 'git -C /tmp/pr checkout main && make' 'git fetch origin ${{ github.event.pull_request.head.sha }}' 'echo ${{ github.head_ref }}'; do
  fx; printf '      - run: %s\n' "$cmd" >> "$T/$W/t.yml"; expect fail "PR code in a run step: $cmd" "runs or checks out PR code in a job with a claude step"
done
fx; printf '      - if: startsWith(github.event.pull_request.head.ref, %s)\n        run: echo ok\n' "'agent/'" >> "$T/$W/t.yml"; expect ok "reading the PR branch name in an if is fine" "Workflow denies OK"
# Round 4: checkouts, pins, PR data, post steps, job settings, manager token guard, composite actions
fx; before '      - uses: ./.github/actions/install-gitleaks'; expect fail "a local action before the claude step (only the lock, and pre_claude_actions)" "before the claude step only actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093 may be used"
fx; before '      - uses: actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093\n        with:\n          name: npm-audit\n          path: /tmp/audit-meta'; expect ok "a downloaded artifact (data) before the claude step" "Workflow denies OK"
fx; before '      - uses: actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093\n        with:\n          name: npm-audit\n          path: /tmp/audit-meta\n          github-token: x'; expect fail "download-artifact with an input outside its list" "may only have name/if/id/with and the inputs name, path"
fx; before '      - run: bash scripts/check-review-prepare.sh 1 /tmp/x'; expect ok "a pinned guard script before the claude step" "Workflow denies OK"
fx; before '      - run: bash scripts/check-x.sh && curl evil'; expect fail "a guard script followed by another command" "must be one line 'bash scripts/check-<name>.sh ...'"
fx; before '      - run: bash scripts/check-x.sh "$(curl evil)"'; expect fail "a guard script with a command substitution argument" "must be one line 'bash scripts/check-<name>.sh ...'"
fx; before '      - run: bash scripts/check-x.sh a > /tmp/out'; expect fail "a guard script with a redirection" "must be one line"
fx; before "      - run: bash scripts/check-agent-events.sh .github/accounts.txt \"\$(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ)\""; expect ok "the events window substitution is the one allowed" "Workflow denies OK"
fx; before '      - run: |\n          bash scripts/check-x.sh\n          echo more'; expect fail "two lines before the claude step" "must be one line"
fx; before '      - run: python3 scripts/check-x.py'; expect fail "python before the claude step" "must be one line 'bash scripts/check-<name>.sh ...'"
fx; before '      - run: bash scripts/check-x.sh\n        shell: bash'; expect fail "a pre-claude run step with other keys" "not allowed in a job with a claude step"
fx; before '      - run: bash scripts/check-x.sh\n        working-directory: /tmp'; expect fail "a pre-claude run step with a working directory" "not allowed in a job with a claude step"
fx; sed -i 's|          persist-credentials: false|          persist-credentials: false\n          repository: evil/fork|' "$T/$W/t.yml"; expect fail "first checkout from another repository" "checkout input(s) repository not allowed"
fx; sed -i 's|          persist-credentials: false|          persist-credentials: false\n          token: x|' "$T/$W/t.yml"; expect fail "first checkout with a token" "checkout input(s) token not allowed"
fx; sed -i 's|      - uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803|      - uses: actions/checkout@v6|' "$T/$W/t.yml"; expect fail "unpinned first checkout" "step 1: action must be pinned to a full commit SHA: actions/checkout@v6"
fx; before '      - uses: actions/setup-node@v4'; expect fail "unpinned action in a claude job" "action must be pinned to a full commit SHA: actions/setup-node@v4"
fx; before '      - run: echo hi\n        working-directory: /tmp'; expect fail "working-directory in a claude job" "'working-directory' not allowed"
fx; before '      - run: echo hi\n        shell: python'; expect fail "custom shell in a claude job" "'shell' not allowed"
fx; sed -i 's|    runs-on: \[self-hosted, agents\]|    runs-on: [self-hosted, agents]\n    defaults:\n      run:\n        working-directory: /tmp/pr|' "$T/$W/t.yml"; expect fail "job defaults in a claude job" "'defaults' not allowed"
fx; sed -i 's|    runs-on: \[self-hosted, agents\]|    runs-on: ubuntu-latest|' "$T/$W/t.yml"; expect fail "claude job on GitHub's runner" "runs-on must be ['self-hosted', 'agents'] (jobs with a claude step run on the agents' runners)"
fx; sed -i 's|    runs-on: \[self-hosted, agents\]|    runs-on: self-hosted|' "$T/$W/t.yml"; expect fail "self-hosted without the agents label" "a self-hosted job must use runs-on: ['self-hosted', 'agents']"
fx; sed -i 's|    runs-on: \[self-hosted, agents\]|    runs-on: [self-hosted, agents, gpu]|' "$T/$W/t.yml"; expect fail "extra runner label" "a self-hosted job must use runs-on: ['self-hosted', 'agents']"
fx; sed -i 's|    runs-on: \[self-hosted, agents\]|    runs-on: ${{ vars.RUNNER }}|' "$T/$W/t.yml"; expect fail "runs-on from an expression" "runs-on must be a plain string or list of labels"
fx; sed -i 's|    runs-on: \[self-hosted, agents\]|    runs-on: windows-latest|' "$T/$W/t.yml"; expect fail "another hosted runner" "runs-on must be ubuntu-latest or ['self-hosted', 'agents']"
fresh; printf 'name: y\non: push\njobs:\n  a:\n    runs-on: [agents]\n    steps:\n      - run: echo\n' > "$T/$W/s.yml"; expect fail "agents label alone in a plain job" "a self-hosted job must use runs-on: ['self-hosted', 'agents']"
fresh; plain s.yml; sed -i 's|    runs-on: ubuntu-latest|    runs-on: [self-hosted, agents]|' "$T/$W/s.yml"; expect ok "plain job on the agents' runners" "Workflow denies OK"
fresh; printf 'name: y\non: push\njobs:\n  a:\n    steps:\n      - run: echo\n' > "$T/$W/s.yml"; expect fail "job without runs-on" "runs-on must be a plain string or list of labels"
fx; sed -i 's|    permissions:\n      contents: read|    permissions: write-all|; /^    permissions:$/{N;s|.*|    permissions: write-all|}' "$T/$W/t.yml"; expect fail "write-all permissions" "permissions must be a mapping"
fx; sed -i '/^    permissions:$/{N;s|.*|    permissions:\n      packages: write|}' "$T/$W/t.yml"; expect fail "unknown permission scope" "permission packages: write not allowed"
# No permissions anywhere means the repository's default job token, which can hold every write scope (statuses: write
# among them, enough to forge a guards/main-guard status as github-actions[bot] from any job the agents' code runs in).
fx; sed -i '/^    permissions:$/{N;d}' "$T/$W/t.yml"; expect fail "no permissions on the job or the workflow" "t.yml job a: no permissions (set them on the job or the workflow; the repository's default token is not allowed)"
fx; sed -i '/^    permissions:$/{N;d}; s|^jobs:|permissions:\n  contents: read\njobs:|' "$T/$W/t.yml"; expect ok "workflow-level permissions cover a job without its own" "Workflow denies OK"
for cmd in 'cd "/tmp/pr" \&\& make' 'pushd /tmp/pr' 'make -C /tmp/pr' 'yarn --cwd=/tmp/pr install' 'bash -c "$(cat /tmp/pr/x)"' 'source /tmp/pr/env.sh' 'gh pr checkout ${{ github.event.pull_request.head.ref }}'; do
  fx; before "      - run: $cmd"; expect fail "PR data in a run step: $cmd" "only the reviewed prepare step may touch /tmp/pr"
done
fx; before '      - run: bash scripts/check-review-prepare.sh "$PR_NUMBER" /tmp/pr "origin/$BASE_REF" origin "$HEAD_SHA"'; expect ok "the reviewed prepare step may use /tmp/pr" "Workflow denies OK"
fx; before '      - run: bash scripts/check-review-prepare.sh "$PR_NUMBER" /tmp/pr "origin/$BASE_REF"'; expect fail "the prepare step without the expected head is not the reviewed one" "only the reviewed prepare step may touch /tmp/pr"
fx; printf '      - run: |\n          printf x | sha256sum --check --strict\n          echo /tmp/pr-meta/log.txt\n' >> "$T/$W/t.yml"; expect ok "/tmp/pr-meta is not PR code (after the claude step)" "Workflow denies OK"
fx; before '      - run: echo /tmp/pr-meta/log.txt'; expect fail "a free-form run before the claude step" "must be one line 'bash scripts/check-<name>.sh ...'"
fx; printf '      - run: bash scripts/check-review-post.sh pr 1 x\n' >> "$T/$W/t.yml"; expect fail "post step without the pin check" "must check its pinned files"
fx; printf '      - env:\n          PINS: x\n        run: |\n          printf "%%s\\n" "$PINS" | sha256sum --check --strict --quiet\n          bash scripts/check-review-post.sh pr 1 x\n' >> "$T/$W/t.yml"; expect ok "post step that checks its pins first" "Workflow denies OK"
fx; printf '      - run: /tmp/gitleaks detect\n' >> "$T/$W/t.yml"; expect fail "gitleaks after the claude step without the pin check" "must check its pinned files"
fx; sed -i 's|      - id: claude|      - id: claude\n        if: always()|' "$T/$W/t.yml"; expect fail "claude step running after a failure" "may not run after a failure"
fx; sed -i 's|      - id: claude|      - id: claude\n        continue-on-error: true|' "$T/$W/t.yml"; expect fail "claude step with continue-on-error" "key 'continue-on-error' not allowed"
fresh; sed -i '/check-agent-token.sh/d' "$T/$W/agent-manager.yml"; sed -i '/Agents must run on their own GitHub token/d' "$T/$W/agent-manager.yml"; expect fail "manager without the founder-token guard" "holds the agents' token, so its first step after checkout and the lock must run"
fresh; mkdir -p "$T/.github/actions/x"; printf 'name: x\nruns:\n  using: composite\n  steps:\n    - uses: actions/setup-node@v4\n' > "$T/.github/actions/x/action.yml"; expect fail "unpinned action inside a composite action" ".github/actions/x/action.yml step 1: action must be pinned"
fresh; mkdir -p "$T/.github/actions/x"; printf 'name: x\nruns:\n  using: composite\n  steps:\n    - run: echo ${{ secrets.CLAUDE_TOKEN_BUILD_V2 }}\n      shell: bash\n' > "$T/.github/actions/x/action.yml"; expect fail "Claude credential inside a composite action" ".github/actions/x/action.yml step 1: Claude/Anthropic credential"
fresh; mkdir -p "$T/.github/actions/x"; printf 'name: x\nruns:\n  using: node20\n  main: index.js\n' > "$T/.github/actions/x/action.yml"; expect fail "non-composite local action" "not a composite action with steps"
fresh; cp -r "$REPO/.github/actions" "$T/.github/"; expect ok "the real composite actions pass" "Workflow denies OK"
# Claude never runs in a pull_request workflow
fx; sed -i 's|^on: workflow_dispatch|on:\n  pull_request:\n  workflow_dispatch:|' "$T/$W/t.yml"; expect fail "claude step in a pull_request workflow" "must not run on pull_request"
fx; sed -i 's|^on: workflow_dispatch|on: [push, pull_request]|' "$T/$W/t.yml"; expect fail "pull_request in a trigger list" "must not run on pull_request"
# Malformed workflows
fx; sed -i 's|^          claude_code_oauth_token: .*|XX|' "$T/$W/t.yml"; sed -i '/^XX$/,/^      - name: After/{/^      - name: After/!d}' "$T/$W/t.yml"; sed -i 's|^        with:$|        with: just-a-string|' "$T/$W/t.yml"; sed -i '0,/        with: just-a-string/s||        with:|' "$T/$W/t.yml"
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
fresh; out=$(python3 -I "$PY" "$T" 2>&1); rc=$?
if [ $rc != 0 ] && grep -q "run through scripts/check-workflows.sh" <<<"$out"; then t PASS "the Python checker alone (no parsed manifests/accounts) fails closed"; else t FAIL "python alone"; echo "$out"; fi
out=$(CW_THIRD_PARTY= CW_ACCOUNT_ROWS="1 a founder" python3 -I "$PY" "$T" --manifest x 2>&1); rc=$?
if [ $rc != 0 ] && grep -q "bad argument '--manifest' (run through scripts/check-workflows.sh)" <<<"$out"; then t PASS "the Python checker takes no options"; else t FAIL "python options"; echo "$out"; fi
fresh;                                                  expect fail "--accounts without a value" "--accounts needs a file" --accounts
fresh;                                                  expect fail "unknown option" "bad argument '--x'" --x
fresh; out=$(python3 -I -S "$PY" "$T" 2>&1); rc=$?
if [ $rc != 0 ] && grep -q "PyYAML is missing; run through the venv from scripts/check-python-deps.sh" <<<"$out"; then t PASS "fails closed without PyYAML"; else t FAIL "without PyYAML"; echo "$out"; fi; rm -rf "$T"
# Round 5: more PR-data forms, git moves, workflow_run, id-token, tag mode, pin check order
for cmd in 'git fetch origin pull/7/head:pr' 'git fetch origin refs/pull/7/merge' 'gh pr checkout 7' 'echo ${{ github.event.pull_request.merge_commit_sha }}' 'echo ${{ github.event.issue.number }}'; do
  fx; before "      - run: $cmd"; expect fail "PR data in a run step: $cmd" "only the reviewed prepare step may touch /tmp/pr"
done
for cmd in 'git checkout feature' 'git -C . switch x' 'git fetch origin' 'git worktree add /tmp/w' 'git reset --hard origin/x' 'git pull'; do
  fx; before "      - run: $cmd"; expect fail "git move in a claude job: $cmd" "not allowed in a job with a claude step (the checkout must stay on the default branch)"
done
fx; printf '      - run: git log --oneline -5\n' >> "$T/$W/t.yml"; expect ok "git log is not a checkout move (after the claude step)" "Workflow denies OK"
fx; sed -i 's/^on: workflow_dispatch$/on:\n  workflow_run:\n    workflows: [CI]\n    types: [completed]/' "$T/$W/t.yml"; expect fail "claude step in a workflow_run workflow" "must not run on workflow_run"
fresh; sed -i 's/^      issues: read$/      issues: read\n      id-token: write/' "$T/$W/agent-manager.yml"; expect fail "id-token in agent-manager.yml" "permission id-token: write not allowed"
fresh; sed -i 's/^      contents: read$/      contents: write/' "$T/$W/agent-manager.yml"; expect fail "a write scope on the manager's job token" "permission contents: write is not allowed in agent-manager.yml (its job token is read-only"
fresh; sed -i 's/^      pull-requests: read$/      pull-requests: read\n      id-token: write/' "$T/$W/claude.yml"; expect fail "id-token in claude.yml (prompt mode needs no OIDC token)" "permission id-token: write not allowed"
fresh; grep -q 'id-token: write' "$T/$W/egress-lock-claude.yml" && expect ok "id-token stays allowed in the probe workflow's oidc job" "Workflow denies OK"
fresh; sed -i 's/^      pull-requests: read$/      pull-requests: read\n      statuses: write/' "$T/$W/claude.yml"; expect fail "statuses: write in claude.yml (only main-guard.yml and pusher-ledger.yml post commit statuses as the bot)" "permission statuses: write not allowed"
fresh; sed -i 's/^      issues: read$/      issues: read\n      statuses: read/' "$T/$W/agent-manager.yml"; expect fail "statuses in agent-manager.yml" "permission statuses: read not allowed"
# Tag mode (a claude step without a prompt) is still checked where it could appear: on issue_comment only, never on PRs
tagmode() { python3 - "$T/$W/claude.yml" "$1" "$2" <<'PYEOF'
import re, sys; p, old, new = sys.argv[1:4]; s = open(p).read()
s = re.sub(r'\n          # The comment.s text is not in the prompt[^\n]*\n          prompt: "[^\n]*"', "", s, count=1)   # no prompt: tag mode
assert old in s, old; open(p, "w").write(s.replace(old, new, 1))
PYEOF
}
fresh; tagmode "  issue_comment:
    types: [created]" "  pull_request_review_comment:
    types: [created]
  issue_comment:
    types: [created]"; expect fail "tag mode on PR review comments" "a claude step without a prompt (tag mode) may run only on issue_comment, issues (found pull_request_review_comment)"
fresh; tagmode " && !github.event.issue.pull_request" ""; expect fail "tag mode answering on PRs" "needs the job if to contain '!github.event.issue.pull_request'"
# Every claude step passes the job's own token (never the action's OIDC-backed app token), the manager the agents' token
fx; sed -i '/          github_token: \${{ github.token }}/d' "$T/$W/t.yml"; expect fail "claude step without github_token" "github_token must be exactly \${{ github.token }}"
fx; sed -i 's|          github_token: \${{ github.token }}|          github_token: \${{ secrets.AGENT_GH_TOKEN_V2 }}|' "$T/$W/t.yml"; expect fail "claude step with the agents' token as github_token" "github_token must be exactly \${{ github.token }}"
fresh; sed -i 's|          github_token: \${{ secrets.AGENT_GH_TOKEN_V2 }}|          github_token: \${{ github.token }}|' "$T/$W/agent-manager.yml"; expect fail "the manager with the job token as github_token" "github_token must be exactly \${{ secrets.AGENT_GH_TOKEN_V2 }}"
# A job that holds a secret runs only on a run's first attempt (a re-run of an old run would get today's secrets)
fx; sed -i "s|    if: github.run_attempt == '1'|    if: github.actor_id == '238822878'|" "$T/$W/t.yml"; expect fail "secret-holding job without the first-attempt condition" "holds a secret, so its 'if' must contain github.run_attempt == '1'"
fx; sed -i "/    if: github.run_attempt == '1'/d" "$T/$W/t.yml"; expect fail "secret-holding job without any if" "holds a secret, so its 'if' must contain github.run_attempt == '1'"
fresh; swap guards.yml $'    if: github.run_attempt == \'1\'\n' ""; expect fail "guards (the ledger key) without the first-attempt condition" "guards.yml job guards: holds a secret"
fresh; swap pusher-ledger.yml $'    if: github.run_attempt == \'1\'\n' ""; expect fail "the ledger without the first-attempt condition" "pusher-ledger.yml job record: holds a secret"
# The manager's installs run with lifecycle scripts off, whatever a PR's .yarnrc.yml says
fresh; sed -i '/      YARN_ENABLE_SCRIPTS: "false"/d' "$T/$W/agent-manager.yml"; expect fail "manager without YARN_ENABLE_SCRIPTS" 'needs env YARN_ENABLE_SCRIPTS: "false"'
fresh; sed -i 's|      YARN_ENABLE_SCRIPTS: "false"|      YARN_ENABLE_SCRIPTS: "true"|' "$T/$W/agent-manager.yml"; expect fail "manager with scripts on" 'needs env YARN_ENABLE_SCRIPTS: "false"'
# The main guard's stop list (policy stop_workflows) is every workflow with a secret or write scope, in both of its copies
fresh; printf 'name: s\non: workflow_dispatch\njobs:\n  a:\n    if: github.run_attempt == %s\n    runs-on: ubuntu-latest\n    permissions:\n      issues: write\n    steps:\n      - uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803\n%s\n      - run: echo\n' "'1'" "$PIN_STEP" > "$T/$W/z.yml"; expect fail "a new write-scoped workflow missing from stop_workflows" "stop_workflows in the policy must be every workflow holding a secret or a write scope"
fresh; sed -i 's|for w in agent-manager.yml review.yml|for w in review.yml|' "$T/$W/main-guard.yml"; expect fail "the fallback's list differs from the policy" "the fallback step's 'for w in ...' list must be exactly the policy's stop_workflows"
fresh; sed -i 's|MAIN_GUARD_WORKFLOWS:-agent-manager.yml |MAIN_GUARD_WORKFLOWS:-|' "$T/scripts/check-main-push.sh"; expect fail "the script's default differs from the policy" "the MAIN_GUARD_WORKFLOWS default must be exactly the policy's stop_workflows"
# The reports' manual runs are founder-gated like the manager's
fresh; swap agent-daily-report.yml "    if: (github.event_name == 'schedule' || github.actor_id == '238822878') && github.run_attempt == '1'
" "    if: github.run_attempt == '1'
"; expect fail "daily report without its founder gate" "agent-daily-report.yml: must let only a founder account start it"
fresh; swap agent-weekly-audit.yml "    if: always() && (github.event_name == 'schedule' || github.actor_id == '238822878') && github.run_attempt == '1'
" "    if: always() && github.run_attempt == '1'
"; swap agent-weekly-audit.yml "    if: (github.event_name == 'schedule' || github.actor_id == '238822878')
" ""; expect fail "weekly audit without its founder gate" "agent-weekly-audit.yml: must let only a founder account start it"
fx; printf '      - run: |\n          /tmp/gitleaks detect\n          printf x | sha256sum --check --strict\n' >> "$T/$W/t.yml"; expect fail "pin check after /tmp/gitleaks does not count" "must check its pinned files"
# Missing or broken policy file: fails closed
P0=$(mktemp -d "$TMPROOT/cwp.XXXXXX"); P2="$P0/scripts"; mkdir "$P2"; cp "$(dirname "$PY")"/check-workflows*.py "$P2/"
out=$(python3 -I "$P2/check-workflows.py" "$REPO" 2>&1); rc=$?
if [ $rc != 0 ] && grep -q "cannot read check-workflows-policy.json" <<<"$out"; then t PASS "missing policy file fails closed"; else t FAIL "missing policy file"; echo "$out"; fi
echo '{not json' > "$P2/check-workflows-policy.json"; out=$(python3 -I "$P2/check-workflows.py" "$REPO" 2>&1); rc=$?
if [ $rc != 0 ] && grep -q "cannot read check-workflows-policy.json" <<<"$out"; then t PASS "broken policy file fails closed"; else t FAIL "broken policy file"; echo "$out"; fi
rm -rf "$P0"
summary
