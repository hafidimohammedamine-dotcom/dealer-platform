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

Agents (manager and builders) are moving to their own GitHub account (`AGENT_GH_TOKEN`); founders use their own accounts.
The switch is in progress: until it is done, agents still push with a founder's token, and the founder-only check protects
us fully only after it (see [Guards and review](runbooks/ci-guards.md)).
Failure handling: `docs/runbooks/ci-guards.md`.
