# API: dealers, users and login (Payload 3.90.2)

Status: **slice 1 (issue #5)**. Only the `dealers` and `users` collections exist. No customer, lead or credit data is
stored, and a CI test stops any such collection from being added until 2FA (issue #57) and row-level security
(issue #58) are in place. Nothing here is live for dealers yet. The access rules below come from the code in
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

| Action                                 | Who                    | Limit                           |
| -------------------------------------- | ---------------------- | ------------------------------- |
| Read list, read by ID, `/count`        | Any signed-in role     | Only dealers on the user's list |
| Update by ID or in bulk                | `admin`                | Only dealers on the user's list |
| Create, delete, `/duplicate`, versions | Nobody through the API | Onboarding is a reviewed job    |
| Change `slug`                          | Nobody through the API | The field is create-only        |

Every change to a dealer's name is written to the access audit log.

## Users (`/api/users`)

| Action                          | Who                      | Limit                                                                                             |
| ------------------------------- | ------------------------ | ------------------------------------------------------------------------------------------------- |
| Read list, read by ID, `/count` | Any signed-in role       | Yourself, and users who work for one of your dealers                                              |
| Create                          | `admin`                  | At least one dealer, all of them the admin's own. Email is set here and cannot be changed later   |
| Update                          | `admin`                  | Only users whose dealers are **all** the admin's own dealers; new dealers must be the admin's own |
| Update                          | Any other signed-in role | Yourself only. Role, active and dealers cannot be changed by the user                             |
| Delete, unlock, versions        | Nobody through the API   | Users are deactivated (`active` false), never deleted. Unlocking is a system job                  |
| Change `role`, `active`         | `admin`                  | Same limit as Update                                                                              |

Creating a user with no logged-in admin is refused, which also closes `POST /api/users/first-register`. The first admin
of a dealer is created by a reviewed system job that sets the `reviewedSystemJob` request context (not built yet).

Creating a user sends a verification email; the user cannot log in before verifying. A duplicate email gives the same
generic error as any other bad input, so an admin cannot learn which emails exist at other dealers.

## Login and session routes (`/api/users/...`)

| Route                                                      | Notes                                                                                                                                          |
| ---------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| `POST /login` (no login)                                   | Payload's built-in login: 5 failed tries lock the account for 10 minutes; a deactivated user is refused. **No second factor yet (issue #57).** |
| `POST /logout`, `GET /me`, `POST /refresh-token`           | Sessions are on (`useSessions`); the token lasts 2 hours. Cookies are `Secure` and `SameSite=Strict` in staging and production                 |
| `POST /forgot-password`, `POST /reset-password` (no login) | Emails go through Resend (required outside dev). The forgot-password answer does not say whether the email exists                              |
| `GET /verify/:token` (no login)                            | Email verification                                                                                                                             |
| `POST /unlock`                                             | Closed to everyone through the API                                                                                                             |
| `POST /first-register` (no login)                          | Refused by the user write guard (see above)                                                                                                    |
| `GET /access`, `GET /init`                                 | Payload's own routes, covered by issue #60                                                                                                     |

API keys are **not** enabled on any collection.

## GraphQL

`/api/graphql` uses the same access functions as REST for `dealers` and `users`. The playground is off in production.

## Audit log

Creating a user, changing a role, `active` or dealer list, and editing a dealer write one JSON line
(`{"audit": {...}}`) to the app's log stream: who (`actorId`), what, which record, the dealers, before and after values
of `role`, `active`, email and dealer IDs, and a UTC time. Passwords, tokens and similar keys are removed before writing.
If the audit write fails, the change fails. Entries are append-only in code (`packages/platform/src/audit.ts`); a database
table with its own retention period is a follow-up, and the retention rule is waiting for the lawyer.
