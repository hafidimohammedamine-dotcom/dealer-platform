# 2026-10-09 - Payload skill for the agents

- Added the official Payload skill (`.claude/skills/payload`) from payloadcms/payload at tag v3.90.2 (commit 6254c3bf…; MIT).
  We removed, by deletion only, the install commands, link lists, the "fetch these URLs" section and the plugin-development guide;
  the exact change is `.claude/skills-patches/payload.diff`. `scripts/check-skill-upstream.sh` checks every file directly
  (deletions only, nothing added, no symlinks, diff errors fail) and that the `.diff` record matches; the `guards` job runs it on every
  PR against a fresh fetch of the locked commit (`scripts/check-skills-upstream-all.sh`).
- Payload version: pin **3.90.2**, never below **3.87.1**. Every published Payload advisory is fixed by 3.87.0, and 3.87.0/3.87.1
  carry further security fixes from the release notes; the advisory table with links is in `.claude/skills/SKILLS-LOCK.md`.
  (An earlier draft of this PR cited CVE numbers that do not exist in Payload's advisories; they were removed.)
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
- `scripts/check-skills.sh` now also checks license files, NOTICE/lock commits, front matter names, agent `skills:` lines (no
  repeats), and the manifest (no CRLF, no duplicate names, no empty or repeated `requires=`, every third-party skill requires one of
  our own override skills).
- Command denies, per job: the manager denies `npx`, `npm`, `yarn dlx`, `yarn create`, `node -e/--eval/-p/--print`, `curl`,
  `wget`, `sudo`, printing the environment, force-push, merge, API deletes, `gh secret`/`gh auth`, and reading runner internals.
  These are a speed bump against one-liners, not a sandbox: builders still run code through yarn and node scripts, and the job has
  no network allow-list (known limit). Every claude-code-action step (manager, review, daily report, weekly audit, founder mentions in
  `claude.yml`) denies loading `payload` on its own (`Skill(payload)`). `scripts/check-workflows.sh` checks this step by step, plus all
  25 manager denies; `guards` runs the `main` copy on every PR.
- Sources and the founder update procedure (git, never npx): `.claude/skills/SKILLS-LOCK.md`.
