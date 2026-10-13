# API index

**Status: nothing is built yet.** No endpoint or webhook exists in the repo. The services and the admin app are
placeholders (see [Architecture](../architecture.md)). This page lists what is planned, so that each entry gets its own
page here when it is built.

## Rules every endpoint and webhook must follow

These come from [CLAUDE.md](../../CLAUDE.md) and are not optional:

1. **Verify the sender first.** Check the signature or secret for that provider before reading the body.
2. **Save the raw message next.** Store what arrived before any parsing.
3. **Process from a queue.** The endpoint answers, and a BullMQ job does the work.
4. **Handle a repeat once.** The same message sent twice is processed one time.
5. **Filter by dealer.** Every query and write is limited to the dealer's tenant.

The data path behind these rules is in [Data flow](../data-flow.md).

## Planned webhooks and endpoints

Secret names are the variables in `.env.example`. Their values live in Railway or GitHub secrets, never in docs. Each
variable's status is in [Environment variables](../dev/env-vars.md) (all are reserved today).

| Name                              | Direction     | Sender check (env name)                | Status  |
| --------------------------------- | ------------- | -------------------------------------- | ------- |
| Lead providers (ADF/XML, email)   | Inbound       | Set when the intake service is built   | Planned |
| Meta Lead Ads and Messenger       | Inbound       | `META_APP_SECRET`, `META_VERIFY_TOKEN` | Planned |
| Web chat                          | Inbound       | Set when the chat endpoint is built    | Planned |
| Telnyx texting                    | Inbound       | `TELNYX_PUBLIC_KEY`                    | Planned |
| Resend email events               | Inbound       | `RESEND_WEBHOOK_SECRET`                | Planned |
| ElevenLabs voice                  | Inbound       | `ELEVENLABS_WEBHOOK_SECRET`            | Planned |
| RouteOne lender callbacks         | Inbound       | `ROUTEONE_WEBHOOK_SECRET`              | Planned |
| Dealertrack lender callbacks      | Inbound       | `DEALERTRACK_WEBHOOK_SECRET`           | Planned |
| Payload admin API (REST, GraphQL) | Inbound       | Payload login and the dealer's tenant  | Planned |
| NHTSA recall and VIN lookups      | Outbound only | Not a webhook; calls go out over HTTPS | Planned |

## How a page for an endpoint should look

When an endpoint is built, add its page in this folder with:

- The method and path, or the provider and event name.
- What it checks before it reads the body, by name only (never the secret value).
- An example request and response with **fake data only**, for example `"phone": "+1-555-0100"` and
  `"vin": "1HGCM82633A000000"` (a made-up VIN). No real customer names, numbers or addresses.
- The error codes it can return.
- Its status (Built or Planned), and what it does on a repeated message.

## Related

- [Architecture](../architecture.md): services and where data lives.
- [Data flow](../data-flow.md): the lead path that the webhooks feed.
- [Runbooks index](../runbooks/README.md): what to do when a webhook fails.
