# 2026-10-09 - Monorepo bootstrap docs (#4)

- **Developer setup** (`docs/dev/setup.md`): Node range, Corepack and Yarn 4.18.1, `yarn install --immutable`, install
  scripts off (`enableScripts: false`), each root script, what `nx run-many` does, the 90% coverage gate, a table of
  pinned `resolutions`, and how to add a workspace.
- **Environment variables** (`docs/dev/env-vars.md`): all 26 variables in `.env.example`, which are secrets, the three
  Postgres roles, `PAYLOAD_SECRET` rotation and the `FIELD_ENCRYPTION_KEY` backup. All 26 are reserved: nothing reads
  `process.env` yet.
- **CI runbook** (`docs/runbooks/ci-pipeline.md`): the step order in `ci.yml` (guard script tests, the full-history secret
  scan on pushes to `main`, build before the dependency audit), the local secret scan command, and what to do when a
  step fails. The pull request's own secret scan is in `guards.yml`.
- **Lint and test commands:** the Payload lint rules are stronger. Outside `packages/data`, the Payload instance and
  database drivers are off limits, `overrideAccess` must be `false` everywhere, and inline lint disable comments are
  turned off. A duplicate test script alias is removed; `yarn test` is the only test command.
- **Key runbook** (`docs/runbooks/key-leak-or-loss.md`): detect, rotate, re-encrypt, sign out and tell people, for a
  leaked or lost `PAYLOAD_SECRET` or `FIELD_ENCRYPTION_KEY`. Re-encryption and key backup checks are not built yet.
