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
# Every workflow that holds a secret or acts with write scopes: all of them stop until a founder re-enables them, so no job
# runs tampered code with a token even if the revert below fails.
WORKFLOWS="${MAIN_GUARD_WORKFLOWS:-agent-manager.yml review.yml claude.yml agent-daily-report.yml agent-weekly-audit.yml egress-lock-claude.yml pusher-ledger.yml guards.yml}"
: "${GH_REPO:?GH_REPO (owner/repo)}"
[[ "$PUSHER" =~ ^[0-9]+$ ]] || { echo "ERROR: pusher id must be numeric: '$PUSHER'"; exit 2; }
[[ "$BEFORE" =~ ^[0-9a-f]{40}$ ]] && [[ "$AFTER" =~ ^[0-9a-f]{40}$ ]] || { echo "ERROR: before/after must be 40-hex commit shas"; exit 2; }
rows=$(accounts_rows "$ACCOUNTS") || { echo "$rows"; exit 1; }
role=$(account_field "$rows" "$PUSHER" 3); login=$(account_field "$rows" "$PUSHER" 2)
if [ "$role" = founder ]; then echo "Push to main by founder '$login' (ID $PUSHER): OK."; exit 0; fi
founders=$(awk '$3 == "founder" {printf "@%s ", $2}' <<<"$rows")

echo "::error::push to main by user ID $PUSHER (${login:-not in $ACCOUNTS}, role ${role:-unknown}): only founders may push to main"
ZERO=0000000000000000000000000000000000000000
reverted=0; left=""; what=""
git config user.name "main-guard" && git config user.email "main-guard@users.noreply.github.com"
[ "$BEFORE" = "$ZERO" ] || git cat-file -e "$BEFORE^{commit}" 2>/dev/null || git fetch -q origin "$BEFORE" 2>/dev/null || true
if [ "$BEFORE" != "$ZERO" ] && git cat-file -e "$BEFORE^{commit}" 2>/dev/null && ! git merge-base --is-ancestor "$BEFORE" "$AFTER" 2>/dev/null; then
  # A force push rewrote main: put the previous tip back (only if main still is what this event says it is).
  range="$BEFORE..$AFTER (force push)"
  if git push --force-with-lease="main:$AFTER" origin "$BEFORE:refs/heads/main" >/dev/null 2>&1; then
    what="restored main to $BEFORE after a force push (the rewritten history is gone from main)"
  else left="main was force-pushed and could not be restored to $BEFORE (check the job log); the founders restore it by hand"; fi
else
  if [ "$BEFORE" = "$ZERO" ]; then
    commits=$(git rev-list --first-parent --max-count=50 "$AFTER" 2>/dev/null || true); range="(new branch) ..$AFTER"
  else   # first-parent only: a merge commit's revert (-m 1) already undoes the whole branch it merged
    commits=$(git rev-list --first-parent "$BEFORE".."$AFTER" 2>/dev/null || true); range="$BEFORE..$AFTER"
  fi
  if [ -z "$commits" ]; then
    left="could not list the pushed commits ($range); revert them by hand"
  else
    for c in $commits; do   # newest first: each revert undoes one pushed commit (a merge commit against its first parent)
      if [ "$(git rev-list --parents -n 1 "$c" | wc -w)" -gt 2 ]; then m=(-m 1); else m=(); fi
      if git revert --no-edit "${m[@]}" "$c" >/dev/null 2>&1; then reverted=$((reverted+1)); else git revert --abort 2>/dev/null || true; left="revert of $c did not apply cleanly; the founders revert the rest by hand"; break; fi
    done
    if [ "$reverted" -gt 0 ]; then
      git push origin HEAD:refs/heads/main >/dev/null 2>&1 || { left="the revert could not be pushed (${left:-check the job log})"; reverted=0; }
    fi
  fi
  what="reverted $reverted pushed commit(s) with new commits on main"
fi
# Runs already going (the manager shift that pushed, for one) keep their tokens for up to 150 minutes: cancel them first.
cancelled=0
for w in $WORKFLOWS; do
  for st in in_progress queued; do
    for id in $(gh run list --workflow "$w" --status "$st" --json databaseId --jq '.[].databaseId' 2>/dev/null); do
      gh run cancel "$id" >/dev/null 2>&1 && cancelled=$((cancelled+1)) || true
    done
  done
done
off=""; notoff=""
for w in $WORKFLOWS; do gh workflow disable "$w" >/dev/null 2>&1 && off+="$w " || notoff+="$w "; done
stopped="cancelled $cancelled running or queued run(s); disabled ${off:-no workflow}(re-enable them after the review)"; [ -z "$notoff" ] || stopped+="; could not disable $notoff- disable by hand"
body="**Someone other than a founder pushed to \`main\`.** Pusher: user ID $PUSHER (${login:-not in accounts.txt}, role ${role:-unknown}). Range: \`$range\`.

What main-guard did: $what; $stopped.${left:+ **Left to do:** $left}

Founders: check what the pushed commits contained (and any repositories the pusher's account owns), rotate \`AGENT_GH_TOKEN\` if the agents' account was involved, then re-enable the workflows (Actions -> each workflow -> Enable). $founders"
gh issue create --title "SECURITY: non-founder push to main by user ID $PUSHER" --label "area:security" --label "blocked" --label "priority:1" --body "$body" >/dev/null 2>&1 \
  || echo "::error::could not open the security issue; founders: $body"
echo "main-guard: $what; $stopped.${left:+ Left: $left}"
exit 1
