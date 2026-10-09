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
in `infra/checks` (`keeps dependency install scripts off`) fails if that line is removed or changed.

## Root scripts

| Command          | What it runs                          | When to use it                                        |
| ---------------- | ------------------------------------- | ----------------------------------------------------- |
| `yarn lint`      | `eslint .`, then `prettier --check .` | Before every push                                     |
| `yarn format`    | `prettier --write .`                  | To fix formatting                                     |
| `yarn typecheck` | `nx run-many -t typecheck`            | Type check every workspace                            |
| `yarn test`      | `nx run-many -t test`                 | Unit tests in every workspace, with the coverage gate |
| `yarn build`     | `nx run-many -t build`                | Compile every workspace to `dist/`                    |

Notes:

- `yarn lint` does not use Nx. It runs ESLint on the whole repo and Prettier on every file, including Markdown in `docs/`.
- ESLint also enforces the Payload data rules, in `eslint.payload-ban.mjs`. All data access goes through `packages/data`.
  - Outside `packages/data`, code may not use the Payload instance, except for its `logger`. The check fails closed.
  - `overrideAccess` must be the literal `false`, in every file, including `packages/data`. The allow-list is empty.
  - Database drivers and Payload database adapters (`pg`, `drizzle-orm`, `@payloadcms/db-postgres`, `@payloadcms/drizzle`)
    may be imported only in `packages/data`.
  - Inline `eslint-disable` comments are off, so a file cannot switch these rules off.
- `yarn test` is the only test command. Coverage is part of it. There is no separate coverage script.

## What `nx run-many` does

- Runs the same target (`typecheck`, `test` or `build`) in every workspace that has that script. Workspaces live in
  `apps/*`, `services/*`, `packages/*` and `infra/*`.
- Runs dependencies first. Each of these targets depends on `^build`, so Nx builds the workspaces a project depends on
  before it type checks or tests that project.
- Caches results. If the inputs did not change, Nx replays the saved result.
  The inputs include the workspace's own files and these root files: `tsconfig.base.json`, `eslint.config.mjs`,
  `eslint.payload-ban.mjs` (the Payload ban rule file that `eslint.config.mjs` imports), `vitest.config.ts`,
  `package.json`, `yarn.lock`, `.yarnrc.yml` and `.env.example`. Changing any of them invalidates the cache for every
  workspace.
- Writes `dist/` (build) and `coverage/` (test). Both are git-ignored.
- To ignore the cache for one run, add `--skip-nx-cache`, for example `yarn build --skip-nx-cache`.

## Coverage gate

- Every workspace's `test` script runs:
  `vitest run --coverage --config ../../vitest.config.ts`
- The shared `vitest.config.ts` sets a **90%** minimum for lines, functions, branches and statements (v8 provider).
  Below 90%, `yarn test` fails.
- Tests live in `src/**/*.test.ts`. A workspace with no test file fails the config tests in `infra/checks`.

## Pinned overrides

`package.json` has a `resolutions` entry that forces one package to a fixed version. Every entry needs a row in this
table, with the reason and the condition for removing it. To see what a row pins, run `yarn why <package>`.

| Package                                              | Pinned version | Reason or advisory   | Parent package                                | Remove when          |
| ---------------------------------------------------- | -------------- | -------------------- | --------------------------------------------- | -------------------- |
| `undici` (`resolutions` key `undici@npm:7.29.0`) | 7.29.1 | Fixes four advisories, see below | `nx@23.3.0`, which pins `undici` 7.29.0 | When nx ships a version that depends on `undici` 7.29.1 or newer |

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
