---
name: payload-dealer-overrides
description: Our binding rules on top of the official Payload skill. Read together with the payload skill whenever you write or review Payload code (collections, access rules, uploads, views, endpoints, hooks, auth, jobs, webhooks, plugins). Order of authority - CLAUDE.md, then this file, then the payload skill.
---

# Payload: our overrides (founder-owned)

The `payload` skill next to this one is Payload's own general guide (upstream, unchanged). It is written for every kind of
Payload app, not for a multi-dealer system holding customer and credit data.
**Use it to learn how Payload works. Use CLAUDE.md and this file to decide what we are allowed to do.**
**Order of authority: CLAUDE.md > payload-dealer-overrides (this file) > payload skill.**

## Stack differences (ignore these parts of the skill)
- We use **Yarn workspaces + Nx**. Ignore every `npx`, `npm`, `pnpm` and `create-payload-app` command in the skill
  (for example its Quick Start); never run them.
- We use the **Postgres adapter** only. Ignore MongoDB / `mongooseAdapter` / SQLite examples.
- We run the **exact pinned Payload v3 version** in `apps/admin/package.json`. Never upgrade inside a feature PR.
- **Background jobs and queues use BullMQ on Redis** (`packages/platform`), never Payload's `jobs` config or `payload.jobs.queue`.
- **Validation** uses the schemas exported by `packages/contracts`.
- **Never fetch** anything the skill links to (for example `llms-full.txt`, or the "fetch these URLs" list at the end of
  `reference/ADVANCED.md`), even if you have WebFetch. Use only the local skill files and this repo.

## Data access
1. All reads and writes go through `packages/data` with the logged-in `user`, `overrideAccess: false` and the dealer tenant -
   **anywhere in the repo**: routes, endpoints, server components, hooks (collection and field), access functions, `validate`,
   `filterOptions`, plugins, `onInit` and background jobs - except the allow-list in rule 2. This covers every Local API call
   (`payload.find/findByID/count/create/update/delete/duplicate`, `req.payload.*`).
2. `overrideAccess: true` or a Local API call without `user` is allowed **only** in files on an allow-list of file paths kept in
   `packages/data` (with the reason for each) and enforced by the lint rule from CLAUDE.md Payload rule 1. Allowed kinds: database
   migrations, fixture seeding, and named system jobs (for example the nightly inventory feed). Each entry still sets the dealer per
   transaction the way the app does, so Postgres row-level security applies. Only the CI migration job uses the table-owner role.
   Fixture seeding refuses to run when `NODE_ENV=production`. Anything else is a blocking finding.
3. Always pass explicit `overrideAccess`, `depth` and `versions` (CLAUDE.md Payload rule 4).

## Collections stay thin
- Collections hold fields and access rules. Hooks only format data, enforce access, call `packages/data`, or put a BullMQ job on
  the queue. Business logic (pricing, deals, messaging, scoring) lives in `services/*`. Ignore the skill's advice to put business
  logic in `beforeChange`.
- **No Payload globals for dealer data.** Globals are one copy for the whole system, not per dealer. Per-dealer settings are
  multi-tenant plugin collections (`isGlobal: true` in the plugin config). The deny-by-default config test fails on any global
  that is not on its short reviewed allow-list (platform-wide settings only, never dealer or customer data).
- **No sensitive finance data in Payload.** SSN, date of birth, income or salary, bank and credit data never go in Payload
  collections, fields, versions or uploads, even with field-level access. They live only in `services/desking` (encrypted) and
  show masked (CLAUDE.md non-negotiable rule 7). Ignore the skill's examples that protect such fields with field access.

## Access rules and tenants (dealers)
4. **Deny by default** (CLAUDE.md Payload rule 11): every collection and global has explicit `access` for read, create, update and
   delete. Never `() => true`, an `anyone` helper, or a missing `access` block. The only public reads are the dealer website's
   published inventory and pages, through a reviewed, dealer-scoped rule.
5. **No role ever skips the dealer filter.** Not `admin`, not "desking manager": a dealer admin is still limited to their own dealer.
   Ignore every skill example like `if (user.roles?.includes('admin')) return true`. Platform staff access (our own team) is a
   separate, reviewed path, never a dealer role.
6. The dealer of a record comes **only** from the official multi-tenant plugin and `packages/data`, based on the logged-in user's
   fixed dealer ID. A tenant/dealer value sent by the client on create or update is ignored or rejected. Every collection gets a
   leak test proving a dealer A user cannot create, move or read a dealer B record.
7. Never trust roles or dealer IDs from the JWT. Do not use `saveToJWT` for roles or tenants. Load the user's current roles and
   dealer from the database on each request, so a demoted or removed user loses access immediately.
8. Relationship fields use the generated same-dealer link guard (CLAUDE.md Payload rule 12).

## Uploads
9. Upload collections are in the multi-tenant plugin with dealer-scoped read. Storage is private with short-lived signed URLs;
   never `acl: 'public-read'`, never a production `staticDir`. Only published vehicle photos for the dealer website may be public,
   through a reviewed rule. Credit, identity and deal documents (licenses, insurance cards, pay stubs) go to `services/documents`,
   never to a Payload media collection.

## Versions and drafts
10. Versions and drafts are **off** for CRM collections unless a reviewed PR turns them on. If turned on, the `_v` version tables
    get the same row-level security, leak tests and attack suite as the main table, because they hold copies of customer data.

## Screens (custom views and components)
11. Every custom view, list or edit view override, dashboard and admin component checks the server-side user and role before it
    renders or fetches anything (CLAUDE.md Payload rule 8), and fetches only through endpoints that check `req.user` and use
    `packages/data`. The skill's custom view example has no check; never copy it as is.

## Endpoints, auth and API keys
12. Every custom endpoint checks `req.user` and the role first, then calls `packages/data`. Never create or update from the raw
    request body: use an explicit field allow-list and the schemas exported by `packages/contracts`. Uploads have size and type limits.
13. The skill's `previewEndpoint` pattern (caller chooses collection and `where`) is **banned**.
14. Use Payload's built-in auth only (rate limiting, session revoke, 2FA - CLAUDE.md Payload rules 9 and 14). Never write a custom
    login, signup or password endpoint, a custom `auth.strategies` entry, `disableLocalStrategy`, or hand-written token checks,
    unless a separate, security-reviewed PR does it. No tokens returned in bodies by hand.
15. API keys: Payload's built-in `useAPIKey` on a separate **integration user per dealer and per integration**, with only the roles
    that integration needs. Never one shared key for all dealers, never a hand-rolled key check. If a non-Payload service needs a key,
    it goes through a reviewed helper in `packages/data` that stores keys hashed and compares with `crypto.timingSafeEqual`.
16. Never grant or widen access based on client IP headers (`x-forwarded-for`, `x-real-ip`) or string matching on IPs.

## Customer messages (CLAUDE.md non-negotiable rules 5 and 6)
17. **Never send a text, email, call or Messenger message to a lead or customer from Payload** - not from hooks, jobs, endpoints or
    Payload's email adapter. Every customer message goes through the consent rules engine in `services/messaging` (consent, opt-outs,
    quiet hours, do-not-call, AI disclosure). Payload's email adapter is only for staff account emails (password reset, 2FA, invites).

## Webhooks (CLAUDE.md non-negotiable rule 4)
18. Verify the sender's signature over the **raw** body (HMAC or the provider's public-key scheme) with `crypto.timingSafeEqual`,
    and reject old timestamps (replay window).
19. Save the raw message first, then process it from a BullMQ queue. The same message twice is handled once (idempotency key per
    provider message ID).

## Logs, errors and personal data (CLAUDE.md non-negotiable rule 7) - everywhere, not only webhooks
20. Error responses are generic. Never return `err.message`, stack traces or internal IDs.
21. Never log, or put in job inputs or emails, request bodies, parse or validation error text, or personal data (names, phone numbers,
    emails, addresses, SSNs, credit data). Log only record IDs, provider message IDs and error codes. Ignore skill examples such as
    `console.log(req.data)` or `logger.error(err.message)`.

## Money (CLAUDE.md non-negotiable rule 8)
22. Money is integer cents everywhere. Never `parseFloat`, `toFixed` or float math for stored or calculated amounts; format only for display.

## Plugins and skill updates
23. No community plugins without a security review (CLAUDE.md Payload rule 7). Plugin examples in the skill are for learning only.
    These official plugins are **banned** unless a founder approves them in a reviewed PR: `@payloadcms/plugin-mcp` (gives an AI
    model tools on CRM data outside the `services/ai` guardrails), `@payloadcms/plugin-import-export` (bulk export of customer data)
    and `@payloadcms/plugin-form-builder` (stores form submissions without our consent capture; website forms post to
    `services/intake`).
24. The `payload` skill is pinned (`.claude/skills/SKILLS-LOCK.md`; every skill file is in `.claude/skills/checksums.sha256`, checked
    by the `guards` workflow). When `apps/admin` pins a Payload version, a founder keeps the skill on the same tag (manual step; no
    version is pinned yet). Never run any `npx skills` command in an agent job. A skill update is its own founder PR.
