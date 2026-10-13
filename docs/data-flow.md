# Data flow: a lead from the provider to the customer

**Status: Planned.** Nothing on this page runs yet. In the repo today, `services/intake`, `services/ai`,
`services/messaging`, `services/voice`, `packages/data` and `apps/admin` are placeholder packages: each one exports only
its name. Payload is not installed in this repo and `packages/contracts` is a placeholder.
The steps below are the design from [CLAUDE.md](../CLAUDE.md). When a step is built, update this page in the same pull
request and change its status here.

For where each kind of data lives, see [Architecture](architecture.md#repo-layout-and-where-data-lives). For the endpoints,
see the [API index](api/README.md).

## The lead path

```
Lead provider ──► webhook or message ──► sender check ──► raw message saved ──► queue (BullMQ on Redis)
                                                                                      │
                                                                                      ▼
                  worker: dedupe + parse
                                                                                      │
                                                                                      ▼
                  opt-out and HELP check (before the AI sees the message)
                     │ STOP or other opt-out: opt-out recorded for all channels, no AI reply
                     │ HELP: the dealer's fixed HELP message
                     ▼ anything else
                  CRM record (Payload, through packages/data)
                                                                                      │
                                                                                      ▼
                  AI reply (guardrails in code)
                                                                                      │
                                                                                      ▼
                  consent, opt-out, do-not-call and quiet-hours check
                                                                                      │
                                                                                      ▼
                  send (Telnyx text, Resend email)
```

1. **A lead arrives.** A provider sends it by webhook or message: ADF/XML, Meta Lead Ads, Messenger, web chat or email.
   (Planned: `services/intake`.)
2. **The sender is checked first.** The endpoint verifies the signature over the raw request bytes, using the secret for
   that provider (see the env names in the [API index](api/README.md)). A request with a stale timestamp, or a message ID or
   nonce it has already seen, is refused. Each sender and IP address is rate limited. A message that fails a check is
   refused.

   The tenant is fixed here too. The verified route (a per-dealer webhook URL or token) maps to a fixed dealer ID, and that
   ID is stored with the raw message. Proving the provider sent a message does not prove which dealer it is for, so the
   dealer is never taken from a field in the message body.

   **Open design question for a founder:** exactly how each provider's route carries the dealer (a URL or a token) is not
   decided yet. (Planned.)

3. **The raw message is saved before anything else.** The message is stored as received, so nothing is lost if parsing
   fails. It holds customer data, so it is encrypted at rest and never written to logs. (Planned.)
4. **The job goes on a queue.** The endpoint answers the provider, and a BullMQ job on Redis (`REDIS_URL`) moves the
   message on to processing. (Planned.)
5. **Duplicates are handled once.** If the same message arrives twice, the second copy is not processed again. (Planned.)
6. **Opt-outs and HELP are checked before the AI sees a message.** Every inbound message on every channel is checked for
   STOP, HELP and any reasonable opt-out wording. (Planned.)
   - An opt-out is recorded at once for all channels: texts, AI calls, marketing and email.
   - The AI does not reply to an opt-out.
   - At most one confirmation text is sent. It has no marketing in it.
   - HELP gets the dealer's fixed HELP message. The AI does not write it.
7. **The CRM record is written through `packages/data`.** The worker runs as a per-dealer system user, a fixed account for
   that dealer. A queue job has no logged-in person, so the worker never passes one. Every read and write goes through the
   one tenant-safe helper, with that user, `overrideAccess: false` and the dealer's tenant. The database also checks the
   dealer, with row-level security on every CRM table. A lead cannot point at another dealer's customer, vehicle or user.
   (Planned.)

   **Open design question for a founder:** how the per-dealer system user is created, limited and rotated is not decided
   yet.

8. **The AI drafts a reply under guardrails.** Claude Haiku writes the reply by default, and Sonnet for hard cases.
   The guardrails are enforced in code, not only in the prompt:
   - The price comes only from inventory.
   - No discounts, approvals, rates or trade values.
   - No SSNs are collected.
   - The AI says it is an AI.
   - A person takes over when the customer asks for one.

   Lead text is untrusted input. It cannot change the AI's instructions or the tools it can use. (Planned: `services/ai`.)

9. **Consent and quiet hours are checked before any text is sent.** A text goes out only when all of these are true:
   - (a) A stored consent record exists for the phone number: who gave it, when, how, and the exact wording. Marketing texts
     need prior express written consent.
   - (b) The customer has not opted out on any channel. A STOP, "stop texting me", or an opt-out by email, Messenger, chat
     or phone takes effect at once and blocks texts, AI calls and marketing on every channel.
   - (c) The number is not on the dealer's do-not-call list, which is kept for 5 years.
   - (d) The number has passed the reassigned-number check since consent was given.
   - (e) It is between 8am and 9pm in the customer's local time. If the time zone is unknown, it must be between 8am and
     9pm in both the dealer's time zone and the phone number's area-code time zone.

   AI voice calls need the same stored prior express consent and the same do-not-call, opt-out and quiet-hours checks.
   If a check fails, nothing is sent. (Planned: `services/messaging`, consent rules engine.)

10. **The text or email is sent and its result comes back by webhook.** Telnyx sends texts and Resend sends email. Delivery
    results come back through the same verified, saved, queued path as step 1. (Planned.)

## What must never be in this path

- Real customer data in fixtures, tests, docs or logs. Use fake data only.
- Secrets in code, logs or messages. Keys are read from environment variables only.
- Sensitive data (SSNs, bank details, credit data) sent by text or email. Credit and finance data lives in a separate
  encrypted schema owned by `services/desking`, never in Payload collections.
- Money as floating point. Amounts are integer cents.

## When a step fails

Runbooks for failures are listed in the [Runbooks index](runbooks/README.md). Four runbooks are planned and not written
yet: texting fails, a lender callback is stuck, the admin is down, and a migration fails. The first, second and fourth are
on the lead path. The admin runbook is outside the lead path.
