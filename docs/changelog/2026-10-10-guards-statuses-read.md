# 2026-10-10 - guards reads the pusher ledger (statuses: read)

Founder change (`.github/workflows/guards.yml`, `scripts/check-workflows-policy.json`, pins).

- The `guards` job's token had only `contents: read`, so reading the `guards/pusher` commit statuses written by
  `pusher-ledger.yml` failed with HTTP 403 ("could not read the statuses ... re-run the job") on every PR after
  PR #30 merged. The job now also has `statuses: read`.
- The workflow checker allows `statuses` in `guards.yml` (read only: `guards.yml` joins `read_only_workflows`, so
  a write scope there fails the checker). Two test cases added in `scripts/check-workflows.test.sh`.
