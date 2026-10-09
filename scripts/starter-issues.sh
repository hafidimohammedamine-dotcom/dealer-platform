#!/usr/bin/env bash
# Creates the first 16 issues (weeks 1-3) with labels and dependencies.
# Run once after setup-github.sh:  bash scripts/starter-issues.sh
set -euo pipefail

# new <agent> <priority> <area> <title> <body>  -> prints the new issue number
new() {
  local url
  url=$(gh issue create --title "$4" --body "$5" \
        --label "status:todo" --label "agent:$1" --label "priority:$2" --label "area:$3")
  echo "${url##*/}"
}

# Founders first: everything waits on these
C=$(new founder 1 platform "Write packages/contracts: Lead, Customer, Vehicle, Deal, CreditApp, LenderDecision" \
"Founders write the shared TypeScript types and their validation (zod). Every agent builds to these.

Done when:
- [ ] Types + zod schemas for Lead, Customer, Vehicle, Deal, CreditApp, LenderDecision, Consent, Dealer
- [ ] All money fields are integer cents; every record has dealer_id
- [ ] Sensitive fields on CreditApp marked so code can encrypt and mask them")

R=$(new devops 1 devops "Bootstrap monorepo: Yarn + Nx + TypeScript strict + ESLint + Prettier + Vitest" \
"Create the empty monorepo layout from CLAUDE.md with root scripts: yarn lint, yarn typecheck, yarn test, yarn build.

Done when:
- [ ] Folders from CLAUDE.md exist with a placeholder package each
- [ ] yarn lint / typecheck / test pass in CI
- [ ] .env.example lists every variable (no real values)")

T=$(new devops 1 platform "Payload app: multi-tenant setup, auth + 2FA, tenant-safe data helper, row-level security, leak tests" \
"Payload v3 (exact pinned version) in apps/admin with the Postgres adapter and the official multi-tenant plugin. Security must pass with zero findings.

Done when:
- [ ] Dealers (tenants) and Users collections; roles: admin, desking manager, sales rep, BDC
- [ ] 2FA required for every user (option chosen after security review)
- [ ] packages/data helper: always user + overrideAccess:false + tenant; lint rule bans direct payload calls elsewhere
- [ ] Postgres row-level security on tenant for every CRM table (FORCE RLS, app user is not owner)
- [ ] Leak test harness in tests/e2e that every new collection plugs into
- [ ] Runs on Railway staging as an always-on container; migrations as one CI job
Depends on: #$R")

P=$(new devops 1 platform "packages/platform: field encryption, audit log, queues" \
"Shared platform used by every service. Security must pass it with zero findings.

Done when:
- [ ] Field-level encryption + masking helpers for sensitive fields
- [ ] Audit log for every read/write of a CreditApp and every deal change
- [ ] BullMQ queue helpers with retries and dead-letter queue
Depends on: #$C, #$R")

F=$(new tester 1 platform "Fake data in fixtures/: 2 dealers, provider leads, texts, credit apps, lender callbacks" \
"All fake. SSNs only 900-xx-xxxx.

Done when:
- [ ] 2 dealers with staff, 30 vehicles each, 50 customers each
- [ ] 5 ADF/XML samples per provider: CarGurus, Cars.com, AutoTrader, TrueCar, Carfax, CarsForSale (incl. malformed)
- [ ] Meta lead ad + Messenger payloads; Telnyx inbound incl. STOP variants
- [ ] RouteOne/Dealertrack-style callbacks: approved, countered, conditioned, declined, expired, duplicate, out of order
Depends on: #$C")

new designer 2 design "Design system v1 in packages/ui: tokens and core components" \
"Colors, type, spacing; buttons, inputs, table, status badge, money and phone formatters, empty/error states; phone width first.
Depends on: #$R" >/dev/null

new docs 3 docs "Docs skeleton: architecture, API index, help center index, runbooks index" \
"Create docs/ structure from the docs agent instructions with first pages for architecture and data flow.
Depends on: #$R" >/dev/null

M=$(new builder-ai 1 ai "Consent and rules engine in services/messaging" \
"Every outbound message passes through it.

Done when:
- [ ] Blocks texts without stored consent
- [ ] Detects opt-out in any wording and blocks all channels instantly
- [ ] Quiet hours 8am-9pm customer local time; DNC list
- [ ] Telnyx send/receive behind it, webhook verified and idempotent
Depends on: #$C, #$P, #$F")

new builder-intake 1 intake "ADF/XML intake for Cars.com, CarGurus and AutoTrader" \
"Email and HTTP intake producing the Lead contract; raw saved first; idempotent; safe XML parsing; dedupe.
Depends on: #$C, #$T, #$F" >/dev/null

A=$(new builder-crm 1 crm "CRM collections v1 in Payload: Customers, Leads, Appointments, Tasks, Notes, Consent, Lead sources" \
"All in the multi-tenant plugin, through packages/data, with role access (reps see only their own) and a leak test each. No sensitive finance fields.
Depends on: #$C, #$T")

I=$(new builder-inventory 2 inventory "Inventory service: vehicles, NHTSA VIN decode + recalls, DealerCenter CSV import" \
"Vehicles collection in Payload (apps/admin/src/collections/inventory) + services/inventory. Includes read-only AI tools checkInventory and getVehicleDetails (dealer-scoped).
Depends on: #$C, #$T, #$F")

D=$(new builder-finance 2 finance "Desking calculator: price, trade, payoff, down, term, rate, Ohio tax/doc fee/title, payment grid" \
"Integer cents. Tester verifies to the cent against fixtures.
Depends on: #$C, #$P")

new builder-finance 2 finance "Lender adapter interface + fake lender + callback receiver" \
"submit, receiveCallback, poll, sendDocs, fundingStatus. Callback rules from CLAUDE.md. Fake lender in fixtures until partner access.
Depends on: #$D, #$F" >/dev/null

new builder-ai 2 ai "AI text replies (Haiku) with guardrails and human handoff" \
"Uses inventory tools; disclosure; no SSN, prices only from inventory; handoff pauses AI.
Depends on: #$M, #$I, #$A" >/dev/null

new builder-intake 2 intake "Meta Lead Ads + Messenger intake" \
"Webhook verified; 24-hour window rules; human_agent tag only for real human replies.
Depends on: #$C, #$T, #$F" >/dev/null

new builder-crm 2 crm "Payload custom views: pipeline board, customer timeline, BDC queue, rep 'my day', manager dashboard" \
"Pipeline stages from builder-crm instructions; speed-to-lead and appointment dashboards.
Depends on: #$A" >/dev/null

echo "Starter issues created. Founders: do #$C (contracts) first - most agents wait on it."
