# Data flow: a lead from the provider to the customer

**Status: Planned.** Nothing on this page runs yet. In the repo today, `services/intake`, `services/ai`,
`services/messaging`, `services/voice`, `packages/data`, `packages/contracts` and `apps/admin` are placeholder packages:
each one exports only its name. The Payload admin is PR #55 and the shared shapes are contracts PR #52; neither is merged.
The steps below are the design from [CLAUDE.md](../CLAUDE.md). When a step is built, update this page in the same pull
request and change its status here.

For where each kind of data lives, see [Architecture](architecture.md#repo-layout-and-where-data-lives). For the endpoints,
see the [API index](api/README.md).

## The lead path

```
Lead provider ──► webhook or message ──► sender check ──► raw message saved ──► queue (BullMQ on Redis)
                                                                                      │
                                                                                      ▼
                  CRM record (Payload, through packages/data) ◄── dedupe + parse ◄── worker
                                                                                      │
                                                                                      ▼
                  AI reply (guardrails in code) ──► consent and quiet-hours check ──► send (Telnyx text, Resend email)
```

1. **A lead arrives.** A provider sends it by webhook or message: ADF/XML, Meta Lead Ads, Messenger, web chat or email.
   (Planned: `services/intake`.)
2. **The sender is checked first.** The endpoint verifies that the sender is who it says it is, using the secret for that
   provider (see the env names in [API index](api/README.md)). A message that fails the check is refused. (Planned.)
3. **The raw message is saved before anything else.** The message is stored as received, so nothing is lost if parsing
   fails. It holds customer data, so it is encrypted at rest and never written to logs. (Planned.)
4. **The job goes on a queue.** The endpoint answers the provider, and a BullMQ job on Redis (`REDIS_URL`) moves the
   message on to processing. (Planned.)
5. **Duplicates are handled once.** If the same message arrives twice, the second copy is not processed again. (Planned.)
6. **The CRM record is written through `packages/data`.** Every read and write goes through the one tenant-safe helper. It
   passes the logged-in user, `overrideAccess: false` and the dealer's tenant. The database also checks the dealer, with
   row-level security on every CRM table. A lead cannot point at another dealer's customer, vehicle or user. (Planned.)
7. **The AI drafts a reply under guardrails.** Claude Haiku writes the reply by default, and Sonnet for hard cases.
   The guardrails are enforced in code, not only in the prompt:
   - The price comes only from inventory.
   - No discounts, approvals, rates or trade values.
   - No SSNs are collected.
   - The AI says it is an AI.
   - A person takes over when the customer asks for one.

   Lead text is untrusted input. It cannot change the AI's instructions or the tools it can use. (Planned: `services/ai`.)

8. **Consent and quiet hours are checked before any text is sent.** A text goes out only when all of these are true:
   - The customer gave written consent to text.
   - The customer has not opted out. A STOP, or an opt-out in any reasonable way, works at once.
   - It is between 8am and 9pm in the customer's local time. If the time zone is unknown, it must be between 8am and 9pm
     in both the dealer's time zone and the phone number's area-code time zone.

   Do-not-call records are kept for 5 years. AI voice calls need prior express consent. If a check fails, nothing is sent. (Planned:
   `services/messaging`, consent rules engine.)

9. **The text or email is sent and its result comes back by webhook.** Telnyx sends texts and Resend sends email. Delivery
   results come back through the same verified, saved, queued path as step 1. (Planned.)

## What must never be in this path

- Real customer data in fixtures, tests, docs or logs. Use fake data only.
- Secrets in code, logs or messages. Keys are read from environment variables only.
- Sensitive data (SSNs, bank details, credit data) sent by text or email. Credit and finance data lives in a separate
  encrypted schema owned by `services/desking`, never in Payload collections.
- Money as floating point. Amounts are integer cents.

## When a step fails

Runbooks for failures are listed in the [Runbooks index](runbooks/README.md). Texting, lender callbacks and migrations
have no runbook yet (Planned).
