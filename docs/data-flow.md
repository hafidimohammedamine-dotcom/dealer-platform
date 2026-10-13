# Data flow: a lead from the provider to the customer

**Status: Planned.** Nothing on this page runs yet. In the repo today, `services/intake`, `services/ai`,
`services/messaging`, `services/voice`, `packages/data` and `apps/admin` are Reserved placeholder packages: each one
exports only its name. Payload is not installed in this repo, and `packages/contracts` is a Reserved placeholder.

The steps follow [CLAUDE.md](../CLAUDE.md) plus proposed review additions. A review addition is marked
"review addition (proposed, pending ... approval)" and is not a rule until the named team approves it. Decisions that are
not made yet are listed in [Open questions](#open-questions). When a step is built, update this page in the same pull
request and change its status here.

For where each kind of data lives, see [Architecture](architecture.md#repo-layout-and-where-data-lives). For the endpoints,
see the [API index](api/README.md).

## The lead path

```
                  Lead provider: ADF/XML, Meta Lead Ads, Messenger, web chat or email
                  │
                  ▼
                  Sender check, dealer binding, replay and rate-limit checks
                  │   a failed check is refused, and nothing is saved
                  ▼
                  Raw message saved, encrypted, with the dealer ID
                  │
                  ▼
                  Queue: BullMQ on Redis (REDIS_URL)
                  │
                  ▼
                  Worker: dedupe, then parse
                  │
                  ▼
                  Detect and mask sensitive data (review addition, proposed)
                  │   SSN, DOB, bank or income data: masked text goes on
                  │   the original stays only in the encrypted raw store or services/desking
                  ▼
                  Opt-out and HELP check (before the AI sees the message)
                  │   STOP or other opt-out: takes effect at once, no AI reply
                  │   HELP: the dealer's fixed HELP message
                  ▼   anything else
                  CRM record (Payload, through packages/data)
                  │
                  ▼
                  AI reply (guardrails in code; sees masked text only)
                  │
                  ▼
                  Texting checks: CLAUDE.md rule 6, plus review additions
                  │   if a check fails, nothing is sent
                  ▼
                  Send: Telnyx text, Resend email, Messenger reply (24-hour rule)
```

1. **A lead arrives.** A provider sends it by webhook or message: ADF/XML, Meta Lead Ads, Messenger, web chat or email.
   (Planned. Runs in `services/intake`, a Reserved placeholder.)

2. **The sender is checked first.** The endpoint runs the checks in
   [API rules 1 to 4](api/README.md#rules-every-endpoint-and-webhook-must-follow): the signature, or the channel-specific
   check listed in the API index, then the replay check, the rate limit and the dealer binding. A request that fails any
   check is refused. (Planned. The replay and rate-limit checks are a review addition, proposed, pending security
   approval.)

   **Open design question for founders and security:** for each provider, how the dealer is bound (a per-dealer secret
   that is not in the URL, or a signed body field looked up in a mapping table). Not decided. See
   [Open questions](#open-questions).

3. **The raw message is saved before parsing.** The message is stored as received, with the fixed dealer ID, so nothing
   is lost if parsing fails. It holds customer data, so it is encrypted at rest and never written to logs. (Planned.)

4. **The job goes on a queue.** The endpoint answers the provider, and a BullMQ job on Redis (`REDIS_URL`) moves the
   message on to processing. (Planned.)

5. **Duplicates are handled once, then the worker parses.** If the same message arrives twice, the second copy is not
   processed again. Parsing of XML is safe as set in [API rule 8](api/README.md#rules-every-endpoint-and-webhook-must-follow).
   (Planned.)

6. **Sensitive data is detected and masked before the CRM or the AI sees it.** The worker looks for SSN, date of birth,
   bank account and income data in the inbound text and masks each one. The CRM and the AI get only the masked text. The
   original stays only in the encrypted raw store or in the `services/desking` schema, and each detection writes an audit
   entry. The AI is told only that sensitive data was received.
   (Planned.) _Review addition (proposed, pending security approval)._ How detection works and what the mask looks like
   are not decided. See [Open questions](#open-questions).

7. **Opt-outs and HELP are checked before the AI sees a message.** Every inbound message on every channel is checked for
   opt-out wording, as [CLAUDE.md](../CLAUDE.md) rule 6 requires. (Planned.)
   - An opt-out takes effect at once (CLAUDE.md rule 6). Which channels it covers, and whether it stops transactional or
     deal-required notices, is an open question for compliance.
   - The AI does not reply to an opt-out. _Review addition (proposed, pending compliance approval)._
   - At most one confirmation text is sent after an opt-out, and it has no marketing in it. _Review addition (proposed,
     pending compliance approval). The limit is an open question._
   - HELP gets the dealer's fixed HELP message, and the AI does not write it. _Review addition (proposed, pending
     compliance approval)._

8. **The CRM record is written through `packages/data`.** Every read and write uses the one tenant-safe helper, which
   passes the logged-in user, `overrideAccess: false` and the dealer's tenant ([CLAUDE.md](../CLAUDE.md), Payload rule 1).
   The database also checks the dealer, with row-level security on every CRM table (Payload rule 2). A lead cannot point at
   another dealer's customer, vehicle or user (Payload rule 12). (Planned.)

   **The worker's identity is planned and undecided.** Whether `packages/data` accepts a per-dealer system user is a
   founder and security decision. _Review addition (proposed, pending founder and security approval)._ Until it is
   decided, no worker writes to the CRM.

9. **The AI drafts a reply under guardrails.** Claude Haiku writes the reply by default, and Sonnet for hard cases. The
   guardrails in [CLAUDE.md](../CLAUDE.md) non-negotiable rule 5 are enforced in code, not only in the prompt. Lead text
   is untrusted input. It cannot change the AI's instructions or the tools it can use. (Planned. Runs in `services/ai`.
   The masked-text input is a review addition, proposed, from step 6.)

10. **Texting checks run before any text is sent.** Every check in [CLAUDE.md](../CLAUDE.md) non-negotiable rule 6 must
    pass: written consent, opt-out, do-not-call and quiet hours. The additions below are review additions. If any check
    fails, nothing is sent. (Planned. Runs in `services/messaging`, the consent rules engine.)
    - (a) A stored prior express written consent record exists for the phone number (who gave it, when, how, the exact
      wording). Written consent is required before any text, marketing or not (CLAUDE.md non-negotiable rule 6).
      _Review addition (proposed, pending compliance approval): the four record fields._
    - (b) The customer has not opted out (CLAUDE.md rule 6).
    - (c) The number is not on the dealer's do-not-call list, which is kept for 5 years (CLAUDE.md rule 6).
    - (d) The number has passed a reassigned-number check since consent was given. _Review addition (proposed, pending
      compliance approval). How and when the check runs is not decided._
    - (e) It is within the quiet hours in CLAUDE.md rule 6, in the customer's local time. Stricter state windows are an
      open question for compliance.
    - (f) The first text after consent is the dealer's fixed opt-in message. It states the dealer name, message frequency,
      "Msg & data rates may apply" and "Reply STOP to opt out, HELP for help", and the stored opt-in wording includes these
      items. _Review addition (proposed, pending compliance approval)._

    **AI voice calls** follow the same kind of gate. _Review addition (proposed, pending compliance approval)._ An AI call
    goes out only after a stored prior express written consent record exists (who gave it, when, how, the exact wording),
    and after the do-not-call, opt-out and quiet-hours checks. CLAUDE.md rule 6 requires prior express consent for AI voice
    calls, so this is a stricter requirement, not a change to it.

11. **The message is sent, and the result comes back by webhook.** Telnyx sends texts and Resend sends email. Delivery
    results come back through the same verified, saved and queued path as step 1 (CLAUDE.md non-negotiable rule 4).
    (Planned.)
    - _Review addition (proposed, pending compliance approval):_ a Messenger reply goes out only inside 24 hours of the
      customer's last message. After that, only a real person may reply, with the `human_agent` tag, within 7 days. The AI
      never uses that tag.
    - Web chat reply timing is not decided. See [Open questions](#open-questions).

## What must never be in this path

- Real customer data in fixtures, tests, docs or logs. Use fake data only.
- Secrets in code, logs or messages. Keys are read from environment variables only.
- Sensitive data (SSNs, bank details, credit data) sent by text or email. Credit and finance data lives in a separate
  encrypted schema owned by `services/desking`, never in Payload collections.
- Money as floating point. Amounts are integer cents.

## When a step fails

Runbooks for failures are listed in the [Runbooks index](runbooks/README.md). On this path, the texting runbook (texting
fails) is planned and not written yet. The lender callback, admin down and migration runbooks are also planned and not
written. They are outside the lead path.

## Open questions

None of these is decided. Each one needs the named team. Nothing marked proposed above is approved until it is answered.

For founders and security:

- **Worker identity (step 8).** Does `packages/data` accept a per-dealer system user? If so, how are such users created,
  limited and rotated?
- **Dealer binding (step 2).** For each provider, is the dealer bound by a per-dealer secret not in the URL, or by a signed
  body field looked up in a mapping table? Where does the mapping table live?
- **Sensitive-data detection (step 6).** How does detection work (rules, a model, or both)? What does the mask look like,
  and where is the audit entry kept?
- **Web chat sender check (step 2).** A widget key with an Origin allow-list, rate limits and CAPTCHA?
- **ADF email sender check (step 2).** A per-dealer inbound address with SPF, DKIM and DMARC checks?

For compliance:

- **Written-consent record (step 10a).** Which system stores it, and who can read it?
- **Reassigned-number check (step 10d).** How is it run, and when is it run again?
- **Web chat reply timing (step 11).** Is there a reply window for web chat, and what is it?

Questions from the lawyer review, for compliance and the founders. They are not answered on this page.

- Can one confirmation text be sent after a non-text opt-out? Should this page state the FCC 5-minute limit? Is one
  clarifying text allowed when the scope of an opt-out is unclear?
- Should quiet hours also follow stricter state windows (for example, Florida 8am to 8pm), based on where the customer
  lives?
- Should a National Do Not Call Registry check apply to AI calls and marketing texts?
- After a marketing opt-out, can transactional or deal-required notices still go out, and on which channel?
