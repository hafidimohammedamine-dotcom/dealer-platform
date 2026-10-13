# Architecture

The product design (Payload admin, NestJS services, Postgres, queues) is set in `CLAUDE.md`. This page says what the repo
has today. Planned parts are marked **Planned** in [Data flow](data-flow.md), which shows how a lead moves through the
platform. Endpoints are listed in the [API index](api/README.md). All docs: [docs/README.md](README.md).

## Repo layout and where data lives

**Built** means code exists in this repo today. **Reserved** means the folder, name or variable is set aside and
documented, but nothing uses it yet.

| Part                      | Where                                                          | Status                                                                    |
| ------------------------- | -------------------------------------------------------------- | ------------------------------------------------------------------------- |
| Yarn workspaces + Nx      | `apps/*`, `services/*`, `packages/*`, `infra/*`                | Built: every workspace has `typecheck`, `test` and `build`                |
| Repo checks               | `infra/checks`, `eslint.config.mjs`                            | Built: config tests and lint. The Payload lint ban is not built yet (#36) |
| Payload admin (CRM, site) | `apps/admin`                                                   | Reserved: Payload is not installed yet                                    |
| Business services         | `services/*` (intake, ai, messaging, voice, desking, ...)      | Reserved: placeholder workspaces only                                     |
| Shared packages           | `packages/data`, `contracts`, `platform`, `ui`                 | Reserved: placeholder workspaces only                                     |
| CRM tables                | Postgres, owned by Payload, row-level security per dealer      | Reserved: no tables, roles or policies yet                                |
| Credit and finance data   | Separate encrypted Postgres schema owned by `services/desking` | Reserved: never in Payload collections; the schema does not exist yet     |
| Queues                    | Redis, used by BullMQ                                          | Reserved: `REDIS_URL` only                                                |

Postgres roles (reserved, named in `.env.example`):

- `app_user` (`DATABASE_URL`): the app. Does not own the tables, so row-level security applies to it.
- `owner_user` (`MIGRATION_DATABASE_URL`): the one migration job in CI only. Never the app, never at container start.
- `desking_user` (`DESKING_DATABASE_URL`): `services/desking` only, for the encrypted credit and finance schema.

Setup and commands: [Developer setup](dev/setup.md). Every variable and its status:
[Environment variables](dev/env-vars.md).

## CI and review

```
PR opened / pushed
 ├─ CI (ci.yml; pull_request: from the PR; push to main: from main; no secrets)
 │    guard-script tests · install · lint · typecheck · test · build · audit
 ├─ Agent egress lock test (egress-lock-test.yml, pull_request on lock changes, from the PR, no secrets): the lock on a real runner,
 │    plus break-on-purpose
 ├─ Pusher ledger (pusher-ledger.yml, every push to a branch but main, scripts from main, no concurrency): who pushed → signed statuses
 ├─ Guards (guards.yml, pull_request_target, from main)
 │    PR fetched as data (must be the event's head) → founder-only files (author + every pusher from the ledger) · skills manifest + checksums ·
 │    third-party skills vs their pinned upstream · agent workflow denies · secret scan of PR commits
 └─ Review team (review.yml, pull_request_target, from main)
      job review (read-only token): PR fetched as data (rule files removed) → wait for CI + Guards → reviewers read only →
      answer handed over as text → job post (write scopes, no Claude) scans it, posts it, labels PASS (ready-to-merge) or
      FAIL (changes-requested). The daily report and weekly audit post the same way.
A founder reads the result and merges.
Founder @claude on an issue (claude.yml, issue_comment by a founder, from main): job answer (read-only token, prompt mode)
reads the thread with gh → answer as text → job post scans and posts it on the issue.
Push to main (main-guard.yml, also hourly): a founder's push (a merge) is fine; any other push is undone (one commit with the previous tip's tree), every workflow that holds a
secret or write scope cancelled and disabled, a security issue opened; a push that passed no main-guard run (a [skip ci] head
commit, a cancelled run) stops the agents the same way at the next push or within the hour. The guard's own undo commit, and
a commit a founder accepts by running the workflow by hand, carry the `guards/main-guard` commit status instead of a run.
Manager shift (agent-manager.yml, hourly): job shift (token check, event check, Claude with the agents' token) → job after
(fresh runner, always): token and guard-workflow check again, the account's events in the last 24 hours all in this repository.
```

Agents (manager and builders) open and push PRs with the agents' own GitHub account (`mohammedaminehafidi-ctrl`, the `agent`
line of `.github/accounts.txt`); founders use their own accounts. People are identified by numeric user ID, never by login.
Before Claude starts, every job holding the agents' token checks that it belongs to that account and is limited (classic with
only `repo`, or fine-grained); every job holding a secret runs only on a run's first attempt (a re-run would hand today's
secrets to an old workflow version). Details: `docs/runbooks/agent-network-lock.md`.
Failure handling: `docs/runbooks/ci-guards.md` (overview), `docs/runbooks/skill-guards.md`, `docs/runbooks/workflow-checker.md`.

### Guard checks for skills and agent workflows

- `scripts/check-skills.sh`: skill manifest, checksums, license, NOTICE and lock rows, and agent `skills:` lines (an agent that
  preloads a skill with `requires=<other>` must also list `<other>`).
- `scripts/check-skills-vs-base.sh`: vendored (third-party) skills keep their kind and source repo compared with `main`.
- `scripts/check-skills-upstream-all.sh` (with `scripts/check-skill-upstream.sh` for one skill and `scripts/check-skill-deletions.py`
  for the unit rule): each third-party skill equals its locked upstream commit minus whole units only (founder-reviewed when a
  removed unit holds a warning), and its `.claude/skills-patches/<name>.diff` record matches. `scripts/check-skills-lib.sh`:
  the manifest and lock-row parsing every skill guard shares.
- `scripts/check-pr-archive.sh` (guards): a PR's tree, or one folder of it, unpacked as data with the tree's own `.gitattributes`
  switched off (an `export-ignore` there would hide a file from the checks that the merge still brings).
- `scripts/check-workflows.sh` (`check-workflows.py`, general rules for every workflow and local action;
  `check-workflows-claude.py`, the rules for jobs with a claude step; `check-workflows-people.py`, who may start what, the
  agents' token check, the manager's after-shift job and the first-attempt rule for every secret-holding job;
  `check-workflows-lib.py`, shared policy, pins and helpers; lists in `check-workflows-policy.json`): Claude runs only through the pinned claude-code-action, on `main`'s code, after the agent
  network lock and with its binaries, with known flags and a deny list that blocks loading any vendored skill on its own; Claude
  credentials reach no other step; no PR code, checkout moves or late scripts without a pin check in a claude job; no workflow
  with a claude step runs on `pull_request`, `workflow_run` or `push`; tag mode (no prompt) only on issues.
- `scripts/check-scrub-probe.sh` (job `scrub` in `egress-lock-claude.yml`, from `main`): run by Claude as a tool, it counts the
  Claude tokens a tool can see and prints counts only; the job fails above 0.
- `scripts/check-agent-token.sh` (every job holding the agents' token, before Claude, and again in the manager's `after`
  job): the token must belong to the `agent` account in `.github/accounts.txt` (by numeric ID) and be classic with exactly
  `repo`, or fine-grained with no classic scopes; the account owns no repository; the guard workflows are active; `main`'s
  head passed the main guard.
- `scripts/check-main-head.sh` (every Claude job, before the lock): the checked-out head of `main` passed the main guard.
  `scripts/check-shift-setup.sh`, `scripts/check-audit-prepare.sh`, `scripts/check-probe-skill.sh`: the only things that
  run between the lock and a Claude step, as pinned one-line scripts (the manager's setup, the audit's history files, the
  probe skill); the audit's dependency scan runs in a separate job without a secret and arrives as an artifact.
- `scripts/check-agent-events.sh` (the manager, before and after each shift): the agents' account has no event outside this
  repository in the last 24 hours (the token can comment anywhere GitHub lets it).
- `scripts/check-review-prepare.sh` (review and guards): fetches the PR as data into `/tmp/pr` with no credentials stored,
  no git filters or hooks, no symlinks, the agent-instruction files removed, and its history written as plain files.
- `scripts/check-review-post.sh` (every `post` job): computes the 60000-character cut of the handed answer, scans the whole
  handed text and that cut with `.gitleaks.toml` in one gitleaks run, and only then posts the cut; sets the review labels.
  `scripts/check-pr-ci-status.sh` (review): waits for CI and guards on the PR head and reports their status.
- `scripts/check-skill-deletions.py` (`check-skills-upstream-all.sh`): a third-party skill may differ from its upstream only
  by whole deleted units, with the founder-reviewed ones listed.
- `scripts/check-founder-files.sh` (guards): founder-only files change only if the PR author and pusher IDs are `founder` IDs
  and every commit was pushed by a founder according to the ledger.
- `scripts/check-pushers.sh` (`pusher-ledger.yml` records, guards verifies): records who pushed each commit as a commit status
  signed with `GUARDS_LEDGER_KEY` (HMAC), and reads it back; GitHub keeps no durable pusher per commit and commit authors can be forged.
- `scripts/check-main-push.sh` (main-guard, every push to `main` and hourly): a non-founder push is undone with one commit
  carrying the previous tip's tree (never per-commit reverts), every
  workflow that holds a secret or write scope cancelled and disabled, a blocked security issue opened; every run also
  requires the previous push's head (hourly: `main`'s head) to have passed the main guard itself, so a push whose head
  commit says `[skip ci]` (no run) or whose run was cancelled stops the agents at the next push or within the hour; the
  undo commit it pushes and a commit a founder accepts (`workflow_dispatch`) are marked with the `guards/main-guard`
  commit status (posted as github-actions[bot] only).
- `scripts/check-python-deps.sh` (guards and CI): the guard scripts' Python packages (PyYAML, coverage.py) from a hash-pinned
  requirements file into a private venv.
- `scripts/check-pins.sh` (`update`: founders and the tests; `verify`: every pin step): regenerates `.github/pins.txt` (sha256
  of every file in `pins_required`, `scripts/check-workflows-policy.json`: `.github/actions/`, the `scripts/check-*` scripts
  except tests and test libraries, `.gitleaks.toml`, `.github/accounts.txt`, `.yarnrc.yml`, and every `CLAUDE.md`,
  `CLAUDE.local.md`, `.mcp.json` and `.claude/` file anywhere) and the `PINS_SHA256` every workflow checks before running any of them; `verify`
  fails a job whose tree holds such a file that is not listed.
- `scripts/check-scan-lib.sh` (sourced by the hand-off and by `check-review-post.sh`): `scan_answer <dir>`, the one
  gitleaks call over an agent's text with `.gitleaks.toml`; returns 0 (clean), 3 (looks like a secret: a fixed notice
  replaces the text) or another code (an error: the step fails and nothing is posted).
- `scripts/check-claude-answer.sh` (the review, mention, daily-report and weekly-audit jobs, after their Claude step; the
  manager runs only its blocked-call listing, since it posts its own shift log; the egress probe jobs use
  `check-claude-probe.py` instead; pinned, run under `env -i` with a fixed `PATH`, `HOME` and `TMPDIR`):
  lists blocked tool calls (scanned first; on a hit one count-only line, on a scanner error nothing and the step fails)
  and hands the answer to the post job as a job output: scanned with the pinned gitleaks before it leaves the job (a job
  output is shown in the post job's log header), cut by the pinned `scripts/check-claude-answer-cut.py` to at most
  120000 bytes (one environment variable; the cut lands on a line break, space or tab and never inside a BEGIN/END
  block; with nothing safe to keep, a withheld notice is handed over instead, which the post job posts as FAIL).
- `scripts/check-accounts-lib.sh` (sourced by the guards that read `.github/accounts.txt`): the one parser of that file and
  the one lookup (`account_field`). `scripts/check-github-lib.sh`: the GitHub helpers the token-holding guards share
  (`gh_context`, `token_account`, `main_guard_passed`). `scripts/check-git-lib.sh`: the no-filter, no-hook git settings for
  checkouts of other people's files. `scripts/check-testlib.sh`: the bookkeeping every `scripts/*.test.sh` shares.
- `scripts/check-claude-probe.py` (`egress-lock-claude.yml`, from `main`): decides the Skill-deny, scrub and read-deny
  probes from the claude-code-action's execution file.
- `guards` runs the `main` copies of all of these on the PR's files as data, so a PR cannot weaken them. CI runs every guard
  script's tests through `scripts/check-coverage.sh` (each guard script at least 90% line coverage).

### Agent network lock

Agent jobs (manager, review, daily report, weekly audit, founder mentions) check out `main` and then run
`.github/actions/agent-egress-lock`: pinned, checksum-verified gitleaks, Claude Code and Bun; outbound HTTPS only to allow-listed host names
through a local SNI-checking proxy; no plain HTTP, raw IPs, outside DNS or IPv6; no sudo, no Docker. Claude Code's subprocess
isolation keeps the Claude token out of the tools agents run. Together with the agents' repo-only token without `workflow`
scope, this narrows what an injected instruction could do; it is not a complete data boundary. Details and limits: `docs/runbooks/agent-network-lock.md`.
