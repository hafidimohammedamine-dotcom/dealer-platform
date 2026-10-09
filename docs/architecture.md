# Architecture

The product architecture (Payload admin, NestJS services, Postgres, queues) is described in `CLAUDE.md` until the docs agent
writes the full version here.

## CI and review

```
PR opened / pushed
 ├─ CI (ci.yml, pull_request, from the PR, no secrets)
 │    guard-script tests · install · lint · typecheck · test · build · audit
 ├─ Guards (guards.yml, pull_request_target, from main)
 │    PR fetched as data → founder-only files (author + pusher) · skills manifest + checksums · secret scan of PR commits
 └─ Review team (review.yml, pull_request_target, from main)
      PR fetched as data (rule files removed) → wait for CI + Guards → reviewers read only → fixed step scans the answer,
      posts it, labels PASS (ready-to-merge) or FAIL (changes-requested)
A founder reads the result and merges.
```

Agents (manager and builders) open and push PRs with the agents' own GitHub account; founders use their own accounts.
Failure handling: `docs/runbooks/ci-guards.md`.
