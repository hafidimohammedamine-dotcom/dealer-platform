# 2026-10-09 - Monorepo bootstrap (#4)

- **Monorepo:** Yarn 4.18.1 workspaces and Nx, with TypeScript strict, ESLint, Prettier and Vitest. There is one
  placeholder package per folder in `CLAUDE.md`, `packages/contracts` (`@dealer/contracts`) included. Each one has a
  test. The root scripts are `yarn lint`, `yarn typecheck`, `yarn test` (with a 90% coverage gate) and `yarn build`.
- **Install safety:** dependency install scripts are off (`enableScripts: false`). A config test parses `.yarnrc.yml`.
  It requires two settings, `nodeLinker: node-modules` and `enableScripts: false`, and allows one optional setting,
  `enableTelemetry: false`.
- **Payload lint rules** (`eslint.payload-ban.mjs`): outside `packages/data`, nothing may name or import the Payload
  instance, and database clients may not be imported (no reviewed exception yet). `overrideAccess` is only
  ever `false`, except in a system job listed in `packages/data/override-allowlist.txt` (empty for now), and Local API calls in `packages/data` must set `overrideAccess`, `depth` and `versions`, and pass `user` or `req`. `showHiddenFields` may only be `false`. Inline disable
  comments do not work. TypeScript `as` casts are banned.
- **Developer setup** (`docs/dev/setup.md`): Node range, Corepack, `yarn install --immutable`, each root script, what
  `nx run-many` does, the lint rules and their limits, a table of pinned `resolutions`, and how to add a workspace.
- **Environment variables** (`docs/dev/env-vars.md`): all 26 variables in `.env.example`, which are secrets, the three
  Postgres roles, `PAYLOAD_SECRET` rotation and the `FIELD_ENCRYPTION_KEY` backup. All 26 are reserved: no code reads
  any of the 26 listed variables yet.
- **CI runbook** (`docs/runbooks/ci-pipeline.md`): the step order in `ci.yml` (guard script tests, the full-history
  secret scan on pushes to `main`, build before the dependency audit), the local secret scan command, and what to do
  when a step fails. The pull request's own secret scan is in `guards.yml`.
- **Key runbook** (`docs/runbooks/key-leak-or-loss.md`): detect, rotate, re-encrypt, sign out and tell people, for a
  leaked or lost `PAYLOAD_SECRET` or `FIELD_ENCRYPTION_KEY`. The legal notice clocks may start on the day of discovery (lawyer to confirm). Re-encryption
  and key backup checks are not built yet.
