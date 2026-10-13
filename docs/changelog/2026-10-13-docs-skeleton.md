# 2026-10-13 - Docs skeleton: architecture, API index, help center index, runbooks index (#9)

- **Docs home:** `docs/README.md` links every docs page, explains the status words (Built, Reserved, Planned) and lists
  the rules for examples (fake data, no secrets).
- **Data flow** (`docs/data-flow.md`): a lead from a provider webhook, through the sender check, the saved raw message,
  the queue, the CRM write through `packages/data`, the AI reply with guardrails, and the consent and quiet-hours checks
  before a text. Marked **Planned** throughout: the intake, AI, messaging and data packages are placeholders today.
- **API index** (`docs/api/README.md`): the planned webhooks and endpoints, with the secret env names from
  `.env.example`. No endpoint is built yet, so none has an example request.
- **Help center index** (`docs/help/README.md`): how dealer pages are written and the four planned task pages. No help
  page is written yet.
- **Runbooks index** (`docs/runbooks/README.md`): links the eight runbooks that exist, and lists the four planned ones
  (texting, lender callbacks, admin down, migrations).
- **Architecture** (`docs/architecture.md`): the intro now points to the data flow, the API index and the docs home. The
  table and CI section are unchanged.
