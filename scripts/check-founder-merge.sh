#!/usr/bin/env bash
# The founders' auto-merge (founder-owned, pinned): merges every pull request that the review team and CI have fully
# cleared, so that founders click only on the changes that are theirs. Run hourly from a founder's own account (the main
# guard undoes a merge by anyone else), never from an agent job.
# Usage: scripts/check-founder-merge.sh [--dry-run]          (env: GH_TOKEN of a founder, GH_REPO=<owner>/<repo>, GH=<gh binary>)
# A pull request is merged only if ALL of these hold, read from the GitHub API, never from the PR's own text:
#   - open, not a draft, from a branch of this repository (no forks), label `ready-to-merge` (set by check-review-post.sh
#     only when every reviewer passed with zero findings), no label `blocked`, `changes-requested` or `escalated`;
#   - GitHub reports it mergeable and `mergeable_state` is `clean` (no conflict, nothing pending);
#   - on the head commit, the check runs `review`, `guards` and `checks` all completed with success, and no check run is
#     failing or still running (a stale label after a new push is caught here: that push's own review is not done);
#   - it changes no founder-only file (the pattern of scripts/check-founder-files.sh) and nothing under packages/contracts/
#     (CODEOWNERS: a founder approves every contracts change). Those PRs are listed as "needs a founder".
# Squash-merges with the PR title as the commit title and deletes the branch. Prints one line per open PR. Exit 1 only on
# an API error (nothing is merged on doubt).
set -euo pipefail
GH="${GH:-gh}"; REPO="${GH_REPO:?GH_REPO=<owner>/<repo>}"
DRY=0; [ "${1:-}" = --dry-run ] && DRY=1
FOUNDER_PATTERN='(^|/)CLAUDE(\.local)?\.md$|(^|/)\.mcp\.json$|(^|/)\.claude/|^\.github/|^scripts/check-|^scripts/gitleaks-config|(^|/)\.gitleaks(\.toml|ignore)$|^packages/data/override-allowlist\.txt$|(^|/)\.yarnrc\.yml$|(^|/)\.yarn/|(^|/)\.gitattributes$|^packages/contracts/'
REQUIRED_CHECKS="review guards checks"

api() { "$GH" api "$@"; }

prs=$(api --paginate "repos/$REPO/pulls?state=open&per_page=100" --jq '.[] | "\(.number)"') || { echo "ERROR: could not list the open pull requests."; exit 1; }
[ -n "$prs" ] || { echo "No open pull requests."; exit 0; }
merged=0
for n in $prs; do
  # One field per line (a PR title holds no newline); empty fields become "-" so nothing shifts.
  pr=$(api "repos/$REPO/pulls/$n" --jq '[.draft, .mergeable, .mergeable_state, .head.sha, (.head.repo.full_name // "-"), ([.labels[].name] | join(",")), .title] | map(tostring | if . == "" then "-" else . end) | .[]') \
    || { echo "ERROR: could not read pull request #$n."; exit 1; }
  { read -r draft; read -r mergeable; read -r mstate; read -r head; read -r headrepo; read -r labels; read -r title; } <<<"$pr"
  [ "$labels" != - ] || labels=""
  has() { [[ ",$labels," == *",$1,"* ]]; }
  if [ "$draft" = true ]; then echo "#$n: draft"; continue; fi
  if [ "$headrepo" != "$REPO" ]; then echo "#$n: head is not a branch of this repository ($headrepo)"; continue; fi
  if ! has ready-to-merge; then echo "#$n: not ready-to-merge (labels: ${labels:-none})"; continue; fi
  for bad in blocked changes-requested escalated; do has "$bad" && { echo "#$n: label $bad"; continue 2; }; done
  if [ "$mergeable" != true ] || [ "$mstate" != clean ]; then echo "#$n: not mergeable (mergeable=$mergeable state=$mstate)"; continue; fi
  checks=$(api --paginate "repos/$REPO/commits/$head/check-runs?per_page=100" --jq '.check_runs[] | "\(.name) \(.status) \(.conclusion // "-")"') \
    || { echo "ERROR: could not read the check runs of #$n."; exit 1; }
  ok=1; why=""
  for c in $REQUIRED_CHECKS; do
    grep -qE "^$c completed success$" <<<"$checks" || { ok=0; why="check '$c' has not passed on $head"; break; }
  done
  if [ "$ok" = 1 ] && bad_run=$(grep -vE ' completed (success|skipped|neutral)$' <<<"$checks" | head -1) && [ -n "$bad_run" ]; then ok=0; why="check run not green: $bad_run"; fi
  if [ "$ok" != 1 ]; then echo "#$n: $why"; continue; fi
  files=$(api --paginate "repos/$REPO/pulls/$n/files?per_page=100" --jq '.[] | .filename, (.previous_filename // empty)') \
    || { echo "ERROR: could not list the files of #$n."; exit 1; }
  if founder=$(grep -E "$FOUNDER_PATTERN" <<<"$files") && [ -n "$founder" ]; then
    echo "#$n: needs a founder (founder-only or contracts files: $(tr '\n' ' ' <<<"$founder"))"; continue
  fi
  if [ "$DRY" = 1 ]; then echo "#$n: would merge (dry run): $title"; continue; fi
  api -X PUT "repos/$REPO/pulls/$n/merge" -f merge_method=squash -f sha="$head" -f commit_title="$title (#$n)" >/dev/null \
    || { echo "ERROR: merging #$n failed (GitHub refused; nothing else was merged)."; exit 1; }
  api -X DELETE "repos/$REPO/git/refs/heads/$(api "repos/$REPO/pulls/$n" --jq .head.ref)" >/dev/null 2>&1 || true
  echo "#$n: merged (squash, $head): $title"; merged=$((merged+1))
done
echo "Merged $merged pull request(s)."
