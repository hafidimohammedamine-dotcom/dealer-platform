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

### Agent skills
- Agents that work on Payload (builder-crm, builder-inventory, builder-finance, devops, security, architect, tester,
  chief-engineer, designer) **preload** two skills together through their `skills:` line: `payload` (Payload's own guide, a pinned
  upstream copy with a recorded deletion-only patch) and `payload-dealer-overrides` (our binding rules). Order of authority:
  CLAUDE.md > payload-dealer-overrides > payload.
- No agent job may load `payload` on its own: every claude-code-action step (manager, review, daily report, weekly audit, and the
  founder-mention job in `claude.yml`) denies `Skill(payload)` in its `--disallowedTools` line. `scripts/check-workflows.sh` checks
  this step by step, plus the manager's command denies; `guards` runs the `main` copy on every PR's workflows.
- Skills are pinned and checked by `guards`: `scripts/check-skills.sh` (manifest, checksums, license, NOTICE and lock rows, agent
  preloads) and `scripts/check-skills-upstream-all.sh` (each third-party skill equals its locked upstream commit with deletions only,
  and its `.claude/skills-patches/<name>.diff` record matches).
- `overrideAccess: true` is allowed only for founder-approved system jobs listed in `packages/data/override-allowlist.txt`, a
  founder-only file, and only once the lint rule from CLAUDE.md Payload rule 1 exists.
