#!/usr/bin/env bash
# Tests the identity and token rules of scripts/check-workflows.sh (scripts/check-workflows-people.py): people are matched
# by numeric user ID from .github/accounts.txt, never by login, and every job holding the agents' token checks it first.
# Also runs the real guards.yml step on a temp base checkout, so its wiring (archive paths, --accounts) is tested.
set -uo pipefail
# shellcheck source=scripts/check-workflows-testlib.sh
. "$(cd "$(dirname "$0")" && pwd)/check-workflows-testlib.sh"
MGR="github.actor_id == '238822878'"
CLA="github.event.comment.user.id == 238822878"
REV="github.event.pull_request.user.id == 250452267"
GUARD='        run: bash scripts/check-agent-token.sh .github/accounts.txt'

# Logins are never compared, in any spelling; bot names may be
for f in "github.actor == 'someone'" "'someone' == github.actor" "github.Actor == 'someone'" "github['actor'] == 'someone'" \
         "github.triggering_actor == 'someone'" "contains(fromJSON('[\"someone\"]'), github.actor)" "github.event.sender.login != 'x'"; do
  fresh; swap agent-manager.yml "$MGR" "$f"; expect fail "login compared as: $f" "refers to a login in 'if' (logins can be re-registered)"
done
fresh; grep -q "github.actor == 'github-actions\[bot\]'" "$T/$W/agent-manager.yml" && expect ok "a bot name may be compared" "Workflow denies OK"
fresh; swap agent-manager.yml "github.actor == 'github-actions[bot]'" "'github-actions[bot]' == github.actor"; expect ok "a bot name on the left is fine too" "Workflow denies OK"
# IDs: only listed accounts, only as a direct comparison with a number
for f in "github.actor_id == '12345'" "12345 == github.actor_id" "'12345' == github.actor_id" "github.Actor_ID == '12345'"; do
  fresh; swap agent-manager.yml "$MGR" "$f"; expect fail "unknown ID compared as: $f" "user ID 12345 is not in .github/accounts.txt"
done
for f in "contains(fromJSON('[238822878]'), github.actor_id)" "github.actor_id == vars.FOUNDER" "github.event.comment.user.id != ''"; do
  fresh; swap agent-manager.yml "$MGR" "$f"; expect fail "ID used indirectly: $f" "compare user IDs only as '<user id> == <number>'"
done
fresh; swap agent-manager.yml "$MGR" "238822878 == github.actor_id"; expect ok "founder ID on the left is fine" "Workflow denies OK"
# The gates themselves cannot be dropped or pointed at the wrong role
fresh; swap claude.yml " && $CLA" "";                     expect fail "claude.yml without its founder-ID clause" "claude.yml: must let only a founder account start it"
fresh; swap agent-manager.yml "      $MGR ||
" "";                                                      expect fail "manager without its founder-ID clause" "agent-manager.yml: must let only a founder account start it"
fresh; swap review.yml "$REV" "github.event.pull_request.user.id == 238822878"; expect fail "fix rounds gated on a founder, not the agent" "review.yml: must let only an agent account start it"
fresh; swap claude.yml "$CLA" "github.event.comment.user.id == 250452267"; expect fail "claude.yml gated on the agent account" "claude.yml: must let only a founder account start it"
# The accounts list: well formed, from the base branch when guards passes --accounts
fresh; printf '238822878 hafidimohammedamine-dotcom\n' > "$T/.github/accounts.txt"; expect fail "accounts line without a role" "bad line 1 in"
fresh; printf '250452267 mohammedaminehafidi-ctrl agent\n' > "$T/.github/accounts.txt"; expect fail "accounts without a founder" "no founder listed in"
fresh; rm "$T/.github/accounts.txt"; expect fail "no accounts file" "accounts file not found"
fresh; rm "$T/.github/accounts.txt"; out=$(bash "$SCRIPT" "$T" 2>&1); grep -qE "^ERROR: accounts file not found" <<<"$out" && ! grep -q "ERROR: ERROR" <<<"$out" && t PASS "the accounts error carries one ERROR prefix" || { t FAIL "accounts error prefix"; echo "$out"; }; rm -rf "$T"
fresh; printf '238822878 hafidimohammedamine-dotcom founder\n250452267 mohammedaminehafidi-ctrl agent\n12345 evil founder\n' > "$T/.github/accounts.txt"
swap agent-manager.yml "$MGR" "github.actor_id == '12345'"; B=$(mktemp -d "$TMPROOT/cwa.XXXXXX"); cp "$REPO/.github/accounts.txt" "$B/"
expect fail "a PR that lists itself in its own accounts file is checked against the base list" "user ID 12345 is not in .github/accounts.txt" --accounts "$B/accounts.txt"; rm -rf "$B"
fresh; expect fail "--accounts without a file" "--accounts needs a file" --accounts
# Every job holding the agents' token runs the token check first, as a plain step
for edit in "        continue-on-error: true\n$GUARD" "        if: false\n$GUARD" "        env:\n          GH_TOKEN: \${{ github.token }}\n$GUARD" \
            "        working-directory: /tmp\n$GUARD"; do
  fresh; swap agent-manager.yml "$GUARD" "$(printf '%b' "$edit")"; expect fail "token check weakened: ${edit//\\n/ / }" "the agents' token check step may only have name and run"
done
for edit in "        run: bash scripts/check-agent-token.sh /dev/null" "        run: bash scripts/check-agent-token.sh" "$GUARD || true" "        run: true"; do
  fresh; swap agent-manager.yml "$GUARD" "$edit"; expect fail "token check replaced: $edit" "its first step after checkout and the lock must run 'bash scripts/check-agent-token.sh .github/accounts.txt'"
done
fx; sed -i 's|      CLAUDE_CODE_SUBPROCESS_ENV_SCRUB: "1"|      CLAUDE_CODE_SUBPROCESS_ENV_SCRUB: "1"\n      GH_TOKEN: ${{ secrets.agent_gh_token_v2 }}|' "$T/$W/t.yml"; expect fail "lower-case secret name still needs the token check" "t.yml job a: holds the agents' token"
fresh; printf 'name: p\non: workflow_dispatch\njobs:\n  push:\n    if: github.run_attempt == '"'"'1'"'"'\n    runs-on: ubuntu-latest\n    env:\n      GH_TOKEN: ${{ secrets.AGENT_GH_TOKEN_V2 }}\n    steps:\n      - run: git push origin HEAD:refs/heads/x\n' > "$T/$W/p.yml"
expect fail "a job without a claude step that holds the token needs the check too" "p.yml job push: holds the agents' token"
fresh; printf 'name: p\non: workflow_dispatch\njobs:\n  push:\n    if: github.run_attempt == '"'"'1'"'"'\n    runs-on: ubuntu-latest\n    env:\n      GH_TOKEN: ${{ secrets.AGENT_GH_TOKEN_V2 }}\n    steps:\n      - uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803\n%s\n      - run: bash scripts/check-agent-token.sh .github/accounts.txt\n      - run: git push origin HEAD:refs/heads/x\n' "$PIN_STEP" > "$T/$W/p.yml"
expect ok "a job without a claude step that checks the token first (after the pin step)" "Workflow denies OK"
fresh; printf 'name: p\non: workflow_dispatch\njobs:\n  push:\n    if: github.run_attempt == '"'"'1'"'"'\n    runs-on: ubuntu-latest\n    env:\n      GH_TOKEN: ${{ secrets.AGENT_GH_TOKEN_V2 }}\n    steps:\n      - uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803\n%s\n      - name: The repository files this job runs are the reviewed ones (pinned here, outside any push'"'"'s reach)\n        run: curl https://evil\n      - run: bash scripts/check-agent-token.sh .github/accounts.txt\n' "$PIN_STEP" > "$T/$W/p.yml"
expect fail "a second step that only carries the pin step's name does not count as one" "its first step after checkout and the lock must run"
fresh; printf 'name: p\non: workflow_dispatch\nenv:\n  GH_TOKEN: ${{ secrets.AGENT_GH_TOKEN_V2 }}\njobs:\n  a:\n    runs-on: ubuntu-latest\n    steps:\n      - run: bash scripts/check-agent-token.sh .github/accounts.txt\n' > "$T/$W/p.yml"
expect fail "the agents' token at workflow level" "p.yml: the agents' token may only be set in a job's env"
fresh; swap agent-manager.yml "$GUARD" "        run: echo first
      - name: later
$GUARD"; expect fail "token check not the first step after the lock" "its first step after checkout and the lock must run"

# guards.yml wiring: run the real step's commands on a temp base checkout whose refs/remotes/pr/head is this tree
guards_step() { python3 -I -c 'import sys, yaml; d = yaml.safe_load(open(sys.argv[1]))
print(next(s["run"] for s in d["jobs"]["guards"]["steps"] if "check-workflows.sh" in str(s.get("run", ""))))' "$1"; }
W2=$(mktemp -d "$TMPROOT/gw.XXXXXX"); mkdir -p "$W2/base" "$W2/pr-skills"
cp -r "$REPO/scripts" "$REPO/.claude" "$REPO/.github" "$REPO/.gitleaks.toml" "$REPO/CLAUDE.md" "$REPO/.yarnrc.yml" "$W2/base/"; rm -rf "$W2/base/scripts/__pycache__"
( cd "$W2/base" && git init -q . && git add -A && git -c user.email=a@b -c user.name=t commit -qm base && git update-ref refs/remotes/pr/head HEAD
  git archive refs/remotes/pr/head .claude | tar -x -C "$W2/pr-skills" )
step=$(guards_step "$REPO/.github/workflows/guards.yml" | sed "s#/tmp/pr-wf#$W2/pr-wf#g; s#/tmp/pr-skills#$W2/pr-skills#g")
out=$(cd "$W2/base" && bash -c "$step" 2>&1); rc=$?
if [ $rc = 0 ] && grep -qF "Workflow denies OK" <<<"$out" && [ -f "$W2/pr-wf/.github/pins.txt" ] && [ -f "$W2/pr-wf/CLAUDE.md" ]; then
  t PASS "the guards.yml step passes with the whole PR tree unpacked as data (workflows, actions, pins, rule files)"
else t FAIL "the guards.yml step (rc=$rc)"; echo "$out" | tail -n 4; fi
rm -rf "$W2"
# The manager's after-shift checks live in their own job (policy after_shift): fresh runner, always after the shift
fresh; python3 - "$T/$W/agent-manager.yml" <<'PYEOF'
import sys; p = sys.argv[1]; s = open(p).read(); open(p, "w").write(s[:s.index("  after:\n")])
PYEOF
expect fail "manager without the after job" "needs a job 'after' that runs the after-shift checks on a fresh runner"
fresh; swap agent-manager.yml $'    needs: shift\n    if: always() && github.run_attempt == \'1\'\n' $'    needs: shift\n    if: success() && github.run_attempt == \'1\'\n'; expect fail "after job that skips failed shifts" "must have needs: shift and if: always() && github.run_attempt == '1'"
fresh; swap agent-manager.yml $'    needs: shift\n    if: always() && github.run_attempt == \'1\'\n' $'    if: always() && github.run_attempt == \'1\'\n'; expect fail "after job without needs" "must have needs: shift and if: always()"
fresh; python3 - "$T/$W/agent-manager.yml" <<'PYEOF'
import sys; p = sys.argv[1]; s = open(p).read()
i = s.index("  after:\n"); after = s[i:]
ev = [l for l in after.split("\n") if "check-agent-events.sh" in l][0]
open(p, "w").write(s[:i] + after.replace(ev + "\n", "        run: echo skipped\n", 1))
PYEOF
expect fail "after job without the event check" "must run exactly 'bash scripts/check-agent-events.sh .github/accounts.txt"
fresh; python3 - "$T/$W/agent-manager.yml" <<'PYEOF'
import sys; p = sys.argv[1]; s = open(p).read()
i = s.index("  after:\n"); after = s[i:]
tok = [l for l in after.split("\n") if "check-agent-token.sh" in l][0]
open(p, "w").write(s[:i] + after.replace(tok + "\n", "", 1))
PYEOF
expect fail "after job without the token re-check" "must run exactly 'bash scripts/check-agent-token.sh .github/accounts.txt'"
fresh; swap agent-manager.yml '      - name: Show blocked tool calls (names and commands only, pinned script)' $'      - run: bash scripts/check-agent-events.sh .github/accounts.txt "$SINCE"\n      - name: Show blocked tool calls (names and commands only, pinned script)'; expect fail "event check inside the shift job after Claude" "after Claude ran, the event check belongs in job 'after' only"
fresh; grep -q "Before the shift, the agents' account did nothing outside" "$T/$W/agent-manager.yml" && expect ok "the event check before Claude in the shift job is fine" "Workflow denies OK"
fresh; swap agent-manager.yml "        run: bash scripts/check-agent-events.sh .github/accounts.txt \"\$(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ)\"
      - name: Shift setup" "        run: bash scripts/check-agent-events.sh .github/accounts.txt \"\$SINCE\"
      - name: Shift setup"; expect fail "the event check before the shift with another window" "the event check before the shift must run exactly"
summary
