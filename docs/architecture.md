# Architecture

The product architecture (Payload admin, NestJS services, Postgres, queues) is described in `CLAUDE.md` until the docs agent
writes the full version here.

## CI and review
```
PR opened / pushed
 ├─ CI (ci.yml, pull_request, from the PR, no secrets)
 │    guard-script tests · install · lint · typecheck · test · build · audit
 ├─ Pusher ledger (pusher-ledger.yml, pull_request_target, from main, no concurrency): who pushed these commits → signed statuses
 ├─ Guards (guards.yml, pull_request_target, from main)
 │    PR fetched as data (must be the event's head) → founder-only files (author + every pusher from the ledger) · skills manifest + checksums ·
 │    third-party skills vs their pinned upstream · agent workflow denies · secret scan of PR commits
 └─ Review team (review.yml, pull_request_target, from main)
      job review (read-only token): PR fetched as data (rule files removed) → wait for CI + Guards → reviewers read only →
      answer handed over as text → job post (write scopes, no Claude) scans it, posts it, labels PASS (ready-to-merge) or
      FAIL (changes-requested). The daily report and weekly audit post the same way.
A founder reads the result and merges.
Push to main (main-guard.yml): a founder's push (a merge) is fine; any other push is reverted, the manager disabled, a security issue opened.
```
Agents (manager and builders) open and push PRs with the agents' own GitHub account (`mohammedaminehafidi-ctrl`, the `agent`
line of `.github/accounts.txt`); founders use their own accounts. People are identified by numeric user ID, never by login.
Before Claude starts, every job holding the agents' token checks that it belongs to that account and is limited (classic with
only `repo`, or fine-grained). Details: `docs/runbooks/agent-network-lock.md`.
Failure handling: `docs/runbooks/ci-guards.md` (overview), `docs/runbooks/skill-guards.md`, `docs/runbooks/workflow-checker.md`.

### Guard checks for skills and agent workflows
- `scripts/check-skills.sh`: skill manifest, checksums, license, NOTICE and lock rows, and agent `skills:` lines (an agent that
  preloads a skill with `requires=<other>` must also list `<other>`).
- `scripts/check-skills-vs-base.sh`: vendored (third-party) skills keep their kind and source repo compared with `main`.
- `scripts/check-skills-upstream-all.sh`: each third-party skill equals its locked upstream commit minus whole units only
  (founder-reviewed when a removed unit holds a warning), and its `.claude/skills-patches/<name>.diff` record matches.
- `scripts/check-workflows.sh` (`check-workflows.py`, general rules for every workflow and local action;
  `check-workflows-claude.py`, the rules for jobs with a claude step; `check-workflows-lib.py`, shared policy and helpers; lists
  in `check-workflows-policy.json`): Claude runs only through the pinned claude-code-action, on `main`'s code, after the agent
  network lock and with its binaries, with known flags and a deny list that blocks loading any vendored skill on its own; Claude
  credentials reach no other step; no PR code, checkout moves or late scripts without a pin check in a claude job; no workflow
  with a claude step runs on `pull_request` or `workflow_run`; tag mode (no prompt) only on issues.
- `scripts/check-scrub-probe.sh` (job `scrub` in `egress-lock-claude.yml`, from `main`): run by Claude as a tool, it counts the
  Claude tokens a tool can see and prints counts only; the job fails above 0.
- `scripts/check-agent-token.sh` (every job holding the agents' token, before Claude): the token must belong to the `agent`
  account in `.github/accounts.txt` (by numeric ID) and be classic with exactly `repo`, or fine-grained with no classic scopes.
- `scripts/check-founder-files.sh` (guards): founder-only files change only if the PR author and pusher IDs are `founder` IDs
  and every commit was pushed by a founder according to the ledger.
- `scripts/check-pushers.sh` (guards): records who pushed each commit as a commit status signed with `GUARDS_LEDGER_KEY`
  (HMAC), and reads it back; GitHub keeps no durable pusher per commit and commit authors can be forged.
- `scripts/check-main-push.sh` (main-guard, every push to `main`): a non-founder push is reverted, the manager disabled, a
  blocked security issue opened.
- `scripts/check-python-deps.sh` (guards and CI): the guard scripts' Python packages (PyYAML, coverage.py) from a hash-pinned
  requirements file into a private venv.
- `scripts/check-claude-probe.py` (`egress-lock-claude.yml`, from `main`): decides the Skill-deny and scrub probes from the
  claude-code-action's execution file.
- `guards` runs the `main` copies of all of these on the PR's files as data, so a PR cannot weaken them. CI runs every guard
  script's tests through `scripts/check-coverage.sh` (each guard script at least 90% line coverage).

### Agent network lock
Agent jobs (manager, review, daily report, weekly audit, founder mentions) check out `main` and then run
`.github/actions/agent-egress-lock`: pinned, checksum-verified gitleaks, Claude Code and Bun; outbound HTTPS only to allow-listed host names
through a local SNI-checking proxy; no plain HTTP, raw IPs, outside DNS or IPv6; no sudo, no Docker. Claude Code's subprocess
isolation keeps the Claude token out of the tools agents run. Together with the agents' repo-only token without `workflow`
scope, this narrows what an injected instruction could do; it is not a complete data boundary. Details and limits: `docs/runbooks/agent-network-lock.md`.
