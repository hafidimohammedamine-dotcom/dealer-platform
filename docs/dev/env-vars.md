# Environment variables

The template is `.env.example` in the repo root. It lists 26 variables. This page explains each one.
The infra config test in `infra/checks` checks that the template and this list match what it expects.

Placeholders on this page look like `<password>`. Never write a real-looking value in docs, issues, PR comments, logs or chat.

## Status today: all 26 are reserved

Nothing in the repo reads `process.env` yet. This was checked with a search of `apps/`, `services/`, `packages/`,
`infra/` and `scripts/`. So every variable below is **reserved**: named and documented, but no code uses it.
Setting one changes nothing yet.

## Rules for values

- Real values never go in git, in `.env.example`, in issues or PR comments, in logs, or in chat with agents.
- Staging and production values live in **Railway variables**. CI secrets live in **GitHub Actions secrets**.
  (Both are the places the template comment names.)
- `.env` on your computer is for local dev only. It is git-ignored.
- "Secret" below means: anyone holding it can act as us, read data, or send and receive on our accounts.
  Treat anything marked "yes" as secret, even if it looks harmless.

## Variables

| Variable                      | Secret?                      | What it is for                                                      | Used by code today? |
| ----------------------------- | ---------------------------- | ------------------------------------------------------------------- | ------------------- |
| `APP_ENV`                     | No                           | `dev`, `staging` or `production`                                    | No (reserved)       |
| `PAYLOAD_PUBLIC_SERVER_URL`   | No                           | Public address of the admin app, used for links                     | No (reserved)       |
| `DATABASE_URL`                | Yes                          | App connection to Postgres. Under row-level security. See below     | No (reserved)       |
| `MIGRATION_DATABASE_URL`      | Yes                          | Owner connection for the migration job only. See below              | No (reserved)       |
| `DESKING_DATABASE_URL`        | Yes                          | Connection to the encrypted credit and finance schema. See below    | No (reserved)       |
| `REDIS_URL`                   | Yes in production            | Redis for BullMQ queues. Local default has no password              | No (reserved)       |
| `PAYLOAD_SECRET`              | Yes                          | Signs Payload logins. See rotation below                            | No (reserved)       |
| `FIELD_ENCRYPTION_KEY`        | Yes                          | 32-byte key (base64) for sensitive fields at rest. See backup below | No (reserved)       |
| `RESEND_API_KEY`              | Yes                          | Sends email through Resend                                          | No (reserved)       |
| `RESEND_WEBHOOK_SECRET`       | Yes                          | Checks Resend webhooks                                              | No (reserved)       |
| `TELNYX_API_KEY`              | Yes                          | Sends and receives texts through Telnyx                             | No (reserved)       |
| `TELNYX_PUBLIC_KEY`           | No (public key)              | Checks Telnyx webhooks. Keep it in env anyway                       | No (reserved)       |
| `TELNYX_MESSAGING_PROFILE_ID` | No (identifier)              | Telnyx messaging profile to send texts from                         | No (reserved)       |
| `ELEVENLABS_API_KEY`          | Yes                          | ElevenLabs voice                                                    | No (reserved)       |
| `ELEVENLABS_WEBHOOK_SECRET`   | Yes                          | Checks ElevenLabs webhooks                                          | No (reserved)       |
| `ANTHROPIC_API_KEY`           | Yes                          | Claude API for AI replies                                           | No (reserved)       |
| `META_APP_SECRET`             | Yes                          | Checks Meta webhook signatures                                      | No (reserved)       |
| `META_VERIFY_TOKEN`           | Yes                          | Token Meta sends when a webhook is set up                           | No (reserved)       |
| `META_PAGE_ACCESS_TOKEN`      | Yes                          | Messenger page access                                               | No (reserved)       |
| `ROUTEONE_CLIENT_ID`          | No on its own. Keep internal | RouteOne client ID                                                  | No (reserved)       |
| `ROUTEONE_CLIENT_SECRET`      | Yes                          | RouteOne client secret                                              | No (reserved)       |
| `ROUTEONE_WEBHOOK_SECRET`     | Yes                          | Checks RouteOne webhooks                                            | No (reserved)       |
| `DEALERTRACK_CLIENT_ID`       | No on its own. Keep internal | Dealertrack client ID                                               | No (reserved)       |
| `DEALERTRACK_CLIENT_SECRET`   | Yes                          | Dealertrack client secret                                           | No (reserved)       |
| `DEALERTRACK_WEBHOOK_SECRET`  | Yes                          | Checks Dealertrack webhooks                                         | No (reserved)       |
| `SENTRY_DSN`                  | Yes                          | Error tracking. The DSN holds a project key                         | No (reserved)       |

## The three Postgres URLs

Use placeholders in any note. The template uses these role names: `app_user`, `owner_user`, `desking_user`.
Format: `postgres://<role>:<password>@<host>:5432/<database>`

**`DATABASE_URL` (app role)**

- The app connects with this role. **The role must not own the tables.**
- Postgres row-level security on the dealer (tenant) column is the second lock. Every CRM table gets
  `FORCE ROW LEVEL SECURITY`, and the app sets the dealer for each transaction.
- Status: the roles, tables and policies do not exist in this repo yet. The variable is reserved.

**`MIGRATION_DATABASE_URL` (owner role)**

- Only the one migration job in CI uses it, before deploy. It runs schema changes.
- The app never uses it. It is never used at container start.
- Status: there is no migration job in `ci.yml` yet. Planned, not built.

**`DESKING_DATABASE_URL` (credit and finance schema)**

- Connects to the separate encrypted schema owned by `services/desking`. Credit and finance data lives only here,
  never in Payload collections.
- Only `services/desking` uses this URL. Do not reuse the app URL for it.
- Status: reserved. The schema does not exist in this repo yet.

## PAYLOAD_SECRET: rotation

- Changing this value signs everyone out. The template comment says so. Plan for it.
- Tell both founders before you rotate. Rotate on staging first, then production in a quiet window.
- Make the new value with `openssl rand -base64 32`. Write it straight into the Railway variable and the founders'
  password manager. Do not paste it in chat or in an issue.
- Restart the container so it reads the new value. Users sign in again, with 2FA.
- Payload may use this secret for other signed values, such as reset links. Expect those to stop working after rotation.
- Status: this is a manual procedure. No rotation script exists.
- If the secret leaked, follow [Key leak or loss](../runbooks/key-leak-or-loss.md).

## FIELD_ENCRYPTION_KEY: backup

- The key is 32 random bytes, written as base64. Make one with `openssl rand -base64 32`.
- It encrypts sensitive fields at rest. **If it is lost, the encrypted fields cannot be read. There is no recovery.**
- Back it up in at least two places, both outside Railway and outside the repo:
  1. the founders' shared password manager (both founders can open it), and
  2. one sealed offline copy, kept by a founder.
- Check each backup once a quarter by restoring it to staging and decrypting a known fake test value.
  Status: this check is a plan. No tool does it yet.
- **Never rotate this key by swapping the value.** Data encrypted under the old key will not decrypt with the new one.
  Rotation needs a re-encryption step, which is not built yet. See the runbook.
- The same applies to `PAYLOAD_SECRET`: keep a separate backup, as the template comment says.

## Adding a variable

1. Add it to `.env.example` with an empty value. Never add a real value or a real-looking example.
2. Add the name to the expected list in `infra/checks/src/config.test.ts`. That file is owned by devops.
3. Add it to this page, marked as secret or not, with its status.
4. Run `yarn test`. The config test fails if the template and the list do not match.
