# Runbook: PAYLOAD_SECRET or FIELD_ENCRYPTION_KEY leaked or lost

**Status: partly planned.** Both keys are reserved environment variables, and no code reads them yet. There is no
rotation script, no re-encryption tool, no key version field and no backup check. Steps marked **(not built)** need
tooling that does not exist yet. Do the rest by hand, and tell the founders which parts you could not do.

**Who to tell, in this order:**

1. Both founders, right away, in a private channel. Not in an issue, a PR comment or a chat with an agent.
2. Devops, who owns environment variables and hosting.
3. The security reviewer, for the fix and the review of how it leaked.
4. Compliance and your lawyer, who decide whether any dealer or customer must be told. Do not contact dealers yourself
   before the founders decide.

## What the two keys protect

- **`PAYLOAD_SECRET`** signs Payload logins. Anyone who has it may be able to forge a login.
- **`FIELD_ENCRYPTION_KEY`** encrypts sensitive fields at rest (`CLAUDE.md`, non-negotiable rule 7). Someone with the key
  and a copy of the database can read those fields. If the key is lost, the fields cannot be read at all.

## Detect

Signs of a leak:

- The CI secret scan (gitleaks) fails on a pull request or a push. See the [CI runbook](ci-pipeline.md).
- A provider or GitHub alert about a secret, if one is enabled for the repo.
- A key shows up where it should not be: an issue, a PR comment, a log, a screenshot, or a chat.
- Logins you cannot explain, in the admin log, if you can see one.

Signs of a loss:

- Staging or production will not start, or a key reads as empty. This needs code that reads the key, which is not built.
- Decrypt errors. Nothing logs these yet (not built).
- Nobody can find the backup of the key.

**Check that a variable is set without printing it.** For example, check that it is not empty. Never `echo` a key, and never
run `printenv` where the output goes to a log, a shared terminal or a screenshot.

## Leak: PAYLOAD_SECRET

1. Tell both founders now. Do not wait for a reply before rotating: a leaked login key is fixed by rotating it.
2. Make a new value with `openssl rand -base64 32`. Write it straight into the Railway variable and the founders' password
   manager. Do not paste it anywhere else.
3. Set the new value on **staging** first. Restart staging. Check that you can sign in with 2FA.
4. Set the new value on **production**. Restart production. Everyone signs out. This is expected.
5. Sessions made with the old value stop working when the new value is read. There is no tool to list or end sessions one
   by one (not built).
6. Look at the admin log for logins from the time of the leak until the rotation. This is a manual check for now.
7. Write a short note for the founders: what leaked, where, when, and who could see it. Do not include the key value.
   The security reviewer checks the note before the incident is closed.

## Leak: FIELD_ENCRYPTION_KEY

This one is harder. Data encrypted under the old key stays readable to anyone who has both the old key and a database copy.

1. Tell both founders now, the same day.
2. Limit who can read the Railway variables and the password manager entry for the key.
3. **Do not just replace the value.** Data encrypted under the old key will not decrypt with the new key.
4. Re-encrypt every sensitive field from the old key to the new key, in batches, with a tool that can read both keys during
   the change (**not built**). Until that tool exists, a leaked `FIELD_ENCRYPTION_KEY` needs a founder decision on whether
   to hold the change until re-encryption can be done.
5. Old database backups still hold data encrypted under the old key. Treat them as just as sensitive as the key. Ask the
   founders how long they are kept (retention is not set in this repo yet).
6. Compliance and your lawyer decide on any notice to dealers or customers.
7. The security reviewer checks the fix and the note before the incident is closed.

## Loss: FIELD_ENCRYPTION_KEY

1. Tell both founders now.
2. Look for the backups: the founders' password manager entry, then the sealed offline copy (see
   [Environment variables](../dev/env-vars.md)).
3. If a backup exists, restore it to **staging** first. Check that it decrypts a known fake test value. Then do production.
   Restoring the key is not built as a script, so this is a manual step.
4. If no backup exists, the encrypted fields are gone. Do not invent a new key and carry on as if nothing happened. Tell
   the founders. They, with compliance and your lawyer, decide what to say to dealers. The app would also need to handle
   missing values, which is not built.

## Loss: PAYLOAD_SECRET

Less serious. A new value signs everyone out, but no data is lost. Follow the steps in "Leak: PAYLOAD_SECRET" without the
note in step 7. Keep the backup in the same password manager entry as the rest of the secrets.

## What not to do

- **Never paste a key, or part of a key, into a GitHub issue, a PR comment, a commit message, a log, a screenshot or a chat
  with an agent.**
- Never commit a key, even to a branch you plan to delete. A committed key stays in git history.
- Do not rotate `FIELD_ENCRYPTION_KEY` by replacing the value. See the leak steps above.
- Do not rewrite git history to remove a leaked key unless a founder decides to. Rewriting history does not un-leak the key.
- Do not add an ignore rule to hide a secret-scan hit. Ask a founder with `REQUEST:`. The key is still leaked.
- Do not use the owner URL (`MIGRATION_DATABASE_URL`) to check a key or to debug. It is for the migration job only.

## After the incident

- Update where the key lives (Railway, the password manager, the offline copy) and write down the date it changed.
- Check that the backups still restore, once the new key is in place.
- The security reviewer signs off on the write-up before the issue is closed.
