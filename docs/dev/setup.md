# Developer setup

For engineers and builder agents. Dealers do not need this page.

## What you need

- **Node.js** in this range (set in `package.json`): `^20.19.0 || ^22.13.0 || >=24`. CI runs Node 20.
- **Corepack**, which comes with Node. It gives you the pinned **Yarn 4.18.1** (`packageManager` in `package.json`).
  Do not use a globally installed Yarn 1 for this repo.
- **gitleaks 8.18.4**, only if you want to run the secret scan on your own machine (optional). See
  [CI pipeline](../runbooks/ci-pipeline.md#secret-scan-on-your-machine).

## First-time install

1. Turn on Corepack:

   ```bash
   corepack enable
   ```

2. Check the Yarn version. It should print `4.18.1`:

   ```bash
   yarn --version
   ```

3. Install from the lockfile:

   ```bash
   yarn install --immutable
   ```

   `--immutable` fails if `yarn.lock` would change. If it does, a dependency changed without its lockfile update.
   Run `yarn install` on your branch, review the `yarn.lock` diff, and commit it with the dependency change.

4. Optional: copy the env template for local work. See [Environment variables](env-vars.md).

   ```bash
   cp .env.example .env
   ```

   `.env` is git-ignored. Nothing in the code reads it yet, so you do not need it to run the checks.

**Install scripts:** `.yarnrc.yml` sets `enableScripts: false`, so dependency install scripts do not run. A config test
in `infra/checks` (`holds exactly the allowed settings, with install scripts off`) fails if that line is removed or changed. It also fails if `preinstall`, `install`, `postinstall`, `prepare`, `prepack` or
`postpack` appears in the root or any workspace `package.json`, because `enableScripts: false` may not stop a workspace's own
scripts. A founder still has to confirm that.

## Root scripts

| Command          | What it runs                                                   | When to use it                                        |
| ---------------- | -------------------------------------------------------------- | ----------------------------------------------------- |
| `yarn lint`      | `eslint --config eslint.config.mjs .`, then `prettier --check .` | Before every push                                     |
| `yarn format`    | `prettier --write .`                                           | To fix formatting                                     |
| `yarn typecheck` | `nx run-many -t typecheck`                                     | Type check every workspace                            |
| `yarn test`      | `nx run-many -t test`                                          | Unit tests in every workspace, with the coverage gate |
| `yarn build`     | `nx run-many -t build`                                         | Compile every workspace to `dist/`                    |

Notes:

- `yarn lint` does not use Nx. It runs ESLint on the whole repo and Prettier on every file not in `.prettierignore`, including Markdown in `docs/`.
- `--config eslint.config.mjs` makes the root config the only one. ESLint ignores any other `eslint.config.*` file, and a
  config test in `infra/checks` fails if one is committed anywhere else (`src/lint-config.test.ts`).
- Lint skips only install, cache, build and Playwright output: `node_modules` (any depth), the root `.nx` and `.yarn`, each
  workspace's own `dist/` and `coverage/` in `apps/*`, `services/*`, `packages/*`, `infra/*` and `tests/*`, and the Playwright
  folders `test-results/`, `playwright-report/` and `blob-report/` at any depth. `tests/*` is reserved for the
  e2e workspace. It is not in the root `package.json` workspaces yet, so `yarn install` does not link it, but lint and the
  tracked-file check already cover it. A config test fails if git tracks any file in those folders (apart from the founder-owned
  `.yarn/releases/` and `.yarn/plugins/`), so nothing can be committed where lint does not look.
- Playwright output is never committed. Traces can hold cookies, auth headers and credit-app fields. `test-results/`,
  `playwright-report/`, `blob-report/` and `playwright/.auth/` (saved login state) are git-ignored and skipped by Prettier,
  at any depth. A config test in `infra/checks` fails if git tracks any file in one of these folders, at any depth. If one
  is already tracked, run `git rm --cached <file>` and leave it out of the commit.
- Inline `eslint-disable` comments are off (`noInlineConfig`). A rule exception goes in `eslint.config.mjs`, where review sees it.
- **The Payload data rules (`CLAUDE.md`, Payload rule 1) are not enforced by lint yet.** There is no Payload ban rule in
  this repo today. Payload is not installed (issue #5 adds it), so no code here can reach a Payload instance or its Local
  API. The ban is built in issue [#36](https://github.com/hafidimohammedamine-dotcom/dealer-platform/issues/36) as a
  type-aware rule (it flags any value whose type is the Payload instance, however it was reached), and #36 must be done
  before the PR that adds `payload` may merge. Until then, Payload rule 1 rests on the security reviewer alone.
- The other locks are planned, not built: Postgres row-level security (Payload rule 2) and the cross-dealer leak tests
  (Payload rule 3) do not exist yet. Today nothing in the repo holds dealer data, so there is nothing for them to guard.
- `eslint.config.mjs` and the root `lint` script are not founder-only files today, so an agent PR can change them and
  only review would see it. The founders track making the lint guard founder-only in issue #46.
- TypeScript casts (`x as T`, `<T>x`) are banned by `@typescript-eslint/consistent-type-assertions`. Use a type guard.
- CI runs `yarn install --immutable`, `yarn lint`, `yarn typecheck`, `yarn test`, `yarn build` and the audit as separate
  steps (`.github/workflows/ci.yml`, lines 39 to 54). Config tests in `infra/checks` check that these root scripts have
  the expected commands, that `ci.yml` runs them in that order, and that `yarn.lock` lists every workspace and no other,
  so `yarn install --immutable` does not fail on a fresh checkout.
- `yarn test` is the only test command. Coverage is part of it. There is no separate coverage script.

## What `nx run-many` does

- Runs the same target (`typecheck`, `test` or `build`) in every workspace that has that script. Workspaces live in
  `apps/*`, `services/*`, `packages/*` and `infra/*`.
- Runs dependencies first. Each of these targets depends on `^build`, so Nx builds the workspaces a project depends on
  before it type checks or tests that project.
- Caches results. If the inputs did not change, Nx replays the saved result. The `infra/checks` tests are never cached:
  they read files that are not Nx inputs.
  The inputs include the workspace's own files and these root files: `tsconfig.base.json`, `eslint.config.mjs`,
  `vitest.config.ts`, `package.json`, `yarn.lock`, `.yarnrc.yml` and `.env.example`. Changing any of them invalidates the cache for every
  workspace.
- Writes `dist/` (build) and `coverage/` (test). Both are git-ignored.
- To ignore the cache for one run, add `--skip-nx-cache`, for example `yarn build --skip-nx-cache`.

## Coverage gate

- Every workspace's `test` script runs:
  `vitest run --coverage --config ../../vitest.config.ts`. There are no exceptions.
- The shared `vitest.config.ts` sets a **90%** minimum for lines, functions, branches and statements (v8 provider).
  The minimum applies **per file** (`perFile: true`), not to the total, so one weak file cannot hide behind the others.
  Below 90% in any file, `yarn test` fails.
- Tests live in `src/**/*.test.ts`. A workspace with no test file fails the config tests in `infra/checks`.
- Each test run prints a coverage table with one row per file, fully covered files included, so the CI log shows the
  per-file numbers for every workspace.

## Pinned overrides

`package.json` has a `resolutions` entry that forces one package to a fixed version. Every entry needs a row in this
table, with the reason and the condition for removing it. To see what a row pins, run `yarn why <package>`.

| Package  | `resolutions` key   | Pinned to | Reason                  | Pulled in by | Remove when                   |
| -------- | ------------------- | --------- | ----------------------- | ------------ | ----------------------------- |
| `undici` | `undici@npm:7.29.0` | 7.29.1    | Four advisories (below) | `nx@23.3.0`  | nx depends on 7.29.1 or newer |

Advisories fixed in 7.29.1. Found with `yarn npm audit` with the pin removed:

- GHSA-3wwx-pv8p-q78v (moderate): denial of service in WebSocket `permessage-deflate` handling.
- GHSA-pmjh-fq2x-6v4x (moderate): denial of service through an orphaned response body in `RetryHandler`.
- GHSA-r53p-7pc4-xj5r (low): response splitting through the retry interceptor.
- npm advisory 1240041: denial of service through an unrequested WebSocket subprotocol.

The resolution raises the `undici` that `nx@23.3.0` pins from 7.29.0 to 7.29.1. `node-gyp` pulls in `undici` 8.11.2,
which is not affected. Re-check this row at each monthly upgrade, and remove the resolution when the condition above is met.

## Adding a new workspace

1. Copy the scripts from `services/desking/package.json`. They must include a `typecheck` script with `tsc`, a `build`
   script with `tsc`, and the `test` script above.
2. Add `tsconfig.json` and `tsconfig.build.json`. Strict mode cannot be turned off in a workspace.
3. Add at least one `src/*.test.ts` file.
4. Run `yarn test` and `yarn typecheck`. The config tests in `infra/checks` check steps 1 to 3.

## Next

- [Environment variables](env-vars.md)
- [CI pipeline](../runbooks/ci-pipeline.md), including what to do when a step fails
