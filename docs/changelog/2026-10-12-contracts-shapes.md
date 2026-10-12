# 2026-10-12 - shared data shapes in packages/contracts

Issue #3 (PR #52, review round 2). `packages/contracts/src/` now holds the shared shapes, written with zod 4. Nothing else uses them yet.

- The shapes: Lead, Customer, Vehicle, Deal, CreditApp, LenderDecision, Consent and Dealer. Every record has a `dealer_id`.
  A Dealer's `id` is its own `dealer_id`. Unknown fields are rejected.
- Record ids are UUID strings. Payload must be configured with `idType: 'uuid'` (its Postgres adapter uses numeric ids by
  default). That config change is not in this PR: it is routed to PR #55 / issue #5. Until it lands, CRM records read
  through `packages/data` would carry numeric ids and fail these shapes.
- Money is integer cents (`*_cents` fields). Rates are basis points (650 = 6.50%), used for APR and tax rate. No floating point.
- Free text (names, labels, comments, consent wording) rejects control characters and bidirectional controls. A leading
  `=`, `+`, `-` or `@` is allowed, so any CSV export must escape formula prefixes.
- URLs (lead source, consent page) are untrusted and display-only. An https link to a domain name is not an SSRF
  control: never fetch these server-side without an SSRF guard.
- Time zones: `time_zone` (IANA name, for example `America/Chicago`) is required on Dealer, because it drives texting
  hours, and optional on Customer.
- Sensitive fields (encrypted at rest, masked on screen, never logged, never sent by text or email):
  - CreditApp: SSN, date of birth, monthly income, bank account number and bank routing number. Listed in `CREDIT_APP_SENSITIVE_FIELDS`.
  - LenderDecision: credit score, score range, score date, key factors, credit bureau and adverse-action reasons. Listed in `LENDER_DECISION_SENSITIVE_FIELDS`.
  - Both lists are derived from the schema and frozen. Masking and encryption are not in contracts; they will be built in `packages/platform`.
- CreditApp carries the credit-pull authorization (the exact wording, the time and the method). With a co-applicant it also
  carries the co-applicant's customer ID and the joint-intent evidence.
- Consent:
  - Each record keeps the address consented, the purpose and the capture context (method, IP address, user agent, page URL).
  - The address must be canonical for its channel: E.164 phone for `sms` and `voice_ai`, lowercased email for `email`,
    digits-only Messenger ID for `messenger`. Channel `all` accepts any of those and covers every address of that person.
  - Purpose is `marketing`, `informational` or `all`. Channel `all` and purpose `all` are valid only on a revoked record.
    A revocation counts as `all` unless the customer limited it to one purpose.
  - Retention: a granted record has no `retain_until`. It is kept while the consent is in use, and until 5 years after it
    is revoked or last used. A revoked record must carry `retain_until`, at least 5 years after `recorded_at`. On Feb 29
    the 5 years end on Mar 1.
  - A granted record requires `evidence_text` (the exact wording shown or received).
- LenderDecision:
  - `request_id` ties the answer to our request. `provider_message_id` is the lender's own message id (visible ASCII, 1-200 characters).
  - The dedupe key for a callback is `request_id` plus `provider_message_id`. It is required on every status except
    `pending`. `services/callbacks` uses that key to handle a repeated callback once.
  - A declined decision needs at least one adverse-action reason.
  - Credit score is 250-900 (FICO Auto Score range). A score must sit inside its `score_range_min` to `score_range_max`
    (both or neither). Key factors are at most 5.
- Deal:
  - `deal_type` is `cash`, `retail_installment` or `lease`.
  - Fees and taxes are separate fields (doc, title, registration, other fees, taxes).
  - Once contracted or funded, every deal type needs the tax rate, tax jurisdiction and taxable amount, an identity check and a clear OFAC result.
  - `retail_installment` also needs the Reg Z fields: term, APR, finance charge, total of payments, total sale price, monthly payment and first payment date.
  - A `lease` cannot be contracted until the Reg M fields exist.
  - A co-buyer (`co_buyer_customer_id`) needs its own identity check and a clear OFAC result once contracted or funded.
  - Cash received above 1,000,000 cents needs `form_8300`.
- Vehicle: `advertised_price_cents` must be above zero. It is the only price the AI may quote. It includes every dealer
  charge except tax, title and registration.
- Test samples use fake data only. SSNs use the 900-xx-xxxx range.
