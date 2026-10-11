# 2026-10-11 - the heartbeat accepts founder-dispatched hourly runs

Founder change (`main-guard.yml`, `scripts/check-main-push.sh`, `scripts/check-github-lib.sh`, pins).

- GitHub's `schedule` trigger fired once in 6 hours after PR #30 merged (cron delays and drops, GitHub community
  discussion #207346). The heartbeat required a scheduled run within 75 minutes, so every Claude job stopped.
- `main-guard.yml`: `accept_sha` is optional; a founder's Run workflow with it empty runs the hourly check
  (`check-main-push.sh heartbeat <actor-id> -`: founder check, then the schedule path). A run dispatched by any other
  account fails and never counts.
- `main_guard_heartbeat` counts `schedule` and `workflow_dispatch` runs that completed with success (push runs still
  do not count).
- New runbook `docs/runbooks/founder-pc-dispatch.md`: the founder PC's scheduled tasks that dispatch the main guard every
  30 minutes and the agent workflows at their times.
