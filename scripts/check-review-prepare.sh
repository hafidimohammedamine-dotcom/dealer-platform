#!/usr/bin/env bash
# Prepares a pull request for review AS DATA: fetches refs/pull/<n>/head with a one-time token (no stored
# credentials), checks it out into <dest> outside the project folder, and removes every agent-instruction file
# (CLAUDE.md, CLAUDE.local.md, .mcp.json, .claude/ at any depth) from that working copy. Git history is untouched,
# so reviewers still see those files in 'git diff'.
# With <base-ref>, it also writes the PR's history as plain files to <dest>-meta (diff-stat.txt, diff.patch, files.txt,
# log.txt, log-patch.txt), so reviewers read them instead of running git (whose --output= could write files).
# Usage: GIT_TOKEN=<token or empty> scripts/check-review-prepare.sh <pr-number> <dest> [base-ref] [remote] [expected-head-sha]
# With <expected-head-sha> (the event's head), a PR that moved since the event fails instead of being reviewed against
# older CI and guards results.
set -euo pipefail
PR="${1:?pr number}"; DEST="${2:?destination}"; BASE="${3:-}"; REMOTE="${4:-origin}"; EXPECT="${5:-}"
[ -z "$EXPECT" ] || [[ "$EXPECT" =~ ^[0-9a-f]{40}$ ]] || { echo "ERROR: bad expected head sha: $EXPECT"; exit 1; }
[[ "$PR" =~ ^[0-9]+$ ]] || { echo "ERROR: bad PR number: $PR"; exit 1; }
[ ! -e "$DEST" ] || { echo "ERROR: $DEST already exists"; exit 1; }
META="$DEST-meta"
[ -z "$BASE" ] || [ ! -e "$META" ] || { echo "ERROR: $META already exists"; exit 1; }
[ -z "$BASE" ] || [[ "$BASE" =~ ^[A-Za-z0-9._/-]+$ ]] || { echo "ERROR: bad base ref: $BASE"; exit 1; }
auth=()
if [ -n "${GIT_TOKEN:-}" ]; then
  auth=(-c "http.extraheader=AUTHORIZATION: basic $(printf 'x-access-token:%s' "$GIT_TOKEN" | base64 -w0)")
fi
# No filters or hooks while the PR's files are written (NOFILTER, scripts/check-git-lib.sh): this job has no network lock.
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/check-git-lib.sh
. "$HERE/check-git-lib.sh"
git "${auth[@]}" "${NOFILTER[@]}" fetch -q "$REMOTE" "+refs/pull/$PR/head:refs/remotes/pr/head"
if [ -n "$EXPECT" ]; then   # the fetched head must be the event's: a newer push must not be reviewed against older results
  got=$(git rev-parse refs/remotes/pr/head)
  [ "$got" = "$EXPECT" ] || { echo "ERROR: the fetched PR head is $got, not this event's $EXPECT; the PR moved, see the newer run"; exit 1; }
fi
git_no_attributes "$(git rev-parse --git-dir)"   # the PR's .gitattributes must not rewrite or hide what the reviewers see
git "${NOFILTER[@]}" worktree add -q --detach "$DEST" refs/remotes/pr/head
find "$DEST" -path "$DEST/.git" -prune -o \( -name CLAUDE.md -o -name CLAUDE.local.md -o -name .mcp.json \) -print0 | xargs -0 -r rm -rf
find "$DEST" -path "$DEST/.git" -prune -o -type d -name .claude -print0 | xargs -0 -r rm -rf
left=$(find "$DEST" -path "$DEST/.git" -prune -o \( -name CLAUDE.md -o -name CLAUDE.local.md -o -name .mcp.json -o -name .claude \) -print)
[ -z "$left" ] || { echo "ERROR: rule files left in $DEST:"; echo "$left"; exit 1; }
# Only regular files and folders: a symlink (docs/x.md -> /proc/self/environ) read by a reviewer's tool would leak the job's
# environment, and sockets or devices have no place in a PR.
odd=$(find "$DEST" -path "$DEST/.git" -prune -o ! -type f ! -type d -print)
[ -z "$odd" ] || { echo "ERROR: symlinks or special files in the PR (only regular files and folders are reviewed):"; echo "$odd"; exit 1; }
if [ -n "$BASE" ]; then
  git -C "$DEST" rev-parse -q --verify "$BASE^{commit}" >/dev/null || { echo "ERROR: base ref not found: $BASE"; exit 1; }
  mkdir "$META"
  git -C "$DEST" diff --stat "$BASE...HEAD" > "$META/diff-stat.txt"
  git -C "$DEST" diff "$BASE...HEAD" > "$META/diff.patch"
  git -C "$DEST" diff --name-status "$BASE...HEAD" > "$META/files.txt"
  git -C "$DEST" log --format='%H %an <%ae> %aI%n    %s' "$BASE..HEAD" > "$META/log.txt"
  # --cc: merge commits too (as combined diffs), so a secret added and removed again inside a merge still shows.
  git -C "$DEST" log -p --cc "$BASE..HEAD" > "$META/log-patch.txt"
  echo "PR history written to $META"
fi
echo "PR #$PR head $(git -C "$DEST" rev-parse HEAD) ready in $DEST (rule files removed)"
