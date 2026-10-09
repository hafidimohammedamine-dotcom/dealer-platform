# Runbook: CI pipeline and build failures

The pipeline is `.github/workflows/ci.yml`. It runs on pull requests into `main` and on pushes to `main`.
It has one job, `checks`, on Ubuntu, with a 30-minute timeout and read-only repo permissions.

The workflow is founder-owned (`.github/` is in the founders-only list in `CLAUDE.md`). To change a step, comment on the
issue with `REQUEST: .github/workflows/ci.yml - <change> - <why>`.

## Step order

GitHub runs the steps in this order. When a step fails, GitHub stops the job, so later steps do not run.

| #   | Step             | Command or action                                              | Runs                          |
| --- | ---------------- | -------------------------------------------------------------- | ----------------------------- |
| 1   | Checkout         | `actions/checkout`, full history (`fetch-depth: 0`)            | Always                        |
| 2   | Secret scan      | gitleaks in Docker: `detect --source=/repo --redact --verbose` | Always                        |
| 3   | Set up Node      | `actions/setup-node`, Node 20                                  | Only if `package.json` exists |
| 4   | Install          | `corepack enable && yarn install --immutable`                  | Only if `package.json` exists |
| 5   | Lint             | `yarn lint` (ESLint, then Prettier check)                      | Only if `package.json` exists |
| 6   | Type check       | `yarn typecheck`                                               | Only if `package.json` exists |
| 7   | Tests            | `yarn test` (Vitest, 90% coverage gate, config tests)          | Only if `package.json` exists |
| 8   | Dependency audit | `yarn npm audit --severity moderate --all --recursive`         | Only if `package.json` exists |
| 9   | Build            | `yarn build`                                                   | Only if `package.json` exists |

Build is the last step. If it is the one that fails, steps 1 to 8 already passed on that run.

## Before you push

Run the same checks locally, in this order:

```bash
corepack yarn lint
corepack yarn typecheck
corepack yarn test
corepack yarn build
```

The secret scan needs Docker. It is the same command CI runs:

```bash
docker run --rm -v "$PWD:/repo" zricethezav/gitleaks:v8.18.4 detect --source=/repo --redact --verbose
```

## When a step fails

Open the job log, find the first red step, and fix that. Push the fix to your branch. CI runs again on the pull request.

### Lint fails

- **ESLint error.** Read the rule name in the log. The Payload rule bans direct `payload.find`, `payload.create`,
  `payload.update`, `payload.delete` and similar calls outside `packages/data`. Use `packages/data` instead.
- **Prettier: "Code style issues found".** Run `yarn format` locally and commit the result. Prettier also checks Markdown
  in `docs/`.

### Type check fails

- Run `yarn typecheck` locally and fix the first error in the log. Strict mode is on and cannot be turned off.
- Do not add `any` or `@ts-ignore` only to get past the check.

### Tests fail

- Run `yarn test` locally. The log names the failing test file, or the coverage line that is under 90%.
- Add tests for new code. Do not lower the threshold in `vitest.config.ts`. That is a founder decision.
- Config tests in `infra/checks` also run here. They check `tsconfig.base.json`, every workspace's scripts, `.yarnrc.yml`
  and the `.env.example` keys.

### Dependency audit fails

- The log lists a dependency advisory at moderate severity or higher.
- Do not delete or skip this step. Post the advisory name on the pull request so the security reviewer sees it.
- If a fixed version exists, upgrade it and commit the lockfile change. Security advisories for Payload are patched within
  48 hours (`CLAUDE.md`, Payload rule 6).

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

### Secret scan fails

- gitleaks found something that looks like a secret in this pull request's commits. The log shows the file, the line and
  the rule. The secret itself is redacted.
- **Treat a real key as leaked, even if the pull request is closed.** Revoke or rotate it at the provider now.
  Then follow [Key leak or loss](key-leak-or-loss.md) for our own keys.
- Removing the key from a later commit does not stop the leak. The old commit still holds it.
- Do not add an ignore rule yourself. Ask a founder with `REQUEST:`.

## Known gaps (as of this page)

- There is no migration job in `ci.yml`. The plan is one migration job in CI, before deploy, never at container start.
  It is not built.
- There is no deploy step.
- Until a founder adds `enableScripts: false` to `.yarnrc.yml`, the config test "keeps dependency install scripts off"
  fails.
- `main` may get a newer `ci.yml`. At the time this page was written, `main` also runs guard-script tests, scans the full
  history on pushes to `main`, and runs Build before the dependency audit. When this branch picks up that change, update
  the step table above to match the file.
