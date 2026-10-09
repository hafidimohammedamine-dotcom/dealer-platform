# Changelog

## 2026-10-09
- **Agent skills pack:** agents now preload pinned skills for Payload, front end and design, code structure (TypeScript, NestJS,
  React, Nx), Postgres, security review, testing, Telnyx texting, Resend email and docs style. Sources, licenses and the update
  procedure: `.claude/skills/SKILLS-LOCK.md`. Binding rules on top: `payload-dealer-overrides`, `skill-overrides`.
- **New CI gates:** "Agents may not change founder-only files", "Skills unchanged" (runs the base branch's check script),
  "Skills check tests" and "Secret-scan allowlist test". Runbook: `docs/runbooks/pinned-skills-check.md`.
- **Review team** now reads CLAUDE.md and `.claude/` from the base branch, not from the PR under review.
- **Consent rule:** an opt-out on any channel (text, call, email) stops all channels; consent records kept at least 5 years.
