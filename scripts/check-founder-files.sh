#!/usr/bin/env bash
# Fails if a pull request from someone who is not a founder changes founder-only files.
# Usage: scripts/check-founder-files.sh <base-ref> <head-ref> <user-ids> <accounts-file> <pushers-file>
#   base-ref / head-ref: git refs to compare (merge-base of base and head .. head).
#   user-ids: comma-separated numeric GitHub user IDs taken from the pull_request event, not from anything the PR controls:
#             the PR author and the account that triggered this run (opened it or pushed the latest commits).
#             Founder-only files may change only if EVERY one of them is a founder. IDs, not logins: a login can be
#             renamed and re-registered.
#   accounts-file: .github/accounts.txt read from the base branch (scripts/check-accounts-lib.sh).
#   pushers-file: the output of `scripts/check-pushers.sh verify` ("<sha> <id> <role>" per commit of the PR). When founder-only
#             files change, every commit must have been pushed by a founder, so an agent's push onto a founder's branch
#             cannot ride along under the founder's next push.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/check-accounts-lib.sh
. "$HERE/check-accounts-lib.sh"
BASE="${1:?base ref}"; HEAD="${2:?head ref}"; IDS="${3:?user ids}"; ACCOUNTS="${4:?accounts file}"; PUSHERS="${5:?pushers file}"

rows=$(accounts_rows "$ACCOUNTS") || { echo "$rows"; exit 1; }
founders=$(awk '$3 == "founder" {print $1}' <<<"$rows")
all_founders=1
IFS=',' read -r -a who <<< "$IDS"
[ "${#who[@]}" -gt 0 ] || all_founders=0
[[ "$IDS" =~ (^|,)(,|$) ]] && all_founders=0   # an empty ID never counts as a founder
for i in "${who[@]}"; do
  [[ "$i" =~ ^[0-9]+$ ]] && grep -qxF -- "$i" <<<"$founders" || all_founders=0
done
# Commits pushed by someone else (the pusher ledger): founder-only changes need every commit pushed by a founder.
[ -f "$PUSHERS" ] || { echo "ERROR: pushers file not found: $PUSHERS"; exit 1; }
not_founder_pushes=$(awk 'NF != 3 || $3 != "founder" {print}' "$PUSHERS")
if [ "$all_founders" = 1 ] && [ -z "$not_founder_pushes" ]; then
  echo "All of '$IDS' are founders (and every commit was pushed by a founder): founder-only files may change; founders review them."
  exit 0
fi

# Founder-only paths (regex on repo-relative paths), at any depth where it matters.
PATTERN='(^|/)CLAUDE(\.local)?\.md$|(^|/)\.mcp\.json$|(^|/)\.claude/|^\.github/|^scripts/check-|^scripts/gitleaks-config|(^|/)\.gitleaks(\.toml|ignore)$|^packages/data/override-allowlist\.txt$|(^|/)\.yarnrc\.yml$|(^|/)\.yarn/|(^|/)\.gitattributes$'

# -z: raw paths (no quoting); --no-renames: a rename lists both old and new paths. Fail closed if git fails.
if ! changed=$(git -c core.quotepath=off diff -z --no-renames --name-only "$BASE...$HEAD" | tr '\0' '\n'; exit "${PIPESTATUS[0]}"); then
  echo "ERROR: could not diff $BASE...$HEAD"; exit 1
fi
bad=$(printf '%s\n' "$changed" | grep -E "$PATTERN" || true)
if [ -n "$bad" ]; then
  if [ "$all_founders" = 1 ]; then
    echo "Commits not pushed by a founder (sha, pusher ID, role; '-' = no pusher record), and the PR changes founder-only files:"
    echo "$not_founder_pushes"
    echo "A founder re-creates those changes in commits of their own (rebase them out and push again); unrecorded commits were pushed before the ledger existed or lost their record."
  else
    echo "Not all of '$IDS' are founders, and the PR changes founder-only files:"
  fi
  echo "$bad"
  [ "$all_founders" = 1 ] || echo "Undo these changes and ask on the issue: REQUEST: <path> - <change> - <why>"
  exit 1
fi
echo "No founder-only files changed."
