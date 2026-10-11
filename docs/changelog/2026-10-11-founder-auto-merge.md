# 2026-10-11 - founders' auto-merge

Founder change (`CLAUDE.md`, `scripts/check-founder-merge.sh` + test, pins).

- Founders approve every merge, now also through an hourly auto-merge run from a founder's own account: a PR that is
  `ready-to-merge` (every reviewer passed, zero findings), green (`review`, `guards`, `checks` on the head commit, no red or
  running check), conflict-free and free of founder-only and `packages/contracts` files is squash-merged on its exact
  head sha. Everything else waits for a founder's click. Runbook: `docs/runbooks/founder-auto-merge.md`.
