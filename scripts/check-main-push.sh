#!/usr/bin/env bash
# Runs on every push to main and on a schedule (main-guard.yml, founder-owned). Only founders merge: a push to main by
# anyone else is a bypass of guards, review and founder approval (the free plan cannot block pushes with a ruleset, and the
# agents' token has write access). For a non-founder push it: reverts the pushed commits with new commits (never a force
# push), stops the agents (cancels and disables every workflow that holds a secret or write scope) and opens a blocked
# security issue for the founders. Every run also checks that the previous push's head passed the main guard itself: a
# push whose head commit message says [skip ci] (or [ci skip], [no ci], [skip actions], [actions skip]) starts no
# workflow, and a run someone cancelled passed nothing, so one unchecked push breaks the chain at the next push or the
# scheduled run, which stops the agents and opens an issue (no revert: the guard cannot tell what that push was).
# Usage: scripts/check-main-push.sh <pusher-id> <before-sha> <after-sha> <accounts-file>   (a push event)
#        scripts/check-main-push.sh schedule - - <accounts-file>                           (the schedule: main's head)
#   Needs gh with GH_TOKEN (contents: write, actions: write, issues: write) and GH_REPO; git in the checkout of main
#   with the pushed commits present. Pushes made with the workflow's own token start no workflow, so this cannot loop.
#   MAIN_GUARD_WAIT (seconds to wait for a main-guard run still going; default 120) and MAIN_GUARD_WORKFLOWS: tests only.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/check-accounts-lib.sh
. "$HERE/check-accounts-lib.sh"
# shellcheck source=scripts/check-github-lib.sh
. "$HERE/check-github-lib.sh"
PUSHER="${1:?pusher id or schedule}"; BEFORE="${2:?before sha}"; AFTER="${3:?after sha}"; ACCOUNTS="${4:?accounts file}"
# Every workflow that holds a secret or acts with write scopes: all of them stop until a founder re-enables them, so no job
# runs tampered code with a token even if the revert below fails.
WORKFLOWS="${MAIN_GUARD_WORKFLOWS:-agent-manager.yml review.yml claude.yml agent-daily-report.yml agent-weekly-audit.yml egress-lock-claude.yml pusher-ledger.yml guards.yml}"
WAIT="${MAIN_GUARD_WAIT:-120}"
gh_context || exit 2
ZERO=0000000000000000000000000000000000000000
rows=$(accounts_rows "$ACCOUNTS") || { echo "$rows"; exit 1; }
founders=$(awk '$3 == "founder" {printf "@%s ", $2}' <<<"$rows")

stop_agents() { # stop_agents <title> <body>: cancel and disable the secret-holding workflows, open the security issue
  local cancelled=0 w st id off="" notoff="" stopped
  for w in $WORKFLOWS; do   # runs already going (the manager shift that pushed, for one) keep their tokens for up to 150 minutes
    for st in in_progress queued; do
      for id in $("$GH" run list --workflow "$w" --status "$st" --json databaseId --jq '.[].databaseId' 2>/dev/null); do
        "$GH" run cancel "$id" >/dev/null 2>&1 && cancelled=$((cancelled+1)) || true
      done
    done
  done
  for w in $WORKFLOWS; do "$GH" workflow disable "$w" >/dev/null 2>&1 && off+="$w " || notoff+="$w "; done
  stopped="cancelled $cancelled running or queued run(s); disabled ${off:-no workflow}(re-enable them after the review)"
  [ -z "$notoff" ] || stopped+="; could not disable $notoff- disable by hand"
  "$GH" issue create --title "$1" --label "area:security" --label "blocked" --label "priority:1" --body "$2 $stopped. $founders" >/dev/null 2>&1 \
    || echo "::error::could not open the security issue; founders: $2 $stopped"
  echo "$stopped"
}

# The previous push's head (or, on the schedule, main's head) must have passed the main guard itself.
chain_ok=1; chain_sha=""
if [ "$PUSHER" = schedule ]; then
  chain_sha=$(git rev-parse HEAD 2>/dev/null || true)
else
  [[ "$PUSHER" =~ ^[0-9]+$ ]] || { echo "ERROR: pusher id must be numeric: '$PUSHER'"; exit 2; }
  [[ "$BEFORE" =~ ^[0-9a-f]{40}$ ]] && [[ "$AFTER" =~ ^[0-9a-f]{40}$ ]] || { echo "ERROR: before/after must be 40-hex commit shas"; exit 2; }
  [ "$BEFORE" = "$ZERO" ] || chain_sha="$BEFORE"
fi
if [ -n "$chain_sha" ]; then
  if chain=$(main_guard_passed "$chain_sha" "$WAIT"); then echo "Chain: $chain"
  else chain_ok=0; case "$chain" in ERROR:*) echo "$chain"; exit 1;; esac; fi
fi
if [ "$chain_ok" = 0 ]; then
  echo "::error::commit $chain_sha reached main without passing the main guard ($chain): a push whose head says [skip ci], a cancelled run, or the workflow disabled at the time"
  stopped=$(stop_agents "SECURITY: a push to main passed no main-guard run (commit $chain_sha)" \
    "**A push to \`main\` was never checked by the main guard.** Commit \`$chain_sha\` is the head of a push that has no successful main-guard run ($chain): its commit message said \`[skip ci]\`, its run was cancelled, or the workflow was disabled at the time. Nothing was reverted (the guard cannot tell what that push contained). Founders: read that commit and the pushes after it (\`git log --first-parent\`), revert what should not be on main, rotate \`AGENT_GH_TOKEN_V2\` if the agents' account pushed it, then re-enable the workflows. What main-guard did:")
  echo "main-guard: unchecked push $chain_sha; $stopped"
  exit 1
fi
[ "$PUSHER" != schedule ] || { echo "Scheduled check: main's head $chain_sha passed the main guard."; exit 0; }

role=$(account_field "$rows" "$PUSHER" 3); login=$(account_field "$rows" "$PUSHER" 2)
if [ "$role" = founder ]; then echo "Push to main by founder '$login' (ID $PUSHER): OK."; exit 0; fi

echo "::error::push to main by user ID $PUSHER (${login:-not in $ACCOUNTS}, role ${role:-unknown}): only founders may push to main"
reverted=0; left=""; what=""
git config user.name "main-guard" && git config user.email "main-guard@users.noreply.github.com"
[ "$BEFORE" = "$ZERO" ] || git cat-file -e "$BEFORE^{commit}" 2>/dev/null || git fetch -q origin "$BEFORE" 2>/dev/null || true
if [ "$BEFORE" != "$ZERO" ] && git cat-file -e "$BEFORE^{commit}" 2>/dev/null && ! git merge-base --is-ancestor "$BEFORE" "$AFTER" 2>/dev/null; then
  # A force push rewrote main: put the previous tip back (only if main still is what this event says it is; the chain check
  # above proved that tip passed the main guard, so the guard never restores an unchecked commit).
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
stopped=$(stop_agents "SECURITY: non-founder push to main by user ID $PUSHER" \
  "**Someone other than a founder pushed to \`main\`.** Pusher: user ID $PUSHER (${login:-not in accounts.txt}, role ${role:-unknown}). Range: \`$range\`.

What main-guard did: $what;${left:+ **Left to do:** $left.}

Founders: check what the pushed commits contained (and any repositories the pusher's account owns), rotate \`AGENT_GH_TOKEN_V2\` if the agents' account was involved, then re-enable the workflows (Actions -> each workflow -> Enable). Also:")
echo "main-guard: $what; $stopped.${left:+ Left: $left}"
exit 1
