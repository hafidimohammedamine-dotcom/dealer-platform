# Architecture

The product architecture (Payload admin, NestJS services, Postgres, queues) is described in `CLAUDE.md` until the docs agent
writes the full version here.

## CI and review
```
PR opened / pushed
 ├─ CI (ci.yml, pull_request, from the PR, no secrets)
 │    guard-script tests · install · lint · typecheck · test · build · audit
 ├─ Guards (guards.yml, pull_request_target, from main)
 │    PR fetched as data → founder-only files (author + pusher) · skills manifest + checksums ·
 │    third-party skills vs their pinned upstream · agent workflow denies · secret scan of PR commits
 └─ Review team (review.yml, pull_request_target, from main)
      PR fetched as data (rule files removed) → wait for CI + Guards → reviewers read only → fixed step scans the answer,
      posts it, labels PASS (ready-to-merge) or FAIL (changes-requested)
A founder reads the result and merges.
```
Agents (manager and builders) open and push PRs with the agents' own GitHub account; founders use their own accounts.
Failure handling: `docs/runbooks/ci-guards.md`.

### Guard checks for skills and agent workflows
- `scripts/check-skills.sh`: skill manifest, checksums, license, NOTICE and lock rows, and agent `skills:` lines (an agent that
  preloads a skill with `requires=<other>` must also list `<other>`).
- `scripts/check-skills-vs-base.sh`: vendored (third-party) skills keep their kind and source repo compared with `main`.
- `scripts/check-skills-upstream-all.sh`: each third-party skill equals its locked upstream commit minus whole units only, and its
  `.claude/skills-patches/<name>.diff` record matches.
- `scripts/check-workflows.sh`: Claude runs only through the pinned claude-code-action, after the agent network lock, with known
  flags and a deny list that blocks loading any vendored skill on its own; Claude credentials reach no other step.
- `guards` runs the `main` copies of all of these on the PR's files as data, so a PR cannot weaken them.

### Agent network lock
Agent jobs (manager, review, daily report, weekly audit, founder mentions) start with `.github/actions/agent-egress-lock`:
outbound network only to an allow-list (GitHub, Anthropic API, npm/Yarn registries, the runner's log storage), no IPv6, no sudo,
no Docker. Details and limits: `docs/runbooks/ci-guards.md`, "Agent network lock".
