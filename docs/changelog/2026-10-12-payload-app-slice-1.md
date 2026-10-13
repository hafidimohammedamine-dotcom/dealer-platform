# 2026-10-12 - Payload app, slice 1: dealers, users, tenant-safe data helper (issue #5)

Devops change (`apps/admin`, `packages/data`, `packages/platform`, `docs`).

- **Payload 3.90.2** (exact pin) with the Postgres adapter and the official multi-tenant plugin, in `apps/admin`. Two
  collections only: `dealers` (the tenants) and `users` (roles `admin`, `desking_manager`, `sales_rep`, `bdc`).
- **Deny by default.** A config test fails CI if a collection lacks explicit access, is missing from the plugin, is not on the
  reviewed list in the final config, or if document locking is on.
- **No customer data before 2FA, row-level security and the audit table.** `apps/admin/src/tenants/readiness.ts` holds three
  flags, all false. A test fails CI if any collection other than dealers, users and Payload's own bookkeeping collections is
  registered while one is false, and while 2FA is false if the admin app has any route file. 2FA is issue #57, row-level
  security is issue #58. Neither is built: this PR has no second factor and no row-level security.
- **Users.** An admin can change a user only when all of the user's dealers are the admin's own dealers. Users are
  deactivated, not deleted. Email verification is on. First-user registration is refused. Cookies are `Secure` and
  `SameSite=Strict` outside dev. Email changes are not possible yet (issue #61).
- **`packages/data`**: `forTenant` is async, re-reads the user from the database, and always passes `overrideAccess: false`,
  `depth`, `draft`, a bounded `limit` and the dealer. Page counts are off unless asked for.
- **`packages/platform`**: an append-only audit writer (secret-looking keys removed). User and dealer changes use it.
- **Start-up checks** (`APP_ENV` has no default; the secret needs 32 characters; https outside dev; `EMAIL_FROM` and
  `RESEND_API_KEY` outside dev). New variable `EMAIL_FROM` in `.env.example`.
- **Passwords and login limits.** 12-character minimum with a common-password list, no password edit-in-place (reset link
  only, audited), per-address and per-email rate limits on login, forgot-password and reset-password, failed logins audited.
  `payload-migrations`, which Payload leaves open to every signed-in user, is closed at start-up.
- **Lint.** Name-based bans on Local API calls, `payload.db`, `overrideAccess: true` and `getPayload` (stopgap until #36).
- **Migration**: the first migration is in `apps/admin/migrations/`. No CI job runs it yet.
- A Yarn resolution swaps `@esbuild-kit/esm-loader` (deprecated, unused by `drizzle-kit`'s code, pulled in by the exact
  `drizzle-kit@0.31.7` in Payload's Postgres adapter) for `tsx`, which clears the CI "Dependency audit" step and removes the
  need for the old `esbuild` override.
- Docs: new `docs/api/dealers-and-users.md`; env-vars, setup, architecture and key-leak pages updated.

**Not live for dealers.** No dealer-facing flow exists yet, so there is no help-center page ("Add a user to your
dealership" comes with the screens and 2FA). Not built, with owners: 2FA (#57), row-level security and the migration
job (#58), the cross-dealer attack suite on real Postgres (#60), the email-change flow (#61).
