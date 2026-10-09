#!/usr/bin/env bash
# Fails if a branch that is not a founder branch changes founder-only files.
# Usage: scripts/check-founder-files.sh <base-ref> <head-branch-name>
#   base-ref: a git ref to diff against (e.g. origin/main). Head is the current HEAD.
# Founder branches are named founder/<anything>. Every other branch (agent/..., anything else) is checked.
set -euo pipefail
BASE="${1:?base ref required}"
BRANCH="${2:?head branch name required}"

case "$BRANCH" in
  founder/*) echo "Founder branch ($BRANCH): founder-only files may change; founders review them."; exit 0;;
esac

# Founder-only paths (regex on repo-relative paths).
PATTERN='(^|/)CLAUDE(\.local)?\.md$|(^|/)\.mcp\.json$|^\.claude/|^\.github/|^scripts/check-|^scripts/gitleaks-config|^\.gitleaks\.toml$|^packages/contracts/'

# -z: NUL-separated raw paths (no quoting of unusual names); --no-renames: a rename lists both old and new paths.
# Fail closed: if the diff itself fails (bad base ref, shallow clone), stop with an error.
if ! changed=$(git -c core.quotepath=off diff -z --no-renames --name-only "$BASE...HEAD" | tr '\0' '\n'; exit "${PIPESTATUS[0]}"); then
  echo "ERROR: could not diff $BASE...HEAD"; exit 1
fi
bad=$(printf '%s\n' "$changed" | grep -E "$PATTERN" || true)
if [ -n "$bad" ]; then
  echo "Branch '$BRANCH' changes founder-only files:"
  echo "$bad"
  echo "Undo these changes and ask on the issue: REQUEST: <path> - <change> - <why>"
  exit 1
fi
echo "No founder-only files changed."
