# Runbook: a migration failed

Status: **not built yet.** The migration job in CI (one job before every deploy, never at container start; CLAUDE.md
Payload rule 5) does not exist yet, so there is no real failure to handle today. This page says what the first version of
the runbook will cover. Owner: devops. It is completed together with issue #58, which adds the job.

## What will be true when the job exists

- Migrations run as one CI job before the deploy. If the job fails, the deploy does not start and the old version keeps
  running. Nothing is half-deployed.
- Each migration runs in a transaction where Postgres allows it, so a failed migration leaves the schema as it was.
- The `down` function of every migration is tested against a real Postgres (`apps/admin/src/tenants/migration.test.ts`).

## Steps when it fails (draft)

1. Read the CI log of the migration job. Note the migration name and the error.
2. Check that the database is in the state before the migration: the `payload_migrations` table lists the migrations that
   ran. Do not edit that table by hand.
3. Fix forward on a branch (a new migration), or revert the pull request. Never edit a migration that already ran on staging
   or production.
4. If a migration ran partly on production, restore from the daily backup into a new database and compare, before touching
   production. Restore is tested monthly (devops standards); the procedure is not written yet.
5. Tell both founders. Production changes are theirs.

## Not built yet

- The CI job and its alert.
- The backup restore procedure.
