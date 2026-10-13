# Runbook: the admin app is down

Status: **not built yet.** The admin app is not deployed (it has no routes yet, and 2FA, issue #57, must exist before it is
reachable). This page is a stub for the first deploy. Owner: devops.

## What will exist at the first deploy

- A health check on the Railway container (always-on, not serverless) and an alert to both founders.
- Error tracking on the app.

## Steps (draft)

1. Open the Railway project for the environment (`staging` or `production`). Check the deployment status and the last
   deploy time.
2. Read the container log. The app refuses to start when `APP_ENV`, `PAYLOAD_SECRET` (32 or more characters), `DATABASE_URL`
   or `PAYLOAD_PUBLIC_SERVER_URL` is missing or wrong, and outside dev when `EMAIL_FROM` or `RESEND_API_KEY` is missing. The log
   names the variable, never its value.
3. If the last deploy broke it, roll back to the previous deployment in Railway (production: a founder does it).
4. If the database is the problem, check Postgres in Railway. Do not restart it without a founder.
5. After `PAYLOAD_SECRET` was rotated, everyone is signed out. That is expected, not an outage.

## Not built yet

- Health check endpoint, alerts and error tracking.
- The rollback plan for production deploys.
