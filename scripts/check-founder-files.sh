#!/usr/bin/env bash
# Fails if a pull request from someone who is not a founder changes founder-only files.
# Usage: scripts/check-founder-files.sh <base-ref> <head-ref> <pr-author-login> <founders-file>
#   base-ref / head-ref: git refs to compare (merge-base of base and head .. head).
#   pr-author-login: GitHub login of the PR author, taken from the pull_request event (not from anything the PR controls).
#   founders-file: list of founder GitHub logins, one per line (read from the base branch).
set -euo pipefail
BASE="${1:?base ref}"; HEAD="${2:?head ref}"; AUTHOR="${3:?pr author}"; FOUNDERS="${4:?founders file}"

[ -f "$FOUNDERS" ] || { echo "ERROR: founders file not found: $FOUNDERS"; exit 1; }
if grep -qxF -- "$AUTHOR" <(sed -e 's/#.*//' -e 's/[[:space:]]//g' "$FOUNDERS" | sed '/^$/d'); then
  echo "PR author '$AUTHOR' is a founder: founder-only files may change; founders review them."
  exit 0
fi

# Founder-only paths (regex on repo-relative paths), at any depth where it matters.
PATTERN='(^|/)CLAUDE(\.local)?\.md$|(^|/)\.mcp\.json$|(^|/)\.claude/|^\.github/|^scripts/check-|^scripts/gitleaks-config|(^|/)\.gitleaks(\.toml|ignore)$|^packages/contracts/'

# -z: raw paths (no quoting); --no-renames: a rename lists both old and new paths. Fail closed if git fails.
if ! changed=$(git -c core.quotepath=off diff -z --no-renames --name-only "$BASE...$HEAD" | tr '\0' '\n'; exit "${PIPESTATUS[0]}"); then
  echo "ERROR: could not diff $BASE...$HEAD"; exit 1
fi
bad=$(printf '%s\n' "$changed" | grep -E "$PATTERN" || true)
if [ -n "$bad" ]; then
  echo "PR author '$AUTHOR' is not a founder and changes founder-only files:"
  echo "$bad"
  echo "Undo these changes and ask on the issue: REQUEST: <path> - <change> - <why>"
  exit 1
fi
echo "No founder-only files changed."
