#!/usr/bin/env bash
# Runs on every push to main and on a schedule (main-guard.yml, founder-owned). Only founders merge: a push to main by
# anyone else is a bypass of guards, review and founder approval (the free plan cannot block pushes with a ruleset, and the
# agents' token has write access). For a non-founder push it: puts the previous tip's tree back with one undo commit
# (never per-commit reverts, never a force push on top), stops the agents (cancels and disables every workflow that holds a secret or write scope) and opens a blocked
# security issue for the founders. Every run also checks that the previous push's head passed the main guard itself: a
# push whose head commit message says [skip ci] (or [ci skip], [no ci], [skip actions], [actions skip]) starts no
# workflow, and a run someone cancelled passed nothing, so one unchecked push breaks the chain at the next push or the
# scheduled run, which stops the agents and opens an issue (no revert: the guard cannot tell what that push was). The same
# check requires main to still descend from the newest checked head (main_guard_lineage): a force push back to an older,
# once-checked commit with the workflow disabled is caught the same way.
# The undo commit this guard pushes starts no run of its own (a push made with a workflow's token starts no workflow),
# so the guard marks it with the guards/main-guard commit status instead (mark_main_guard_passed); a founder who has read
# an unchecked commit accepts it the same way, by running this workflow by hand (Actions -> Main guard -> Run workflow,
# with the commit's sha): the status is posted only when the person who started that run is a founder.
# Usage: scripts/check-main-push.sh <pusher-id> <before-sha> <after-sha> <accounts-file>   (a push event)
#        scripts/check-main-push.sh schedule - - <accounts-file>                           (the schedule: main's head)
#        scripts/check-main-push.sh accept <actor-id> <sha> <accounts-file>                (workflow_dispatch by a founder)
#   Needs gh with GH_TOKEN (contents: write, actions: write, issues: write, statuses: write) and GH_REPO; git in the checkout
#   of main with the pushed commits present (no working tree needed: the undo commit is built with commit-tree).
#   MAIN_GUARD_WAIT (seconds to wait for a main-guard run still going; default 120) and MAIN_GUARD_WORKFLOWS: tests only,
#   ignored inside Actions (a step that ran before could have written $GITHUB_ENV).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/check-accounts-lib.sh
. "$HERE/check-accounts-lib.sh"
# shellcheck source=scripts/check-github-lib.sh
. "$HERE/check-github-lib.sh"
PUSHER="${1:?pusher id or schedule}"; BEFORE="${2:?before sha}"; AFTER="${3:?after sha}"; ACCOUNTS="${4:?accounts file}"
# Every workflow that holds a secret or acts with write scopes: all of them stop until a founder re-enables them, so no job
# runs tampered code with a token even if the undo below fails.
[ -z "${GITHUB_ACTIONS:-}" ] || unset MAIN_GUARD_WORKFLOWS MAIN_GUARD_WAIT
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

# A founder accepts a commit the guard never checked (after reading it): the guards/main-guard status on it mends the chain.
if [ "$PUSHER" = accept ]; then
  ACTOR="$BEFORE"; SHA="$AFTER"
  [[ "$ACTOR" =~ ^[0-9]+$ ]] || { echo "ERROR: the actor id must be numeric: '$ACTOR'"; exit 2; }
  [[ "$SHA" =~ ^[0-9a-f]{40}$ ]] || { echo "ERROR: the commit to accept must be a 40-hex sha: '$SHA'"; exit 2; }
  [ "$(account_field "$rows" "$ACTOR" 3)" = founder ] || { echo "::error::only a founder may accept a commit; user ID $ACTOR is not one. Nothing was marked."; exit 1; }
  [ -z "${GITHUB_ACTIONS:-}" ] || [ "${GITHUB_REF:-}" = refs/heads/main ] || { echo "::error::run this workflow from the main branch (this run used '${GITHUB_REF:-}'); nothing was marked."; exit 1; }
  git merge-base --is-ancestor "$SHA" HEAD 2>/dev/null || { echo "::error::commit $SHA is not on main (this checkout); nothing was marked."; exit 1; }
  mark_main_guard_passed "$SHA" "accepted by founder $ACTOR (main-guard run ${GITHUB_RUN_ID:-local})" || { echo "ERROR: could not post the $MAIN_GUARD_STATUS status on $SHA."; exit 1; }
  echo "Accepted: commit $SHA now carries the $MAIN_GUARD_STATUS status (founder ID $ACTOR). Re-enable the workflows when the review is done."
  exit 0
fi
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
if [ "$chain_ok" = 0 ] && [ "${chain#rolled back}" != "$chain" ]; then   # main points at an older, once-checked commit
  echo "::error::main was moved back to an older commit ($chain): a force push with the main guard disabled or its run cancelled"
  stopped=$(stop_agents "SECURITY: main was moved back to an older commit ($chain_sha)" \
    "**\`main\` was moved back to an older commit.** $chain. No main-guard run recorded that move (the workflow was disabled or the run cancelled meanwhile), so the commits after it are gone from \`main\`. Nothing was restored by the guard. Founders: read the repository's audit log for who moved it, put \`main\` back to the last checked head by hand, rotate \`AGENT_GH_TOKEN_V2\` if the agents' account did it, then re-enable the workflows. What main-guard did:")
  echo "main-guard: rolled back $chain_sha; $stopped"
  exit 1
fi
if [ "$chain_ok" = 0 ]; then
  echo "::error::commit $chain_sha reached main without passing the main guard ($chain): a push whose head says [skip ci], a cancelled run, or the workflow disabled at the time"
  stopped=$(stop_agents "SECURITY: a push to main passed no main-guard run (commit $chain_sha)" \
    "**A push to \`main\` was never checked by the main guard.** Commit \`$chain_sha\` is the head of a push that has no successful main-guard run ($chain): its commit message said \`[skip ci]\`, its run was cancelled, or the workflow was disabled at the time. Nothing was reverted (the guard cannot tell what that push contained). Founders: read that commit and the pushes after it (\`git log --first-parent\`), revert what should not be on main, rotate \`AGENT_GH_TOKEN_V2\` if the agents' account pushed it, accept the commit (Actions -> Main guard -> Run workflow, sha \`$chain_sha\`: a founder's run marks it checked), then re-enable the workflows. What main-guard did:")
  echo "main-guard: unchecked push $chain_sha; $stopped"
  exit 1
fi
[ "$PUSHER" != schedule ] || { echo "Scheduled check: main's head $chain_sha passed the main guard."; exit 0; }

role=$(account_field "$rows" "$PUSHER" 3); login=$(account_field "$rows" "$PUSHER" 2)
if [ "$role" = founder ]; then echo "Push to main by founder '$login' (ID $PUSHER): OK."; exit 0; fi

echo "::error::push to main by user ID $PUSHER (${login:-not in $ACCOUNTS}, role ${role:-unknown}): only founders may push to main"
left=""; what=""; range="$BEFORE..$AFTER"
git config user.name "main-guard" && git config user.email "main-guard@users.noreply.github.com"
[ "$BEFORE" = "$ZERO" ] || git cat-file -e "$BEFORE^{commit}" 2>/dev/null || git fetch -q origin "$BEFORE" 2>/dev/null || true
if [ "$BEFORE" = "$ZERO" ]; then
  range="(new branch) ..$AFTER"; left="main was created by this push; there is no previous tip to restore - the founders reset main by hand"
elif ! git cat-file -e "$BEFORE^{commit}" 2>/dev/null; then
  left="the previous tip $BEFORE is not in this checkout and could not be fetched; the founders restore main by hand"
elif ! git merge-base --is-ancestor "$BEFORE" "$AFTER" 2>/dev/null; then
  # A force push rewrote main: put the previous tip back (only if main still is what this event says it is; the chain check
  # above proved that tip passed the main guard, so the guard never restores an unchecked commit).
  range+=" (force push)"
  if git push --force-with-lease="main:$AFTER" origin "$BEFORE:refs/heads/main" >/dev/null 2>&1; then
    what="restored main to $BEFORE after a force push (the rewritten history is gone from main)"
  else left="main was force-pushed and could not be restored to $BEFORE (check the job log); the founders restore it by hand"; fi
elif [ "$(git rev-parse HEAD 2>/dev/null)" != "$AFTER" ]; then   # main moved on (or this is a re-run): undoing again would undo more
  left="main is no longer at $AFTER (a later push, or a re-run of this job); nothing undone - the founders check main by hand"
else
  # One undo commit whose tree is exactly the previous tip's, built without a working tree (commit-tree; the checkout may be
  # sparse or broken): never per-commit reverts (a pushed merge whose first parent is an older main commit would make
  # `revert -m 1` roll main back to that older tree, and a revert can conflict or stop halfway). The commit may be empty (a
  # push that changed no file) and still becomes the head.
  if undo=$(git commit-tree "$BEFORE^{tree}" -p "$AFTER" -m "main-guard: undo push $BEFORE..$AFTER by user ID $PUSHER" 2>/dev/null) \
     && [[ "$undo" =~ ^[0-9a-f]{40}$ ]] && git diff --quiet "$BEFORE" "$undo" 2>/dev/null; then
    if ! git push origin "$undo:refs/heads/main" >/dev/null 2>&1; then left="the undo commit could not be pushed (check the job log); the founders restore main by hand"
    else   # that push starts no run of its own (a workflow's token): mark its head checked
      what="restored main to the tree of $BEFORE with one undo commit ($undo)"
      mark_main_guard_passed "$undo" "undo by main-guard run ${GITHUB_RUN_ID:-local}" \
        || left="the undo commit $undo could not be marked with the $MAIN_GUARD_STATUS status; the next run will flag it, so a founder accepts it (Actions -> Main guard -> Run workflow)"
    fi
  else left="the undo commit could not be made (check the job log); the founders restore main by hand"; fi
fi
: "${what:=nothing undone}"
stopped=$(stop_agents "SECURITY: non-founder push to main by user ID $PUSHER" \
  "**Someone other than a founder pushed to \`main\`.** Pusher: user ID $PUSHER (${login:-not in accounts.txt}, role ${role:-unknown}). Range: \`$range\`.

What main-guard did: $what;${left:+ **Left to do:** $left.}

Founders: check what the pushed commits contained (and any repositories the pusher's account owns), rotate \`AGENT_GH_TOKEN_V2\` if the agents' account was involved, then re-enable the workflows (Actions -> each workflow -> Enable). Also:")
echo "main-guard: $what; $stopped.${left:+ Left: $left}"
exit 1
