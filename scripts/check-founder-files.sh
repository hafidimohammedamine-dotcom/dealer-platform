#!/usr/bin/env bash
# Fails if a pull request from someone who is not a founder changes founder-only files.
# Usage: scripts/check-founder-files.sh <base-ref> <head-ref> <logins> <founders-file>
#   base-ref / head-ref: git refs to compare (merge-base of base and head .. head).
#   logins: comma-separated GitHub logins taken from the pull_request event, not from anything the PR controls:
#           the PR author and the account that triggered this run (opened it or pushed the latest commits).
#           Founder-only files may change only if EVERY one of them is a founder.
#   founders-file: list of founder GitHub logins, one per line (read from the base branch).
set -euo pipefail
BASE="${1:?base ref}"; HEAD="${2:?head ref}"; LOGINS="${3:?logins}"; FOUNDERS="${4:?founders file}"

[ -f "$FOUNDERS" ] || { echo "ERROR: founders file not found: $FOUNDERS"; exit 1; }
founders=$(sed -e 's/#.*//' -e 's/[[:space:]]//g' "$FOUNDERS" | sed '/^$/d')
all_founders=1; AUTHOR="$LOGINS"
IFS=',' read -r -a who <<< "$LOGINS"
[ "${#who[@]}" -gt 0 ] || all_founders=0
[[ "$LOGINS" =~ (^|,)(,|$) ]] && all_founders=0   # an empty login never counts as a founder
for l in "${who[@]}"; do
  [ -n "$l" ] && grep -qxF -- "$l" <<<"$founders" || all_founders=0
done
if [ "$all_founders" = 1 ]; then
  echo "All of '$LOGINS' are founders: founder-only files may change; founders review them."
  exit 0
fi

# Founder-only paths (regex on repo-relative paths), at any depth where it matters.
PATTERN='(^|/)CLAUDE(\.local)?\.md$|(^|/)\.mcp\.json$|(^|/)\.claude/|^\.github/|^scripts/check-|^scripts/gitleaks-config|(^|/)\.gitleaks(\.toml|ignore)$'

# -z: raw paths (no quoting); --no-renames: a rename lists both old and new paths. Fail closed if git fails.
if ! changed=$(git -c core.quotepath=off diff -z --no-renames --name-only "$BASE...$HEAD" | tr '\0' '\n'; exit "${PIPESTATUS[0]}"); then
  echo "ERROR: could not diff $BASE...$HEAD"; exit 1
fi
bad=$(printf '%s\n' "$changed" | grep -E "$PATTERN" || true)
if [ -n "$bad" ]; then
  echo "Not all of '$AUTHOR' are founders, and the PR changes founder-only files:"
  echo "$bad"
  echo "Undo these changes and ask on the issue: REQUEST: <path> - <change> - <why>"
  exit 1
fi
echo "No founder-only files changed."
