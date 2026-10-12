# 2026-10-12 - shared data shapes in packages/contracts

Issue #3 (PR #52). `packages/contracts/src/` now holds the shared shapes, written with zod 4. Nothing else uses them yet.

- The shapes: Lead, Customer, Vehicle, Deal, CreditApp, LenderDecision, Consent and Dealer. Every record has a `dealer_id`.
  A Dealer's `id` is its own `dealer_id`. Unknown fields are rejected.
- Ids are strings (letters, digits, `_`, `-`, 1-64). Payload is to be configured with `idType: 'uuid'` so its ids pass; Payload's
  default is a numeric id (see `docs/architecture.md`).
- Money is integer cents (`*_cents` fields). Rates are basis points (650 = 6.50%). No floating point.
- Free text (names, comments, evidence wording, sources, user agents) rejects control characters and bidi controls
  (`SafeTextSchema`; `SafeLongTextSchema` also allows newline and tab). A leading `=`, `+`, `-` or `@` is allowed, so any CSV
  export must escape formula prefixes. URLs (`HttpsUrlSchema`) are https with a domain name host. They are untrusted and
  display-only; the check is not an SSRF control.
- Sensitive fields are marked in the schema. CreditApp: SSN, date of birth, monthly income, bank account number and bank routing
  number (`CREDIT_APP_SENSITIVE_FIELDS`). LenderDecision consumer-report data: credit score, score range, score date, key
  factors, bureau and adverse-action reasons (`LENDER_DECISION_SENSITIVE_FIELDS`). Both lists are derived from the schema and
  frozen. The field walker fails closed: it follows wrappers, both sides of a pipe, unions, intersections, records, tuples and
  lazy schemas, and throws on a type it does not know. A test fails if a field named like ssn, dob, income, account number or
  routing is not marked.
- Masking is not in contracts. Screen masking and encryption at rest will be built in `packages/platform`.
- New dependency: `zod` 4.1.12 (exact version) in `packages/contracts`.
- No endpoint uses the shapes yet. The package has no database and does no I/O.
- Consent: each record keeps the consented address, the purpose (marketing, informational, or all) and the capture context
  (method, IP address, user agent, page URL). The address must fit the channel: E.164 phone for `sms` and `voice_ai`, a lowercase
  email for `email`, digits for a Messenger ID; `all` takes any of these. `all` (channel or purpose) is for revoked records only,
  and a revocation counts as `all` unless the customer limited it. Retention: a granted record has no `retain_until` (it is kept
  while in use, and until at least 5 years after it is revoked or last used). A revoked record needs `retain_until`, at least
  5 years after `recorded_at` (a leap day rolls forward: 2028-02-29 becomes 2033-03-01).
- CreditApp: carries the credit-pull authorization (the wording, the time and the method). With a co-applicant it also
  carries the co-applicant's customer ID and the joint-intent evidence.
- LenderDecision: carries `request_id` (ties the answer to our request) and a required `provider_message_id` (the lender's own
  message ID, printable ASCII, 1-200 characters). `services/callbacks` uses the shape's ids to handle a repeated callback once;
  the contract only carries them. Adverse-action fields: reasons, credit score (250-900, checked against the optional score
  range), bureau, score date, up to 5 key factors and the notice date. A declined decision needs at least one reason.
- Deal: `deal_type` is cash, retail_installment or lease. Fees and taxes are separate fields (doc, title, registration, other
  fees, taxes). Once a deal is contracted or funded it needs `tax_rate_basis_points`, `tax_jurisdiction`, `taxable_amount_cents`,
  an identity check and a clear OFAC screen. A retail installment deal also needs the Reg Z fields (term, APR, finance charge,
  total of payments, total sale price, monthly payment, first payment date). A contracted lease is rejected until Reg M fields
  are added. An optional co-buyer needs their own identity check and a clear OFAC screen once contracted. Cash above 1,000,000
  cents needs `form_8300`.
- Vehicle: `advertised_price_cents` is the only price the AI may quote. It must be above zero and include every dealer charge
  except tax, title and registration.
- Time zones: `time_zone` (IANA name) is required on Dealer and drives texting hours. It is optional on Customer.
- Test samples use fake data only. SSNs use the 900-xx-xxxx range. The shared samples live in `src/samples.test.ts`, which is
  left out of the build and the coverage count.
