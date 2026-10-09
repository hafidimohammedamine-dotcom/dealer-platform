# 2026-10-09 - Payload skill for the agents

- Added the official Payload skill (`.claude/skills/payload`) from payloadcms/payload at tag v3.90.2 (commit 6254c3bf…; MIT).
  We removed, by deletion only, the install commands, link lists, the "fetch these URLs" section and the plugin-development guide;
  the exact change is `.claude/skills-patches/payload.diff`, provable with `scripts/check-skill-upstream.sh` (7 tests).
- Added our binding rules on top of it (`.claude/skills/payload-dealer-overrides`): collections stay thin; no globals for dealer data;
  no sensitive finance data in Payload; deny by default; no role skips the dealer filter; private, dealer-scoped uploads; custom views
  check login and role; built-in auth only; per-dealer API keys; no IP-header access; no customer messages from Payload;
  BullMQ instead of Payload jobs; webhooks; no personal data in logs, job inputs or errors; integer-cents money; banned plugins;
  a file-path allow-list (enforced by lint) for the only `overrideAccess: true` code.
- **CLAUDE.md**: order of authority "CLAUDE.md > payload-dealer-overrides > payload skill"; Payload rule 1 points to the allow-list;
  third-party skills may carry a recorded deletion-only patch.
- Preloaded both skills into builder-crm, builder-inventory, builder-finance, devops, security, architect, tester,
  chief-engineer and designer (designer owns the Payload admin theme).
- builder-inventory's description now matches its folders in CLAUDE.md; the old `services/website` mention was dropped
  (dealer website pages live in `apps/admin/src/website/`).
- `scripts/check-skills.sh` now also checks license files, NOTICE/lock commits, front matter names, and agent `skills:` lines
  (49 tests in `scripts/check-skills.test.sh`).
- Manager job also denies `yarn dlx`, `yarn create` and `node -e/--eval/-p`.
- Sources and the founder update procedure (git, never npx): `.claude/skills/SKILLS-LOCK.md`.
