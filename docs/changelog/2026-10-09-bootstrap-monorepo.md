# 2026-10-09 - Monorepo bootstrap (#4)

- **Monorepo:** Yarn 4.18.1 workspaces and Nx, with TypeScript strict, ESLint, Prettier and Vitest. There is one
  placeholder package per folder in `CLAUDE.md`, `packages/contracts` (`@dealer/contracts`) included. Each one has a
  test. The root scripts are `yarn lint`, `yarn typecheck`, `yarn test` (with a 90% coverage gate) and `yarn build`.
- **Install safety:** dependency install scripts are off (`enableScripts: false`). A config test parses `.yarnrc.yml`.
  It requires two settings, `nodeLinker: node-modules` and `enableScripts: false`, and allows one optional setting,
  `enableTelemetry: false`. It also allows `dependenciesMeta` entries shaped exactly `{ built: true }` on exact versions
  (a founder allows a package's build script one by one).
- **Lint:** `yarn lint` runs `eslint --config eslint.config.mjs .`, so the root config is the only one. Inline disable
  comments do not work, and TypeScript `as` casts are banned. Lint ignores only install, cache and build output
  (`node_modules`, the root `.nx` and `.yarn`, `<workspace>/dist`, `<workspace>/coverage`), and a config test fails if git tracks a
  file in those folders or an ESLint config outside the root. There is no Payload ban rule yet: Payload is not
  installed, and the type-aware ban is issue #36, which must be done before the PR that adds `payload` merges.
- **Coverage:** the 90% gate is checked per file, and each test run prints a per-file coverage table. The
  `infra/checks` tests are never cached by Nx, because they read files outside the Nx inputs.
- **Env template values:** each value in `.env.example` is empty or exactly its reviewed placeholder.
- **Developer setup** (`docs/dev/setup.md`): Node range, Corepack, `yarn install --immutable`, each root script, what
  `nx run-many` does, what lint does and does not enforce yet, a table of pinned `resolutions`, and how to add a workspace.
- **Environment variables** (`docs/dev/env-vars.md`): all 26 variables in `.env.example`, which are secrets, the three
  Postgres roles, `PAYLOAD_SECRET` rotation and the `FIELD_ENCRYPTION_KEY` backup. All 26 are reserved: no code reads
  any of the 26 listed variables yet.
- **CI runbook** (`docs/runbooks/ci-pipeline.md`): the steps of `ci.yml` (the full-history
  secret scan on pushes to `main`, then the guard script tests, and build before the dependency audit), the local secret scan command, and what to do
  when a step fails. The pull request's own secret scan is in `guards.yml`.
- **Key runbook** (`docs/runbooks/key-leak-or-loss.md`): detect, rotate, re-encrypt, sign out and tell people, for a
  leaked or lost `PAYLOAD_SECRET` or `FIELD_ENCRYPTION_KEY`. The legal notice clocks may start on the day of discovery (lawyer to confirm). Re-encryption
  and key backup checks are not built yet.
