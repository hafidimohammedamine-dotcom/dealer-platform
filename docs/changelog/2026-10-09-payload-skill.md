# 2026-10-09 - Payload skill for the agents

- Added the official Payload skill (`.claude/skills/payload`), copied unchanged from payloadcms/payload at tag v3.90.2
  (commit 6254c3bf…; MIT; NOTICE.md and license included). The skill tag must match our pinned Payload version.
- Added our binding rules on top of it (`.claude/skills/payload-dealer-overrides`): deny by default; no role skips the dealer
  filter; private, dealer-scoped uploads; custom views check login and role; built-in auth only; per-dealer API keys; no IP-header
  access; no customer messages from Payload (only through `services/messaging`); BullMQ instead of Payload jobs; webhooks;
  no personal data in logs, job inputs or errors; integer-cents money; banned plugins (MCP, import-export, form-builder).
- **CLAUDE.md**: order of authority "CLAUDE.md > payload-dealer-overrides > payload skill"; Payload rule 1 now states the one
  exception (a reviewed allow-list of system jobs in `packages/data`, RLS still applies).
- Preloaded both skills into builder-crm, builder-inventory, builder-finance, devops, security, architect, tester,
  chief-engineer and designer (designer owns the Payload admin theme).
- builder-inventory's description now matches its folders in CLAUDE.md; the old `services/website` mention was dropped
  (dealer website pages live in `apps/admin/src/website/`).
- `scripts/check-skills.sh` (34 tests) now also checks: license file and matching commit for third-party skills, front matter
  names, and that agents only preload listed skills, with their required override.
- Sources, known neutralized upstream lines, and the founder update procedure (git, not npx): `.claude/skills/SKILLS-LOCK.md`.
