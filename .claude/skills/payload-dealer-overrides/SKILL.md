---
name: payload-dealer-overrides
description: Our binding rules on top of the official Payload skill. Read together with the payload skill whenever you write or review Payload code (collections, access rules, endpoints, hooks, auth, webhooks, plugins). Where the two disagree, this file and CLAUDE.md win.
---

# Payload: our overrides (founder-owned)

The `payload` skill next to this one is Payload's own general guide (upstream, unchanged).
It is written for every kind of Payload app, not for a multi-dealer system holding credit data.
**Use it to learn how Payload works. Use CLAUDE.md and this file to decide what we are allowed to do.**
If any example in any skill disagrees with CLAUDE.md or this file, CLAUDE.md and this file win.

## Stack differences (ignore these parts of the skill)
- We use **Yarn workspaces + Nx**, not pnpm or npm. Never run `create-payload-app@latest`.
- We use the **Postgres adapter** only. Ignore MongoDB / `mongooseAdapter` / SQLite examples.
- We run the **exact pinned Payload v3 version** in `apps/admin/package.json`. Never upgrade inside a feature PR.
- Do **not** fetch remote docs (for example `llms-full.txt` or any URL in the skill) into context.
  Use only the local skill files and the code in this repo.

## Data access
1. All reads and writes go through `packages/data` with the logged-in `user`, `overrideAccess: false`
   and the dealer tenant. This covers `payload.find/findByID/count/create/update/delete/duplicate`
   **and** `req.payload.*` inside routes, endpoints, hooks and server components.
2. `overrideAccess: true` or a Local API call without `user` is allowed **only** in a short, security-reviewed
   allow-list of background jobs (migrations, seed for fixtures, system jobs). Each one is listed in
   `packages/data` with a comment saying why. Anything else is a blocking finding.
3. Always pass explicit `overrideAccess`, `depth` and `versions` (CLAUDE.md rule 4).

## Tenants (dealers)
4. The dealer of a record comes **only** from the official multi-tenant plugin and `packages/data`,
   based on the logged-in user's fixed dealer ID. A `tenant`/dealer value sent by the client on create
   or update is ignored or rejected. Every collection gets a leak test proving a dealer A user cannot
   create, move or read a dealer B record. (The skill's plain `tenant` field example is not enough.)
5. Never trust roles or dealer IDs from the JWT. Do not use `saveToJWT` for roles or tenants.
   Load the user's current roles and dealer from the database on each request, so a demoted or
   removed user loses access immediately.
6. Relationship fields use the generated same-dealer link guard (CLAUDE.md rule 12).

## Versions and drafts
7. Versions and drafts are **off** for CRM collections unless a reviewed PR turns them on.
   If turned on, the `_v` version tables get the same row-level security, leak tests and attack suite
   as the main table, because they hold copies of customer data.

## Endpoints and custom routes
8. Every custom endpoint checks `req.user` and the role first, then calls `packages/data`.
   Never create or update from the raw request body: use an explicit field allow-list and validate with
   the zod schemas from `packages/contracts`. Uploads have size and type limits.
9. The skill's `previewEndpoint` pattern (caller chooses collection and `where`) is **banned**.
10. Never write a custom login, signup or password endpoint. Use Payload's built-in auth
    (rate limiting, session revoke, 2FA per CLAUDE.md rules 9 and 14). No tokens returned in bodies by hand.
11. API keys: one key per dealer and per integration, scoped to that dealer, compared in constant time
    (`crypto.timingSafeEqual`), stored hashed, rotatable. Never one shared key for all dealers.

## Webhooks (CLAUDE.md non-negotiable rule 4)
12. Verify the sender's signature over the **raw** body (HMAC or the provider's public-key scheme) with
    `crypto.timingSafeEqual`, and reject old timestamps (replay window).
13. Save the raw message first, then process it from a BullMQ queue. The same message twice is handled once
    (idempotency key per provider message ID).
14. Error responses are generic. Never return `err.message`, stack traces or internal IDs.

## Plugins and skill updates
15. No community plugins without a security review (CLAUDE.md rule 7). Plugin examples in the skill are for learning only.
16. The `payload` skill is pinned (upstream commit in `.claude/skills/SKILLS-LOCK.md` and file hashes in
    `.claude/skills/checksums.sha256`, checked in CI). Never run `npx skills update` in an agent job.
    A skill update is its own PR that a founder opens and the security reviewer passes.
