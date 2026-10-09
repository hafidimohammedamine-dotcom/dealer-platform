# 2026-10-09 - Guard checks for skills and agent workflows

- `guards` now runs two more checks from `main` on every PR (the PR's files are data):
  - `scripts/check-skills-upstream-all.sh` fetches each third-party skill's locked upstream commit and runs
    `scripts/check-skill-upstream.sh`: our copy may only delete lines or files from upstream. A removed line may not be a
    warning (❌, WRONG, SECURITY, never, must, not, avoid, ...), a fenced code block is kept or removed whole, and the
    `.claude/skills-patches/<name>.diff` record must equal today's diff. Any diff error fails.
  - `scripts/check-workflows.sh` fails closed: Claude runs only through the pinned claude-code-action; every such step has one
    quoted `--disallowedTools` line that denies `Skill(payload)` and sets tools no other way; the manager keeps all 25 command
    denies; Claude credentials reach no other step; no unlisted local action or reusable workflow.
- `scripts/check-skills.sh`: lock rows matched on the exact first cell; commits in lower case; license file named
  `UPSTREAM-LICENSE` (plain, .md or .txt) or upstream's own `LICENSE`; the manifest has no CRLF, no duplicate names, no empty or
  repeated `requires=`, and every third-party skill requires one of our own override skills; no skill repeated in an agent's
  `skills:` line.
- Every agent workflow step (manager, review, daily report, weekly audit, founder mentions) denies `Skill(payload)`; the manager
  also denies `yarn dlx`, `yarn create` and `node -e/--eval/-p/--print`. These denies are a speed bump, not a sandbox (known limit;
  an outbound network allow-list is tracked separately).
- `packages/data/override-allowlist.txt` is founder-only (CLAUDE.md, CODEOWNERS, `check-founder-files.sh`).
- Messages and fixes: `docs/runbooks/ci-guards.md`.
