# 2026-10-12 - Payload app, slice 1: dealers, users, tenant-safe data helper (issue #5)

Devops change (`apps/admin`, `packages/data`, `packages/platform`, `docs`).

- **Payload 3.90.2** (exact pin) with the Postgres adapter and the official multi-tenant plugin, in `apps/admin`. Two
  collections only: `dealers` (the tenants) and `users` (roles `admin`, `desking_manager`, `sales_rep`, `bdc`).
- **Deny by default.** A config test fails CI if a collection lacks explicit access, is missing from the plugin, is not on the
  reviewed list in the final config, or if document locking is on.
- **No customer data and no HTTP route before the security gates.** `apps/admin/src/tenants/readiness.ts` holds four
  flags, all false: 2FA (#57), row-level security (#58), the durable audit table (#71) and the login surface (#73). A test
  fails CI if any collection other than dealers, users and Payload's own bookkeeping collections is registered while one of
  the first three is false, and another fails while 2FA or the login surface is missing if the admin app has any HTTP entry
  point (route folders, middleware/proxy/server/instrumentation/`next.config` files, `@payloadcms/next` or `next` imports).
  None of the four is built: this PR has no second factor, no row-level security, no audit table and no login limits.
- **Users.** An admin can change a user only when all of the user's dealers are the admin's own dealers. Users are
  deactivated, not deleted, and deactivation ends all of the user's sessions. Email verification is on. Every write without
  a logged-in user is refused (also first-user registration). Forgot-password and reset-password are closed until #73.
  `where`/`sort` may not name the dealer rows. Cookies are `Secure` and
  `SameSite=Strict` outside dev. Email changes are not possible yet (issue #61).
- **`packages/data`**: `forTenant(api, { headers, tenantId })` is async and takes the user only from Payload's built-in
  `auth` over the request headers. It always passes `overrideAccess: false`, `depth`, `draft`, a bounded `limit` and the
  dealer, and refuses a `where` that filters through a linked record. Page counts are off unless asked for.
- **`packages/platform`**: an append-only audit writer (secret-looking keys removed). User and dealer changes use it.
- **Start-up checks** (`APP_ENV` has no default; the secret needs 32 characters; https outside dev; `EMAIL_FROM` and
  `RESEND_API_KEY` outside dev). New variable `EMAIL_FROM` in `.env.example`.
- **Passwords.** 12-character minimum with a common-password list, checked when an admin creates a user; no password
  edit-in-place. Login rate limits, the trusted client IP, login and failed-login audit, and the reset flow are issue #73.
  `payload-migrations`, which Payload leaves open to every signed-in user, is closed at start-up.
- **Lint.** Syntax bans on Local API calls (on `payload`, on any alias, and any call shaped like one), `payload.db`,
  aliasing or destructuring the Payload instance, any `overrideAccess` but the literal `false`, `getPayload`, namespace,
  default and dynamic Payload imports and `require`, in TypeScript and JavaScript files (stopgap until the type-aware #36).
- **Migration.** A dealer that still has staff cannot be deleted (`ON DELETE restrict` on `users_tenants.tenant_id`).
- **Migration**: the first migration is in `apps/admin/migrations/`. No CI job runs it yet.
- A Yarn resolution swaps `@esbuild-kit/esm-loader` (deprecated, unused by `drizzle-kit`'s code, pulled in by the exact
  `drizzle-kit@0.31.7` in Payload's Postgres adapter) for `tsx`, which clears the CI "Dependency audit" step and removes the
  need for the old `esbuild` override.
- Docs: new `docs/api/dealers-and-users.md`, `docs/runbooks/admin-down.md`, `docs/runbooks/migration-failed.md` and
  `docs/help/README.md`; env-vars, setup, architecture and key-leak pages updated.

**Not live for dealers.** No dealer-facing flow exists yet, so there is no help-center page ("Add a user to your
dealership" comes with the screens and 2FA). Not built, with owners: 2FA (#57), row-level security and the migration
job (#58), the cross-dealer attack suite on real Postgres (#60), the email-change flow (#61), the durable audit table
(#71), the login surface (#73). Founder decisions: #72.
