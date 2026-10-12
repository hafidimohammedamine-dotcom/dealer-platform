# 2026-10-11 - the repository is public; the review team runs only for PRs from this repository

Founder change (`.github/workflows/review.yml`). GitHub Actions stopped at 12:42 UTC: a private repository on the free
plan has 2000 hosted minutes a month and the agents had used them (one manager shift is about 150 minutes; every job
then failed in two seconds with "The job was not started because recent account payments have failed or your spending
limit needs to be increased"). The founders made the repository public, which gives hosted runners without a minute cap
at no cost; the agent-runner runbook from PR #34 (runners on the founders' PCs; not in this tree yet) is the way back
to private at $0.

- `review.yml`: the `review` job runs only when the PR's head is in this repository
  (`github.event.pull_request.head.repo.full_name == github.repository`). A fork's PR must never start a Claude run:
  `pull_request_target` would hand it the founders' Claude token (inside the egress lock) and spend their usage. Agents
  and founders push branches to this repository, never from forks, so nothing of ours changes. `guards` still runs on a
  fork's PR and fails it (no pusher record, author not in `.github/accounts.txt`); CI runs without secrets.
- What a public repository shows: the code, the issues and PR comments (the agents' logs and reviews), the Actions logs.
  Secrets are never given to forks; the data in `fixtures/` is fake; there are no real customer records in the repo.
