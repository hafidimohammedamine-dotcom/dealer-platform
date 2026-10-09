#!/usr/bin/env bash
# Prepares a pull request for review AS DATA: fetches refs/pull/<n>/head with a one-time token (no stored
# credentials), checks it out into <dest> outside the project folder, and removes every agent-instruction file
# (CLAUDE.md, CLAUDE.local.md, .mcp.json, .claude/ at any depth) from that working copy. Git history is untouched,
# so reviewers still see those files in 'git diff'.
# Usage: GIT_TOKEN=<token or empty> scripts/check-review-prepare.sh <pr-number> <dest> [remote]
set -euo pipefail
PR="${1:?pr number}"; DEST="${2:?destination}"; REMOTE="${3:-origin}"
[[ "$PR" =~ ^[0-9]+$ ]] || { echo "ERROR: bad PR number: $PR"; exit 1; }
[ ! -e "$DEST" ] || { echo "ERROR: $DEST already exists"; exit 1; }
auth=()
if [ -n "${GIT_TOKEN:-}" ]; then
  auth=(-c "http.extraheader=AUTHORIZATION: basic $(printf 'x-access-token:%s' "$GIT_TOKEN" | base64 -w0)")
fi
git "${auth[@]}" fetch -q "$REMOTE" "+refs/pull/$PR/head:refs/remotes/pr/head"
git worktree add -q --detach "$DEST" refs/remotes/pr/head
find "$DEST" -path "$DEST/.git" -prune -o \( -name CLAUDE.md -o -name CLAUDE.local.md -o -name .mcp.json \) -print0 | xargs -0 -r rm -rf
find "$DEST" -path "$DEST/.git" -prune -o -type d -name .claude -print0 | xargs -0 -r rm -rf
left=$(find "$DEST" -path "$DEST/.git" -prune -o \( -name CLAUDE.md -o -name CLAUDE.local.md -o -name .mcp.json -o -name .claude \) -print)
[ -z "$left" ] || { echo "ERROR: rule files left in $DEST:"; echo "$left"; exit 1; }
echo "PR #$PR head $(git -C "$DEST" rev-parse HEAD) ready in $DEST (rule files removed)"
