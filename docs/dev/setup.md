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

| Command          | What it runs                          | When to use it                                        |
| ---------------- | ------------------------------------- | ----------------------------------------------------- |
| `yarn lint`      | `eslint .`, then `prettier --check .` | Before every push                                     |
| `yarn format`    | `prettier --write .`                  | To fix formatting                                     |
| `yarn typecheck` | `nx run-many -t typecheck`            | Type check every workspace                            |
| `yarn test`      | `nx run-many -t test`                 | Unit tests in every workspace, with the coverage gate |
| `yarn build`     | `nx run-many -t build`                | Compile every workspace to `dist/`                    |

Notes:

- `yarn lint` does not use Nx. It runs ESLint on the whole repo and Prettier on every file not in `.prettierignore`, including Markdown in `docs/`.
- ESLint also enforces the Payload data rules. All data access goes through `packages/data`. `eslint.payload-ban.mjs`
  wires them up; the rules are in `eslint-rules/`, and the reviewed allow-lists in `eslint-rules/payload-lists.mjs`. The system-job allow-list is a separate file,
  `packages/data/override-allowlist.txt`.
  The rules ban where the Payload instance comes from and every name it goes by, instead of listing bad uses. Expect
  false positives; rename the value or ask security to review an allow-list entry.
  - `local/no-payload-instance-access`, outside `packages/data`: no identifier, object key, string, JSX prop or type named
    `payload`, `getPayload…`, `Payload` or `BasePayload`. The one exception is `payload.logger` / `req.payload.logger`.
    `Reflect` is banned. A computed read whose key is not a fixed string (`obj[key]`, or `const p = req[k]`) is flagged in
    any use. Plain writes (`obj[k] = 1`) and `delete obj[k]` are not. `Object.values`, `entries`, `assign`,
    `getOwnPropertyDescriptor(s)` and `getOwnPropertyNames` are banned, and so is any use of `Object` other than
    `Object.<fixed name>`.
    A webhook body with a field of that name (Telnyx sends `data.payload`) needs a reviewed entry in
    `payloadNameAllowedPaths`.
  - `local/no-restricted-modules`, outside `packages/data`: only type imports from `payload`. No database client at all
    (`pg` and `pg-*`, `postgres`, `kysely`, `knex`, `drizzle-orm`, `drizzle-kit`, Prisma, Neon, `@vercel/postgres`,
    `node:sqlite`, every `@payloadcms/db-*` adapter and more). The reviewed exception list is empty, so no file outside
    `packages/data` may import one yet. A separate rule stops code outside `services/desking/` from importing
    `services/desking/src/db/`. `import()` and `require()` take fixed names only.
  - `local/no-override-access`, in every file: `overrideAccess` is only the literal `false`, except in a system job
    listed in `packages/data/override-allowlist.txt`. That file is created by founder PR #43, is founder-only and is
    empty, so no file may use `true` yet. It is not in the branch that adds this page; it reaches `main` only when
    PR #43 merges. The rule reads it as exact repo-relative paths, one per line. `#` comment lines and blank lines are
    skipped. No globs, no trailing comments, no `..` and no leading `/`. A missing file counts as an empty list. A
    malformed line, or a listed file that does not exist, breaks lint when the config loads. An unlisted file that uses
    `true` fails lint. In `packages/data`, every Local API call passes one object literal with `overrideAccess: false`,
    `depth` and `versions`, plus `user` or `req` (a `null` or `undefined` value does not count), with no spreads and no
    computed keys. `showHiddenFields` may only be the literal `false`, or be left out. Also in `packages/data`: a Local API method (`find`, `create`, ...)
    may only be read to call it directly (`payload.find({...})` or `payload.find.call(payload, {...})`), so no destructured
    `find`, no `[payload.find][0](...)`, no `.apply` or `.bind`. No dynamic or numeric key (`obj[k]`, `rows[0]`; use a fixed
    name, `.at()` or a Map), no `Reflect`, and no `.values()`, `.entries()`, `.getOwnPropertyDescriptor()` or
    `.getOwnPropertyDescriptors()` (use `for...of` on a Map instead). Raw database access through `payload.db` has no
    reviewed file yet: `payloadDbAllowedPaths` in `eslint-rules/payload-lists.mjs` is empty. Its entry comes with the
    PR that adds the reviewed file, which must set the dealer for each transaction (Payload rule 2).
    Outside `packages/data`, `local/no-override-access` checks only a static `overrideAccess` key. Dynamic keys
    (`{ [k]: true }`) and spreads (`{ ...opts }`) in `apps/` and `services/` are not flagged by it, because the Payload
    instance cannot be reached there: the other two rules ban every way to reach it. The reasoning is in the header of
    `eslint-rules/no-override-access.mjs`.
  - `no-eval`, `no-implied-eval`, `no-new-func` and `no-with` are on. Process, thread, VM and module-loading modules are
    banned, with or without `node:`: `vm`, `worker_threads`, `child_process`, `module`, `cluster` and `repl`. So are the
    members that load code or modules by hand: `getBuiltinModule`, `_load`, `_linkedBinding`, `dlopen`, `.require`,
    `process.binding` and `process[k]`. These bans apply everywhere, `packages/data` included. Only exactly two files may
    start processes (`spawnAllowedPaths`): `infra/checks/src/config.test.ts` and
    `infra/checks/src/payload-ban-config.test.ts`. Lint bans these names; it cannot prove that no other route exists, so
    it is not a sandbox.
  - Inline `eslint-disable` comments are off, so a file cannot switch these rules off.
  - Limit: the rules work on names and syntax, not on types. A value that reaches the Payload instance through a name the
    rules do not know, or through a function's return value, is not caught by lint. The checks above are syntax checks,
    not proof. The type-aware rule is issue
    [#36](https://github.com/hafidimohammedamine-dotcom/dealer-platform/issues/36); it blocks the PR that adds `payload`,
    which may not merge before #36 is done. Until then, and after,
    Postgres row-level security and the cross-dealer leak tests are the locks that hold (`CLAUDE.md`, Payload rules 2-3).
- `eslint-rules/`, `eslint.payload-ban.mjs` and `eslint.config.mjs` become founder-only once #19 merges. A follow-up
  founder PR adds them to the founder-only list (CLAUDE.md, `scripts/check-founder-files.sh`, CODEOWNERS and
  `.prettierignore`). Until that PR merges, they are not founder-only yet.
- TypeScript casts (`x as T`, `<T>x`) are banned by `@typescript-eslint/consistent-type-assertions`. Use a type guard.
- `yarn test` is the only test command. Coverage is part of it. There is no separate coverage script.

## What `nx run-many` does

- Runs the same target (`typecheck`, `test` or `build`) in every workspace that has that script. Workspaces live in
  `apps/*`, `services/*`, `packages/*` and `infra/*`.
- Runs dependencies first. Each of these targets depends on `^build`, so Nx builds the workspaces a project depends on
  before it type checks or tests that project.
- Caches results. If the inputs did not change, Nx replays the saved result.
  The inputs include the workspace's own files and these root files: `tsconfig.base.json`, `eslint.config.mjs`,
  `eslint.payload-ban.mjs` and `eslint-rules/` (the Payload ban rules that `eslint.config.mjs` imports), `vitest.config.ts`,
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
- `infra/checks` also counts the Payload lint rules (`eslint.payload-ban.mjs` and `eslint-rules/*.mjs`) toward its gate.
  Its tests lint with the repo's `eslint.config.mjs` loaded through Vitest, and one test checks in a separate process that
  ESLint loading the file from disk (as `yarn lint` does) gives the same result.

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
