# Developer setup

For engineers and builder agents. Dealers do not need this page.

## What you need

- **Node.js** in this range (set in `package.json`): `^20.19.0 || ^22.13.0 || >=24`. CI runs Node 20.
- **Corepack**, which comes with Node. It gives you the pinned **Yarn 4.18.1** (`packageManager` in `package.json`).
  Do not use a globally installed Yarn 1 for this repo.
- **Docker**, only if you want to run the secret scan the same way CI does (optional).

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

**Install scripts:** the intended setting is `enableScripts: false` in `.yarnrc.yml`, so dependency install scripts do not
run. A founder still has to add that line. Until it is in the file, install scripts do run.

## Root scripts

| Command              | What it runs                                  | When to use it                                      |
| -------------------- | --------------------------------------------- | --------------------------------------------------- |
| `yarn lint`          | `eslint .`, then `prettier --check .`         | Before every push                                   |
| `yarn format`        | `prettier --write .`                          | To fix formatting                                   |
| `yarn typecheck`     | `nx run-many -t typecheck`                    | Type check every workspace                          |
| `yarn test`          | `nx run-many -t test`                         | Unit tests in every workspace, with the coverage gate |
| `yarn test:coverage` | Same as `yarn test`                           | Same thing, kept as an alias                        |
| `yarn build`         | `nx run-many -t build`                        | Compile every workspace to `dist/`                  |

Notes:

- `yarn lint` does not use Nx. It runs ESLint on the whole repo and Prettier on every file, including Markdown in `docs/`.
- ESLint also fails on direct Payload data calls (`payload.find`, `payload.create`, and so on) outside `packages/data`.
  All data access goes through `packages/data`.

## What `nx run-many` does

- Runs the same target (`typecheck`, `test` or `build`) in every workspace that has that script. Workspaces live in
  `apps/*`, `services/*`, `packages/*` and `infra/*`.
- Runs dependencies first. Each of these targets depends on `^build`, so Nx builds the workspaces a project depends on
  before it type checks or tests that project.
- Caches results. If the inputs did not change, Nx replays the saved result.
  The inputs include the workspace's own files and these root files: `tsconfig.base.json`, `eslint.config.mjs`,
  `vitest.config.ts`, `package.json`, `yarn.lock`, `.yarnrc.yml` and `.env.example`. Changing any of them invalidates
  the cache for every workspace.
- Writes `dist/` (build) and `coverage/` (test). Both are git-ignored.
- To ignore the cache for one run, add `--skip-nx-cache`, for example `yarn build --skip-nx-cache`.

## Coverage gate

- Every workspace's `test` script runs:
  `vitest run --coverage --config ../../vitest.config.ts`
- The shared `vitest.config.ts` sets a **90%** minimum for lines, functions, branches and statements (v8 provider).
  Below 90%, `yarn test` fails.
- Tests live in `src/**/*.test.ts`. A workspace with no test file fails the config tests in `infra/checks`.

## Adding a new workspace

1. Copy the scripts from `services/desking/package.json`. They must include a `typecheck` script with `tsc`, a `build`
   script with `tsc`, and the `test` script above.
2. Add `tsconfig.json` and `tsconfig.build.json`. Strict mode cannot be turned off in a workspace.
3. Add at least one `src/*.test.ts` file.
4. Run `yarn test` and `yarn typecheck`. The config tests in `infra/checks` check steps 1 to 3.

## Next

- [Environment variables](env-vars.md)
- [CI pipeline](../runbooks/ci-pipeline.md), including what to do when a step fails
