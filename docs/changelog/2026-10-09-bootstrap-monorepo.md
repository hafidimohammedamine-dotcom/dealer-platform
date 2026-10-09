# 2026-10-09 - Monorepo bootstrap docs (#4)

- **Developer setup** (`docs/dev/setup.md`): Node range, Corepack and Yarn 4.18.1, `yarn install --immutable`, each root
  script, what `nx run-many` does, the 90% coverage gate, and how to add a workspace.
- **Environment variables** (`docs/dev/env-vars.md`): all 26 variables in `.env.example`, which are secrets, the three
  Postgres roles, `PAYLOAD_SECRET` rotation and the `FIELD_ENCRYPTION_KEY` backup. All 26 are reserved: nothing reads
  `process.env` yet.
- **CI runbook** (`docs/runbooks/ci-pipeline.md`): the step order in `ci.yml`, and what to do when lint, types, tests,
  audit, build or the secret scan fails.
- **Key runbook** (`docs/runbooks/key-leak-or-loss.md`): detect, rotate, re-encrypt, sign out and tell people, for a
  leaked or lost `PAYLOAD_SECRET` or `FIELD_ENCRYPTION_KEY`. Re-encryption and key backup checks are not built yet.
