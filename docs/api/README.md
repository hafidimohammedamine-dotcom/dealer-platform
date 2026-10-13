# API index

**Status: nothing is built yet.** No endpoint or webhook exists in the repo. Payload is not installed in this repo, and
the services and the admin app are Reserved placeholders (see [Architecture](../architecture.md)). Status words are
defined in [Docs home](../README.md#status-words). This page lists what is planned, so that each entry gets its own page
here when it is built.

## Rules every endpoint and webhook must follow

Each rule says where it comes from:

- **CLAUDE.md** means a company rule. The number is the rule number in [CLAUDE.md](../../CLAUDE.md).
- **Proposed** means a review addition. It is not approved yet. It needs founder and security approval before it is
  treated as a rule. The decisions are listed in [Open questions](#open-questions).

1. **Verify the sender before parsing.** _CLAUDE.md, non-negotiable rule 4._ Check the signature or secret for that
   provider over the raw request bytes, before the body is parsed. For a channel with no approved check (web chat and
   ADF email today), use the channel-specific check listed in the table below, once it is approved. A request that
   fails the check is refused.
2. **Refuse replays.** _Proposed (pending founder and security approval)._ A signed request with a timestamp outside the
   window set for that provider is refused. A message ID or nonce already seen inside that window is refused too. The
   replay store is global: one store shared by all dealers, so a replay cannot pass by naming a different dealer. Window
   lengths are not set.
3. **Rate limit.** _Proposed (pending founder and security approval)._ Limit requests per sender and per IP address. A
   request over the limit is refused before it is saved or queued. Limits are not set.
4. **Filter by dealer.** _CLAUDE.md, non-negotiable rule 3, for every query and write. How a webhook finds its dealer is
   proposed (pending founder and security approval)._ The dealer is never taken from a bare URL path segment, because no
   provider signature covers it. The dealer is bound in one of these ways:
   - a per-dealer secret that is not in the URL, mapped to a fixed dealer ID; or
   - a signed body field (for example Meta's `page_id`, Telnyx's `to` number or an agent ID), looked up in a mapping
     table.

   If a route and a body field both exist, they must agree, or the request is refused. Every query and write is limited to
   that dealer's tenant.

5. **Save the raw message before parsing.** _CLAUDE.md, non-negotiable rule 4._ Store what arrived, with the dealer it was
   routed to, before any parsing. The raw store is encrypted at rest and never logged.
6. **Process from a queue.** _CLAUDE.md, non-negotiable rule 4._ The endpoint answers, and a BullMQ job does the work.
7. **Handle a repeat once.** _CLAUDE.md, non-negotiable rule 4._ The same message sent twice is processed one time.
8. **Parse XML safely.** _Proposed (pending security approval)._ XML from lead providers is parsed in the job, after the
   raw save and the queue, with DTDs and external entities turned off. A document cannot read local files or make the
   server call other hosts.
9. **Check login and role on every non-webhook endpoint.** _CLAUDE.md, Payload rule 8, for custom views. Applying the
   same check to every non-webhook endpoint is proposed (pending founder and security approval)._ An endpoint that is not
   a webhook (for example, a staff screen or an API route used by staff) checks that the user is logged in and has the
   right role, in its own code. Payload custom views are public by default.

The data path behind these rules is in [Data flow](../data-flow.md).

## Planned webhooks and endpoints

Secret names are the variables in `.env.example`. Their values live in Railway or GitHub secrets, never in docs. Each
variable's status is in [Environment variables](../dev/env-vars.md) (all are reserved today).

| Name                              | Direction     | Sender check                                                                          | Status  |
| --------------------------------- | ------------- | ------------------------------------------------------------------------------------- | ------- |
| Lead providers (ADF/XML, email)   | Inbound       | no secret yet (planned)                                                               | Planned |
| Meta Lead Ads and Messenger       | Inbound       | `META_APP_SECRET` for POSTs (`X-Hub-Signature-256`). `META_VERIFY_TOKEN` for GET only | Planned |
| Web chat                          | Inbound       | no secret yet (planned)                                                               | Planned |
| Telnyx texting                    | Inbound       | `TELNYX_PUBLIC_KEY`                                                                   | Planned |
| Resend email events               | Inbound       | `RESEND_WEBHOOK_SECRET`                                                               | Planned |
| ElevenLabs voice                  | Inbound       | `ELEVENLABS_WEBHOOK_SECRET`                                                           | Planned |
| RouteOne lender callbacks         | Inbound       | To be confirmed from provider docs. Reserved name: `ROUTEONE_WEBHOOK_SECRET`          | Planned |
| Dealertrack lender callbacks      | Inbound       | To be confirmed from provider docs. Reserved name: `DEALERTRACK_WEBHOOK_SECRET`       | Planned |
| Payload admin API (REST, GraphQL) | Inbound       | Payload login and the dealer's tenant                                                 | Planned |
| NHTSA recall and VIN lookups      | Outbound only | Not a webhook; calls go out over HTTPS                                                | Planned |

**Meta (Lead Ads and Messenger).** Event POSTs are checked only by the `X-Hub-Signature-256` header. It is an HMAC-SHA256
over the raw request body, using `META_APP_SECRET`. `META_VERIFY_TOKEN` is used only for Meta's GET setup handshake. The
verify token is never accepted as proof of the sender on a POST.

**Lead providers and web chat.** These two channels have no approved sender check yet. CLAUDE.md non-negotiable rule 4
requires every webhook to verify the sender, so neither channel can be built until a check is approved (see
[Open questions](#open-questions)).

**RouteOne and Dealertrack.** Whether either provider signs callbacks with a shared secret is not confirmed. The reserved
names are kept, but the check is not set until the provider docs are read.

## How a page for an endpoint should look

When an endpoint is built, add its page in this folder with:

- The method and path, or the provider and event name.
- What it checks before it parses the body, by name only (never the secret value).
- An example request and response with **fake data only**, for example `"phone": "+1-555-0100"` and
  `"vin": "1HGCM82633A000000"` (a made-up VIN). No real customer names, numbers or addresses.
- The error codes it can return.
- Its status (Built, Reserved or Planned), and what it does on a repeated message.

## Open questions

These are not decided. Nothing marked proposed above is approved until the named team answers.

- **Dealer binding for each provider (founders and security).** Use a per-dealer secret not in the URL, or a signed body
  field looked up in a mapping table (rule 4)? Where does the mapping table live?
- **Web chat sender check (founders and security).** Options: a widget key with an Origin allow-list, plus rate limits
  and CAPTCHA. Not decided.
- **ADF email sender check (founders and security).** Options: a per-dealer inbound address, plus SPF, DKIM and DMARC
  checks on the sending domain. Not decided.
- **RouteOne and Dealertrack callback signing (founders).** Confirm from each provider's docs whether callbacks are signed
  with a shared secret, and how. If not, the check must be agreed before these endpoints are built.
- **Replay window and rate limits (security).** Window length and limits for each provider are not set.

## Related

- [Architecture](../architecture.md): services and where data lives.
- [Data flow](../data-flow.md): the lead path that the webhooks feed.
- [Runbooks index](../runbooks/README.md): what to do when a webhook fails.
