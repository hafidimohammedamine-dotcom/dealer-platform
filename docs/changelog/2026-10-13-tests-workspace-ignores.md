# 2026-10-13 - tests/* workspace and Playwright output ignores

- **Lint** (`eslint.config.mjs`): also skips `dist/` and `coverage/` in `tests/*`, and the Playwright folders
  `test-results/`, `playwright-report/` and `blob-report/` at any depth. `tests/*` is reserved for the e2e
  workspace. It is not yet in the root `package.json` workspaces.
- **Tracked-file check** (`infra/checks/src/checks.ts`, `trackedFileProblems`): fails on any tracked file under `tests/*/dist`,
  `tests/*/coverage`, or any tracked file under `test-results/`, `playwright-report/` or `blob-report/` at any depth. It also
  fails on any tracked file under a `.auth` folder, any `*.har`, any `trace.zip` and any `storageState` / `storage-state`
  JSON file (`/storage-?state[^/]*\.json$/i`), at any depth, wherever Playwright is told to write them. Traces can hold
  cookies, auth headers and credit-app fields. Messages: `committed in a folder lint skips` (Playwright output) and
  `saved Playwright login state, HAR or trace must not be committed` (the rest).
- **`.gitignore`**: `test-results/`, `playwright-report/`, `blob-report/`, `**/.auth/`, `*.har` and `**/trace.zip`, with a comment on why.
- **`.prettierignore`**: `test-results`, `playwright-report`, `blob-report`, `**/.auth`, `*.har` and `**/trace.zip`. `dist` and `coverage` already
  skip the `tests/*` build folders at any depth.
- **Tests** (`infra/checks`): lint ignores and non-ignored source files under `tests/*`, the tracked-file rules, and the
  `.gitignore` and `.prettierignore` entries.
- **Docs**: `docs/dev/setup.md` describes the lint ignores, the `tests/*` reservation and the Playwright output rules.
  `docs/runbooks/ci-pipeline.md` ("Tests fail") lists the two failure messages and the fix (`git rm --cached`).
