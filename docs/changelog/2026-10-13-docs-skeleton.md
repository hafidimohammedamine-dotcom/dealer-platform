# 2026-10-13 - Docs skeleton: architecture, API index, help center index, runbooks index (#9)

- **Docs home:** `docs/README.md` links every docs page and defines the status words (Built, Reserved, Planned) once,
  under "Status words". The other pages link to that definition. It also lists the rules for examples (fake data, no
  secrets).
- **Data flow** (`docs/data-flow.md`): a lead from a provider, through the sender check, the saved raw message, the queue,
  the worker's dedupe and parse, a detect-and-mask step for sensitive data (proposed), the opt-out and HELP check, the CRM
  write through `packages/data`, the AI reply with guardrails, and the texting checks before a send. Every step is tagged
  **Planned**, and each review addition is tagged "review addition (proposed)" and waits for its approver. The texting
  rules are linked to CLAUDE.md rule 6, not restated. The open questions for founders, security and compliance are at the
  end of the page.
- **API index** (`docs/api/README.md`): the planned webhooks and endpoints, each with its sender check (no secret yet for
  lead providers and web chat). Each rule is marked as from CLAUDE.md or as proposed. Meta POST signatures are kept apart
  from the GET verify token. RouteOne and Dealertrack callback signing is to be confirmed from provider docs. No endpoint is
  built yet, so none has an example request.
- **Environment variables** (`docs/dev/env-vars.md`): descriptions of the Meta, RouteOne and Dealertrack secrets now match
  the API index. The variable names are unchanged.
- **Help center index** (`docs/help/README.md`): how dealer pages are written and the four planned task pages. No help
  page is written yet.
- **Runbooks index** (`docs/runbooks/README.md`): links the eight runbooks that exist, and lists the four planned ones
  (texting, lender callbacks, admin down, migrations). Only the texting runbook is on the lead path.
- **Architecture** (`docs/architecture.md`): the intro points to the data flow, the API index and the docs home. The
  status words link to the docs home. The table and CI section are unchanged.
