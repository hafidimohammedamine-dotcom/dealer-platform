# 2026-10-12 - shared data shapes in packages/contracts

Issue #3 (PR #52). `packages/contracts/src/` now holds the shared shapes, written with zod 4. Nothing else uses them yet.

- The shapes: Lead, Customer, Vehicle, Deal, CreditApp, LenderDecision, Consent and Dealer. Every record has a `dealer_id`.
  A Dealer's `id` is its own `dealer_id`. Unknown fields are rejected.
- Money is integer cents (`*_cents` fields). Rates are basis points (650 = 6.50%). No floating point.
- Sensitive fields on CreditApp: SSN, date of birth, monthly income, bank account number and bank routing number. They are
  marked in the schema. `CREDIT_APP_SENSITIVE_FIELDS` lists them, is derived from the schema and is frozen.
- Masking is not in contracts. Screen masking and encryption at rest will be built in `packages/platform`.
- New dependency: `zod` 4.1.12 (exact version) in `packages/contracts`.
- No endpoint uses the shapes yet. The package has no database and does no I/O.
- Consent: each record keeps the consented address (phone, email or Messenger ID), the purpose (marketing or
  informational) and the capture context (method, IP address, user agent, page URL). Revoked records are kept for at least
  5 years (`retain_until`).
- CreditApp: carries the credit-pull authorization (the wording, the time and the method). With a co-applicant it also
  carries the co-applicant's customer ID and the joint-intent evidence.
- LenderDecision: carries `request_id` (ties the answer to our request) and `provider_message_id` (the lender's message ID,
  so a repeated callback is handled once). Adverse-action fields: reasons, credit score and bureau, and the notice date.
  A declined decision needs at least one reason.
- Deal: fees and taxes are separate fields (doc, title, registration, other fees, taxes). The Reg Z disclosure fields (APR,
  finance charge, total of payments, total sale price, monthly payment, first payment date) are required once a deal is
  contracted or funded. Identity check and a clear OFAC screen are also required then.
- Test samples use fake data only. SSNs use the 900-xx-xxxx range.
