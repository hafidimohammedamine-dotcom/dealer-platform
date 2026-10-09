# Runbook: CI pipeline and build failures

The pipeline is `.github/workflows/ci.yml`. It runs on pull requests into `main` and on pushes to `main`.
It has one job, `checks`, on Ubuntu, with a 30-minute timeout and read-only repo permissions (`contents: read`).

Two other workflows also check every pull request. `guards.yml` runs from `main`, checks founder-only files and scans
the pull request's commits for secrets. The review workflow reads the result. See [Guards and review](ci-guards.md).

The workflow is founder-owned (`.github/` is in the founders-only list in `CLAUDE.md`). To change a step, comment on the
issue with `REQUEST: .github/workflows/ci.yml - <change> - <why>`.

## Step order

GitHub runs the steps in this order. When a step fails, GitHub stops the job, so later steps do not run.
Steps marked "Push to `main` only" are skipped on pull requests. Steps marked "If `package.json`" are skipped when the
repo has no `package.json`.

| #   | Step               | Command or action                                                                                        | Runs                |
| --- | ------------------ | -------------------------------------------------------------------------------------------------------- | ------------------- |
| 1   | Checkout           | `actions/checkout`, full history (`fetch-depth: 0`), no persisted token                                  | Always              |
| 2   | Install gitleaks   | `./.github/actions/install-gitleaks`: gitleaks 8.18.4 from its GitHub release, sha256 checked, no Docker | Always              |
| 3   | Secret scan        | `gitleaks detect --source=. --config=.gitleaks.toml --redact --verbose` on the full history              | Push to `main` only |
| 4   | Guard script tests | The five `scripts/check-*.test.sh` tests, then `scripts/gitleaks-config.test.sh`                         | Always              |
| 5   | Set up Node        | `actions/setup-node`, Node 20                                                                            | If `package.json`   |
| 6   | Install            | `corepack enable && yarn install --immutable`                                                            | If `package.json`   |
| 7   | Lint               | `yarn lint` (ESLint, then Prettier check)                                                                | If `package.json`   |
| 8   | Type check         | `yarn typecheck`                                                                                         | If `package.json`   |
| 9   | Tests              | `yarn test` (Vitest, 90% coverage gate, config tests)                                                    | If `package.json`   |
| 10  | Build              | `yarn build`                                                                                             | If `package.json`   |
| 11  | Dependency audit   | `yarn npm audit --severity moderate --all --recursive`                                                   | If `package.json`   |

Two things to know about the order:

- **Build runs before the dependency audit.** The audit is the last step. If the audit fails, the build already passed on
  that run.
- **The pull request's own secret scan is not in `ci.yml`.** It runs in `guards.yml` (job `guards`), against the
  pull request's commits only. The full-history scan in step 3 runs only on pushes to `main`.

## Before you push

Run the same checks locally, in this order:

```bash
corepack yarn lint
corepack yarn typecheck
corepack yarn test
corepack yarn build
corepack yarn npm audit --severity moderate --all --recursive
```

## Secret scan on your machine

Use gitleaks **8.18.4**, the same version CI installs. CI downloads the release file and checks its sha256 before it
runs. Install the same release, or use the Docker image with the same tag. The image is the same version, but it is a
different file, so CI's checksum check does not cover it.

The full-history scan, the same command and flags as CI step 3:

```bash
gitleaks detect --source=. --config=.gitleaks.toml --redact --verbose
```

Docker version of the same scan:

```bash
docker run --rm -v "$PWD:/repo" zricethezav/gitleaks:v8.18.4 detect --source=/repo --config=/repo/.gitleaks.toml --redact --verbose
```

To check a pull request's commits the way the `guards` job does, run this after `origin/main` is fetched. It ignores
`.gitleaksignore` and inline `gitleaks:allow` comments, as CI does:

```bash
mkdir -p /tmp/noignore
gitleaks detect --source=. --config=.gitleaks.toml --gitleaks-ignore-path=/tmp/noignore --ignore-gitleaks-allow --redact --verbose --log-opts="origin/main..HEAD"
```

gitleaks prints matches redacted. Do not paste a match anywhere, even redacted, outside the terminal.

## When a step fails

Open the job log, find the first red step, and fix that. Push the fix to your branch. CI runs again on the pull request.

### Install gitleaks fails

- The download failed, or the checksum did not match. Re-run the job once.
- If it fails again, tell a founder. The action is founder-owned.

### Guard script tests fail

- The log names the test script. Run it locally, for example `bash scripts/check-skills.test.sh`, and read the failing case.
- For the secret config test, set `GITLEAKS` to your local binary: `GITLEAKS=/path/to/gitleaks bash scripts/gitleaks-config.test.sh`.
- The `scripts/check-*` files and `.gitleaks.toml` are founder-owned. Do not change them to make a test pass. Follow
  [Guards and review](ci-guards.md) and send a `REQUEST:`.

### Secret scan fails (push to `main`)

- This step runs only after a change reached `main`. The log shows the file, the line and the rule. The secret itself is redacted.
- **Treat a real key as leaked, even if the pull request is closed.** Revoke or rotate it at the provider now.
  Then follow [Key leak or loss](key-leak-or-loss.md) for our own keys.
- Removing the key from a later commit does not stop the leak. The old commit still holds it.
- Do not add an ignore rule yourself. Ask a founder with `REQUEST:`.
- A secret in a pull request is caught earlier, by the `guards` job. See [Guards and review](ci-guards.md).

### Lint fails

- **ESLint error.** Read the rule name in the log. The Payload rules in `eslint.payload-ban.mjs` are:
  - `local/no-payload-instance-access`: outside `packages/data`, do not use the Payload instance (only `logger` is allowed).
  - `local/no-override-access`: `overrideAccess` must be the literal `false`, in every file.
  - `no-restricted-imports`: database drivers and Payload adapters are imported only in `packages/data`.

  Use `packages/data` instead. Inline `eslint-disable` comments do not work for these rules.

- **Prettier: "Code style issues found".** Run `yarn format` locally and commit the result. Prettier also checks Markdown
  in `docs/`.

### Type check fails

- Run `yarn typecheck` locally and fix the first error in the log. Strict mode is on and cannot be turned off.
- Do not add `any` or `@ts-ignore` only to get past the check.

### Tests fail

- Run `yarn test` locally. The log names the failing test file, or the coverage line that is under 90%.
- Add tests for new code. Do not lower the threshold in `vitest.config.ts`. That is a founder decision.
- Config tests in `infra/checks` also run here. They check `tsconfig.base.json`, every workspace's scripts, `.yarnrc.yml`
  (including `enableScripts: false`) and the `.env.example` keys.

### Build fails

1. Find the first failing workspace in the log. Nx builds dependencies first, so a later workspace can fail only because
   an earlier one failed. Fix the first one.
2. Reproduce it locally:

   ```bash
   corepack enable
   corepack yarn install --immutable
   corepack yarn build
   ```

3. If it passes locally but fails in CI, run the build with the cache off, to rule out a stale cache:

   ```bash
   corepack yarn build --skip-nx-cache
   ```

4. Common causes:
   - A type error in a workspace's `tsconfig.build.json` build.
   - A missing export, or an import from another workspace that is not built yet.
   - A dependency added without updating `yarn.lock`. That shows up at the **Install** step, not at Build.
5. Do not remove the Build step, do not set `continue-on-error`, and do not commit `dist/` folders. `dist/` is git-ignored.
6. If the failure is in the workflow file itself, send a `REQUEST:` to the founders.

### Dependency audit fails

- The build passed on this run, because Build runs first. Only the audit failed.
- The log lists a dependency advisory at moderate severity or higher.
- Do not delete or skip this step. Post the advisory name on the pull request so the security reviewer sees it.
- If a fixed version exists, upgrade it and commit the lockfile change. Security advisories for Payload are patched within 48 hours (`CLAUDE.md`, Payload rule 6).
- If the package is pinned in `package.json` `resolutions`, check the "Pinned overrides" table in
  [Developer setup](../dev/setup.md#pinned-overrides) before you change the pin.

## Not in CI yet

- There is no migration job in `ci.yml`. The plan is one migration job in CI, before deploy, never at container start.
  It is not built.
- There is no deploy step.
