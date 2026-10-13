# API: dealers, users and login (Payload 3.90.2)

Status: **slice 1 (issue #5)**. Only the `dealers` and `users` collections exist. No customer, lead or credit data is
stored, and a CI test stops any such collection from being added until 2FA (issue #57), row-level security
(issue #58) and the durable audit table (issue #71) are in place. A second CI test fails while 2FA (issue #57) or the login
surface (issue #73) is missing if the admin app has any HTTP entry point (a Next.js `app/` or `pages/` file, a
middleware, proxy, server, instrumentation or `next.config` file, or code that imports `@payloadcms/next` or `next`), so the
app is not reachable over HTTP yet. Nothing here is live for dealers yet. The routes below describe what the app will
answer once those gates are closed. The access rules below come from the code in
`apps/admin/src/tenants/` and were checked against the Payload 3.90.2 source in `node_modules/payload/dist`.

**What is tested, and what is not.** The access functions, the write guards and the audit hooks have unit tests,
including dealer A against dealer B (`apps/admin/src/tenants/two-dealers.test.ts`). The generated attack suite against a
running server with real Postgres (REST, GraphQL, `/count`, bulk, `/duplicate`, `depth`) is the tester's issue #60 and is
**not built yet**. Treat the table below as the intended behavior until #60 proves it.

Base path: `/api`. GraphQL: `/api/graphql`. All routes need a login (cookie) except the ones marked "no login".

## Roles

`admin` (a dealer's own administrator), `desking_manager`, `sales_rep`, `bdc`. The role is a single field on the user, not
per dealer. Nobody has access across dealers, not even an admin (`userHasAccessToAllTenants` is always false). A
deactivated user (`active` is false) has no role, so every rule below says no.

## Dealers (`/api/dealers`)

| Action                                 | Who                    | Limit                                                                     |
| -------------------------------------- | ---------------------- | ------------------------------------------------------------------------- |
| Read list, read by ID, `/count`        | Any signed-in role     | Only dealers on the user's list                                           |
| Update by ID or in bulk                | `admin`                | Only dealers on the user's list                                           |
| Create, delete, `/duplicate`, versions | Nobody through the API | Onboarding is a reviewed job                                              |
| Change `slug`                          | Nobody through the API | The reviewed onboarding job sets it; it cannot be changed through the API |

Every dealer create or update is written to the access audit log; the entry records only the dealer's name (before and
after).

## Users (`/api/users`)

| Action                          | Who                      | Limit                                                                                             |
| ------------------------------- | ------------------------ | ------------------------------------------------------------------------------------------------- |
| Read list, read by ID, `/count` | Any signed-in role       | Yourself, and users who work for one of your dealers                                              |
| Create                          | `admin`                  | At least one dealer, all of them the admin's own. Email is set here and cannot be changed later   |
| Update                          | `admin`                  | Only users whose dealers are **all** the admin's own dealers; new dealers must be the admin's own |
| Update                          | Any other signed-in role | Yourself only. Role, active and dealers cannot be changed by the user                             |
| Delete, unlock, versions        | Nobody through the API   | Users are deactivated (`active` false), never deleted. Unlocking is a system job                  |
| Change `role`, `active`         | `admin`                  | Same limit as Update                                                                              |

Every write to a user with no logged-in user is refused, which also closes `POST /api/users/first-register`. There is no
request flag that lifts this. The first admin of a dealer will be created by a reviewed system job listed in
`packages/data/override-allowlist.txt` (issue #36; not built yet).

`where` and `sort` on users may not name the dealer rows (`tenants`, `tenants.tenant`, `tenants.tenant.name` and so on):
the answer is `403`. The list is already limited to your dealers, and such a filter could only probe other dealers.

Creating a user sends a verification email; the user cannot log in before verifying. A duplicate or invalid email gets a
generic error. Other fields keep their own messages. Whether a create succeeds still shows that an email is free, so an
admin who tries addresses one by one can learn which ones exist at another dealer. Successful creates are audited; refused
or invalid creates are **not** audited yet, and there is no create rate limit yet: both come with the login surface
(issue #73), and the app has no HTTP route until then. An invite flow would remove this fully (not built).

**Passwords.** Checked when an admin creates a user: at least 12 and at most 128 characters, not a common password (a
built-in list, also with digits or symbols on the ends), not one short piece repeated, and not containing the name part of
the user's email when that name part is 4 or more characters long. Payload 3.90.2 checks nothing about strength by itself,
so the rule is ours (`password-policy.ts`). Nobody sets another person's password and nobody changes their own by editing
the user: an update that carries `password` is refused (`403`). **Forgot-password and reset-password are closed** (`403`)
until issue #73, which brings them back with the same password rule and a `user.password_change` audit entry written only
after the change succeeds. A check against a list of breached passwords is a follow-up.

**Rate limits and the client IP are not built** (issue #73: Redis-backed limits per address and per email, a client IP
from a source a founder confirms for Railway). Today only Payload's own account lock applies: 5 failed tries lock that
account for 10 minutes. The app has no HTTP route until #73 is done, so nothing can be tried from outside.

## Login and session routes (`/api/users/...`)

| Route                                                      | Notes                                                                                                                                                                                                                       |
| ---------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `POST /login` (no login)                                   | Payload's built-in login: 5 failed tries lock the account for 10 minutes; a deactivated user is refused. **No second factor (issue #57) and no rate limits (issue #73) yet.**                                               |
| `POST /logout`, `GET /me`, `POST /refresh-token`           | Sessions are on (`useSessions`); the token lasts 2 hours. Cookies are `Secure` and `SameSite=Strict` in staging and production. Deactivating a user ends all of that user's sessions, and a deactivated user cannot refresh |
| `POST /forgot-password`, `POST /reset-password` (no login) | Closed: `403` for everyone until issue #73                                                                                                                                                                                  |
| `GET /verify/:token` (no login)                            | Email verification                                                                                                                                                                                                          |
| `POST /unlock`                                             | Closed to everyone through the API                                                                                                                                                                                          |
| `POST /first-register` (no login)                          | Refused by the user write guard (see above)                                                                                                                                                                                 |
| `GET /access`, `GET /init`                                 | Payload's own routes, covered by issue #60                                                                                                                                                                                  |

API keys are **not** enabled on any collection.

## Examples (fake data)

Replace `$DEALER_A` and the other IDs with real IDs from your own staging data. `-b cookies.txt` sends the login cookie.
These are the intended answers; the test against a running server is issue #60.

```bash
# Log in (the cookie is saved). A wrong password returns 401; the sixth try in a row on one account returns a locked answer.
curl -c cookies.txt -H 'Content-Type: application/json' \
  -d '{"email":"rep@dealer-a.example","password":"a-long-fake-password-1"}' https://staging.example.test/api/users/login

# Who am I, refresh the token, log out
curl -b cookies.txt https://staging.example.test/api/users/me
curl -b cookies.txt -X POST https://staging.example.test/api/users/refresh-token
curl -b cookies.txt -X POST https://staging.example.test/api/users/logout

# Dealers: list (own dealers only), read one, rename (admin only)
curl -b cookies.txt 'https://staging.example.test/api/dealers?limit=10&depth=0'
curl -b cookies.txt https://staging.example.test/api/dealers/$DEALER_A
curl -b cookies.txt -X PATCH -H 'Content-Type: application/json' -d '{"name":"Dealer A Motors"}' \
  https://staging.example.test/api/dealers/$DEALER_A

# Users: list (yourself and your dealers' people), read one
curl -b cookies.txt 'https://staging.example.test/api/users?limit=10&depth=0'
curl -b cookies.txt https://staging.example.test/api/users/$USER_ID

# Create a user (admin only): one or more of the admin's own dealers; a verification email is sent
curl -b cookies.txt -H 'Content-Type: application/json' -d '{
  "email":"new.rep@dealer-a.example","password":"another-long-fake-password","role":"sales_rep",
  "tenants":[{"tenant":"'$DEALER_A'"}]}' https://staging.example.test/api/users

# Deactivate a user (admin only). Users are never deleted
curl -b cookies.txt -X PATCH -H 'Content-Type: application/json' -d '{"active":false}' \
  https://staging.example.test/api/users/$USER_ID

# Verify an email (no login): the link in the verification email
curl https://staging.example.test/api/users/verify/TOKEN-FROM-THE-EMAIL
```

Refused on purpose, for every role:

```bash
# Unlock: closed (a system job does it)
curl -b cookies.txt -X POST -H 'Content-Type: application/json' -d '{"email":"rep@dealer-a.example"}' \
  https://staging.example.test/api/users/unlock          # 403
# Delete a user or a dealer
curl -b cookies.txt -X DELETE https://staging.example.test/api/users/$USER_ID      # 403
curl -b cookies.txt -X DELETE https://staging.example.test/api/dealers/$DEALER_A   # 403
# Forgot and reset password: closed until issue #73
curl -H 'Content-Type: application/json' -d '{"email":"rep@dealer-a.example"}' \
  https://staging.example.test/api/users/forgot-password   # 403
# Filter users through their dealer rows
curl -b cookies.txt 'https://staging.example.test/api/users?where[tenants.tenant.name][like]=Dealer'   # 403
# Set a password by editing a user
curl -b cookies.txt -X PATCH -H 'Content-Type: application/json' -d '{"password":"a-new-long-fake-password"}' \
  https://staging.example.test/api/users/$USER_ID        # 403
```

## GraphQL

`/api/graphql` uses the same access functions as REST for `dealers` and `users`. The playground is off in production.

## Audit log

These write one JSON line (`{"audit": {...}}`) to the app's log stream: creating a user; changing a user's role, `active`,
email or dealer list; and every dealer create or update. Each entry has who (`actorId`), what, which record, the dealers,
the before and after values of those fields (for a dealer, only the name), and a UTC time. Passwords, tokens and similar
keys are removed before writing.

All of these entries **fail closed**: they are written inside the change, and if the write fails the change fails.

Not audited yet, all in issue #73: successful logins, logouts and token refreshes, failed logins, attempts on a locked
account, and refused or invalid writes. The app has no HTTP route until #73 is done.

Entries are append-only in code (`packages/platform/src/audit.ts`). The durable, append-only database table with its own
retention period is issue #71 (the `auditStore` gate in `readiness.ts` blocks customer data until it exists), and the
retention period is waiting for the lawyer. Until then the log stream on Railway is the only copy.
