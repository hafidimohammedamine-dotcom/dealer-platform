# Architecture

The product architecture (Payload admin, NestJS services, Postgres, queues) is described in `CLAUDE.md` until the docs agent
writes the full version here.

## Repo layout and where data lives

**Built** means code exists in this repo today. **Reserved** means the folder, name or variable is set aside and
documented, but nothing uses it yet.

| Part                      | Where                                                          | Status                                                                |
| ------------------------- | -------------------------------------------------------------- | --------------------------------------------------------------------- |
| Yarn workspaces + Nx      | `apps/*`, `services/*`, `packages/*`, `infra/*`                | Built: every workspace has `typecheck`, `test` and `build`            |
| Repo checks               | `infra/checks`, `eslint.payload-ban.mjs`, `eslint-rules/`      | Built: config tests and the Payload lint bans                         |
| Payload admin (CRM, site) | `apps/admin`                                                   | Reserved: Payload is not installed yet                                |
| Business services         | `services/*` (intake, ai, messaging, voice, desking, ...)      | Reserved: placeholder workspaces only                                 |
| Shared packages           | `packages/data`, `contracts`, `platform`, `ui`                 | Reserved: placeholder workspaces only                                 |
| CRM tables                | Postgres, owned by Payload, row-level security per dealer      | Reserved: no tables, roles or policies yet                            |
| Credit and finance data   | Separate encrypted Postgres schema owned by `services/desking` | Reserved: never in Payload collections; the schema does not exist yet |
| Queues                    | Redis, used by BullMQ                                          | Reserved: `REDIS_URL` only                                            |

Postgres roles (reserved, named in `.env.example`):

- `app_user` (`DATABASE_URL`): the app. Does not own the tables, so row-level security applies to it.
- `owner_user` (`MIGRATION_DATABASE_URL`): the one migration job in CI only. Never the app, never at container start.
- `desking_user` (`DESKING_DATABASE_URL`): `services/desking` only, for the encrypted credit and finance schema.

Setup and commands: [Developer setup](dev/setup.md). Every variable and its status:
[Environment variables](dev/env-vars.md).

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

Agents (manager and builders) open and push PRs with the agents' own GitHub account (`AGENT_GH_TOKEN_V2`, account
`mohammedaminehafidi-ctrl`), never a founder's token; founders use their own accounts.
Failure handling: `docs/runbooks/ci-guards.md`.
