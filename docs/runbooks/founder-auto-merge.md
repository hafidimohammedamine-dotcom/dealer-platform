# Founders' auto-merge

`scripts/check-founder-merge.sh` (founder-owned, pinned) merges the pull requests that are fully cleared, so founders
click only on the changes that are theirs. It runs every hour as a scheduled task on a founder's Claude account (the
merge is made by the founder's GitHub login: the main guard undoes a merge by anyone else). Never run it from an agent
job or with the agents' token.

A PR is merged only when all of these hold (read from the GitHub API, never from the PR's text):

- open, not a draft, head branch in this repository (no forks);
- label `ready-to-merge` (set by `scripts/check-review-post.sh` only when every reviewer passed with zero findings), and
  none of `blocked`, `changes-requested`, `escalated`;
- GitHub says mergeable with `mergeable_state: clean` (no conflict, nothing pending);
- on the head commit the check runs `review`, `guards` and `checks` completed with success, and no check run is red or
  still running (a label left over from an earlier push is caught here: the new push's review is not done);
- no changed or renamed file matches the founder-only pattern of `scripts/check-founder-files.sh` or `packages/contracts/`
  (CODEOWNERS). Those PRs print `needs a founder (...)` and wait for a founder's click.

It squash-merges on the exact head sha it checked (`sha=` in the merge call: a push in between makes GitHub refuse),
with `<PR title> (#<n>)` as the commit title, deletes the branch, and prints one line per open PR plus `Merged N pull
request(s).` `--dry-run` prints `would merge` instead. It exits 1 only on an API error; nothing is merged on doubt.

Run by hand (a founder's `gh` login): `GH_REPO=hafidimohammedamine-dotcom/dealer-platform bash scripts/check-founder-merge.sh --dry-run`.

Tests: `scripts/check-founder-merge.test.sh` (stub `gh`; every skip reason, the founder-only paths, API errors, the
merge call's sha and title).
