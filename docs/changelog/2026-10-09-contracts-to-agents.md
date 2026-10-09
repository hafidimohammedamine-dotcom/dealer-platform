# 2026-10-09 - Agents build the shared data shapes

- `packages/contracts/` (Lead, Customer, Vehicle, Deal, CreditApp, LenderDecision, Consent, Dealer) is now built by the devops
  agent instead of the founders, at the founders' request. A founder still approves every change (CODEOWNERS, and founders merge
  every PR); other agents ask for changes with `REQUEST:`.
- The founder-only file check no longer includes `packages/contracts/`.
