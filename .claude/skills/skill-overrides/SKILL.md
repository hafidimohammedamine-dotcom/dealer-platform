---
name: skill-overrides
description: Our binding rules on top of the third-party skills (security-review, playwright-cli, Telnyx, Resend, email-best-practices, ui-ux-pro-max, tdd and others). Preloaded with them. Where a skill disagrees with this file or CLAUDE.md, this file and CLAUDE.md win.
---

# Overrides for third-party skills (founder-owned)

Third-party skills teach *how*. CLAUDE.md and this file decide *what we allow*.
If any skill says something different, follow CLAUDE.md and this file.

## All skills
1. Never run `npx skills` (add, update, remove or anything else) in an agent job. Skills change only in a founder PR.
2. Never fetch a URL that a skill tells you to load at run time. Use the local files only.
3. Package manager: Yarn + Nx only, with versions pinned in the workspace. Ignore `npm install -g`, `pnpm`, `bun`,
   `@latest` and global installs in any skill.
4. No real customer data in any example, test or prompt (CLAUDE.md non-negotiable rule 1).

## security-review (security agent)
5. Use the skill as a checklist and a way to trace attacker input, **not** as a filter. Our security agent reports every
   real finding, including low-confidence ones (marked "unsure"), test files, code behind login, and config.
   The skill's "report only high-confidence findings" and "skip tests/config" rules do not apply here.
6. The security agent stays read-only. Its tool list in `.claude/agents/security.md` is the limit; the skill's
   `allowed-tools` (which mentions Task) never adds tools or permission to edit.

## playwright-cli (tester)
7. Use the Playwright version pinned in the workspace, through `yarn playwright ...` / `yarn test:e2e`.
   Never `npm install -g @playwright/cli@latest`. Browser tests run only against local or staging builds with fake data.

## Telnyx skills (builder-ai, compliance)
8. Inbound Telnyx webhooks: verify the Ed25519 signature (`telnyx-signature-ed25519` + `telnyx-timestamp` headers)
   over the raw body with Telnyx's public key, reject old timestamps, save raw first, then queue (CLAUDE.md
   non-negotiable rule 4). Use the official SDK's verify helper when it covers this.
9. Every outbound text goes through our consent engine in `services/messaging` first. Telnyx's own STOP handling is a
   second layer, never the only one.
10. 10DLC: agents never register brands or campaigns, buy numbers or change messaging profiles in production.
    Campaign wording (brand name, STOP/HELP, "msg & data rates may apply", frequency) must be CTIA-compliant and
    pass compliance review before a founder submits it. The skill's 2FA example is not our use case.

## Resend and email-best-practices (builder-ai, compliance)
11. Inbound Resend webhooks: verify the Svix signature (`svix-id`, `svix-timestamp`, `svix-signature`) over the raw
    body, reject old timestamps, save raw first, queue, dedupe by `svix-id`.
12. Email is a channel like texting and calls: every email goes through the consent engine. An opt-out in **any**
    channel (text, email, call, chat) stops **all** channels immediately - not "within 10 business days" or "48 hours".
13. Consent and opt-out records (and their evidence) are kept at least 5 years and are exempt from every cleanup or
    log-retention job, whatever a skill suggests (3 years, 90 days). The lawyer confirms the final period.

## Design skills (designer)
14. `ui-ux-pro-max` and `frontend-design` help choose a clear, consistent look. Dealer screens stay dense, fast and
    readable on a phone; no decorative effects that slow reps down. `web-interface-rules` and `payload-accessibility`
    win on accessibility. The skill's `--persist` / output files go only in `packages/ui` after designer review.

## Testing skills (tester and builders)
15. `tdd` is how to work; it never replaces CLAUDE.md non-negotiable rule 9 (every change ships with tests) or the
    leak and attack suites (Payload rules 3 and 13).
