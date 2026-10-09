# Runbook: "Skills unchanged" or "Agents may not change founder-only files" fails in CI

**Who fixes it:** a founder. Agents never change `.claude/` or the skill checks.

## "Agents may not change founder-only files"
An `agent/*` branch touched CLAUDE.md, `.claude/`, the skill check scripts, `.gitleaks.toml`, CODEOWNERS, an agent workflow or
`packages/contracts`. The builder must undo those changes and instead comment on its issue:
`REQUEST: <path> - <change> - <why>`. The manager routes it to the founders.

## "Skills unchanged"
The output says which case it is:
- **Unknown skill folder** - a folder under `.claude/skills/` isn't in `PINNED` or `FIRST_PARTY` in `scripts/check-skills.sh`.
- **Missing skill folder** - a listed skill was deleted.
- **Symlinks / only regular files** - remove the link or special file; skills must be plain files.
- **Files added / removed or renamed / changed** - the files differ from `.claude/skills/checksums.sha256`.

What to do:
1. If nobody meant to change skills: revert the change on the branch. Done.
2. If a founder is adding or updating a skill on purpose: follow "How a founder adds or updates a skill" in
   `.claude/skills/SKILLS-LOCK.md` (pin the commit, NOTICE, review the files, `--write`, run the tests).
3. If you added a new skill folder and CI still says "Unknown skill folder": CI runs the **base branch's** script. Merge the
   script change (new name in `PINNED`/`FIRST_PARTY`) in its own PR first, then re-run.

Local checks: `bash scripts/check-skills.sh`, `bash scripts/check-skills.test.sh`,
`GITLEAKS=gitleaks bash scripts/gitleaks-config.test.sh`.
