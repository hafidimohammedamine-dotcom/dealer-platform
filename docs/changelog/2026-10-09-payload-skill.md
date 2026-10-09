# 2026-10-09 - Payload skill for the agents

- Added the official Payload skill (`.claude/skills/payload`) from payloadcms/payload at tag v3.90.2 (commit 6254c3bf…; MIT).
  We removed, by deletion only, the install commands, link lists, the "fetch these URLs" section and the plugin-development guide;
  the exact change is `.claude/skills-patches/payload.diff`, provable with `scripts/check-skill-upstream.sh`, which checks every file directly: deletions only, nothing added, no symlinks
  (15 tests in `scripts/check-skill-upstream.test.sh`). We must run Payload 3.90.0+ (advisories CVE-2026-105852, -105847).
- Added our binding rules on top of it (`.claude/skills/payload-dealer-overrides`): collections stay thin; no globals for dealer data;
  no sensitive finance data in Payload; deny by default; no role skips the dealer filter; private, dealer-scoped uploads; custom views
  check login and role; built-in auth only; per-dealer API keys; no IP-header access; no customer messages from Payload;
  BullMQ instead of Payload jobs; webhooks; no personal data in logs, job inputs or errors; integer-cents money; banned plugins;
  secrets only through a required-env helper; `overrideAccess: true` only for founder-approved system jobs in the founder-only
  `packages/data/override-allowlist.txt`, and only once the lint rule exists (no exception until then).
- **CLAUDE.md**: order of authority "CLAUDE.md > payload-dealer-overrides > payload skill"; Payload rule 1 points to the allow-list;
  third-party skills may carry a recorded deletion-only patch.
- Preloaded both skills into builder-crm, builder-inventory, builder-finance, devops, security, architect, tester,
  chief-engineer and designer (designer owns the Payload admin theme).
- builder-inventory's description now matches its folders in CLAUDE.md; the old `services/website` mention was dropped
  (dealer website pages live in `apps/admin/src/website/`).
- `scripts/check-skills.sh` now also checks license files, NOTICE/lock commits, front matter names, and agent `skills:` lines
  (tests in `scripts/check-skills.test.sh`).
- Command denies, per job: the manager denies `npx`, `npm`, `yarn dlx`, `yarn create`, `node -e/--eval/-p/--print`, `curl`,
  `wget`, `sudo`, printing the environment, force-push, merge, API deletes, `gh secret`/`gh auth`, and reading runner internals.
  These are a speed bump against one-liners, not a sandbox: builders still run code through yarn and node scripts, and the job has
  no network allow-list (known limit). Every agent job that can use skills (manager, review, daily report, weekly audit) denies
  loading `payload` on its own (`Skill(payload)`); `scripts/check-workflows.sh` keeps these denies in place.
- Sources and the founder update procedure (git, never npx): `.claude/skills/SKILLS-LOCK.md`.
