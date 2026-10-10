#!/usr/bin/env bash
# Runs on every push to main (main-guard.yml, founder-owned). Only founders merge: a push to main by anyone else is a
# bypass of guards, review and founder approval (the free plan cannot block pushes with a ruleset, and the agents' token
# has write access). For a non-founder push it: reverts the pushed commits with new commits (never a force push), stops
# the agents (disables the manager workflow) and opens a blocked security issue for the founders.
# Usage: scripts/check-main-push.sh <pusher-id> <before-sha> <after-sha> <accounts-file>
#   Needs gh with GH_TOKEN (contents: write, actions: write, issues: write) and GH_REPO; git in the checkout of main
#   with the pushed commits present. Pushes made with the workflow's own token start no workflow, so this cannot loop.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/check-accounts-lib.sh
. "$HERE/check-accounts-lib.sh"
PUSHER="${1:?pusher id}"; BEFORE="${2:?before sha}"; AFTER="${3:?after sha}"; ACCOUNTS="${4:?accounts file}"
MANAGER_WORKFLOW="${MAIN_GUARD_MANAGER:-agent-manager.yml}"
: "${GH_REPO:?GH_REPO (owner/repo)}"
[[ "$PUSHER" =~ ^[0-9]+$ ]] || { echo "ERROR: pusher id must be numeric: '$PUSHER'"; exit 2; }
[[ "$BEFORE" =~ ^[0-9a-f]{40}$ ]] && [[ "$AFTER" =~ ^[0-9a-f]{40}$ ]] || { echo "ERROR: before/after must be 40-hex commit shas"; exit 2; }
rows=$(accounts_rows "$ACCOUNTS") || { echo "$rows"; exit 1; }
role=$(awk -v i="$PUSHER" '$1 == i {print $3; exit}' <<<"$rows"); login=$(awk -v i="$PUSHER" '$1 == i {print $2; exit}' <<<"$rows")
if [ "$role" = founder ]; then echo "Push to main by founder '$login' (ID $PUSHER): OK."; exit 0; fi
founders=$(awk '$3 == "founder" {printf "@%s ", $2}' <<<"$rows")

echo "::error::push to main by user ID $PUSHER (${login:-not in $ACCOUNTS}, role ${role:-unknown}): only founders may push to main"
if [ "$BEFORE" = "0000000000000000000000000000000000000000" ]; then
  commits=$(git rev-list --max-count=50 "$AFTER" 2>/dev/null || true); range="(new branch) ..$AFTER"
else
  commits=$(git rev-list "$BEFORE".."$AFTER" 2>/dev/null || true); range="$BEFORE..$AFTER"
fi
reverted=0; left=""
if [ -z "$commits" ]; then
  left="could not list the pushed commits ($range); revert them by hand"
else
  git config user.name "main-guard" && git config user.email "main-guard@users.noreply.github.com"
  for c in $commits; do   # newest first: each revert undoes one pushed commit (a merge commit against its first parent)
    if [ "$(git rev-list --parents -n 1 "$c" | wc -w)" -gt 2 ]; then m=(-m 1); else m=(); fi
    if git revert --no-edit "${m[@]}" "$c" >/dev/null 2>&1; then reverted=$((reverted+1)); else git revert --abort 2>/dev/null || true; left="revert of $c did not apply cleanly; the founders revert the rest by hand"; break; fi
  done
  if [ "$reverted" -gt 0 ]; then
    git push origin HEAD:refs/heads/main >/dev/null 2>&1 || left="the revert could not be pushed (${left:-check the job log})"
  fi
fi
gh workflow disable "$MANAGER_WORKFLOW" >/dev/null 2>&1 && stopped="disabled $MANAGER_WORKFLOW (re-enable it after the review)" \
  || stopped="could not disable $MANAGER_WORKFLOW; disable it by hand"
body="**Someone other than a founder pushed to \`main\`.** Pusher: user ID $PUSHER (${login:-not in accounts.txt}, role ${role:-unknown}). Range: \`$range\`.

What main-guard did: reverted $reverted pushed commit(s) with new commits on main; $stopped.${left:+ **Left to do:** $left}

Founders: check what the pushed commits contained (and any repositories the pusher's account owns), rotate \`AGENT_GH_TOKEN\` if the agents' account was involved, then re-enable the manager. $founders"
gh issue create --title "SECURITY: non-founder push to main by user ID $PUSHER" --label "area:security" --label "blocked" --label "priority:1" --body "$body" >/dev/null 2>&1 \
  || echo "::error::could not open the security issue; founders: $body"
echo "Reverted $reverted commit(s); $stopped.${left:+ Left: $left}"
exit 1
