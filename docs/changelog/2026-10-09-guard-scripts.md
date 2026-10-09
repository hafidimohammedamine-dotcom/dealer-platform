# 2026-10-09 - Guard checks for skills and agent workflows, and the agent network lock

- **Agent network lock** (`.github/actions/agent-egress-lock`, runs right after checkout in every agent job): pre-installs the
  pinned Claude Code, then allows outbound network only to GitHub, the Anthropic API, the npm/Yarn registries and the runner's
  log storage (local DNS allow-list plus firewall, no IPv6), stops Docker and removes sudo so nothing later can undo it, and
  self-tests. `.github/workflows/egress-lock-test.yml` proves it on a real runner, with the real claude-code-action, whenever it
  changes. The command deny lists stay as hygiene, not a boundary. Limits: `docs/runbooks/ci-guards.md`. Closes #31.
- **`guards` runs these checks from `main`** on every PR (the PR's files are data):
  - `scripts/check-skills-vs-base.sh`: a base third-party skill may not become `ours` or move to another source repo; every
    commit/path change, new and removed skill is logged.
  - `scripts/check-skills-upstream-all.sh` + `scripts/check-skill-upstream.sh`: fetch each third-party skill's locked commit; our
    copy may only delete whole units (a file, a heading's body, a fenced code block, or a table row/list item without a warning
    word; `scripts/check-skill-deletions.py`), and `.claude/skills-patches/<name>.diff` must equal today's diff.
  - `scripts/check-workflows.sh` (`check-workflows.py`, YAML-based, fails closed): Claude runs only through the pinned
    claude-code-action, after the network lock, with the pre-installed binary; `claude_args` holds only known flags and exactly one
    `--disallowedTools`, which denies `Skill(<name>)` for `payload` and every third-party skill in the base or PR manifest; the
    manager keeps its 25 denies (`Skill(payload)`, 19 command denies and 5 path denies); Claude credentials appear only in a
    claude step's `claude_code_oauth_token`; no unlisted local action, reusable workflow, Docker action or container job.
- `scripts/check-skills.sh` and the two upstream scripts read the manifest and lock rows through one helper,
  `scripts/check-skills-lib.sh` (exact first-cell match; commit = third cell, lower case). Also new: license file named
  `UPSTREAM-LICENSE` (plain, .md or .txt) or upstream's own `LICENSE`; manifest without CRLF, duplicate names, empty or repeated
  `requires=`; every third-party skill requires one of our own override skills; no skill repeated in an agent's `skills:` line.
- Every agent workflow step denies `Skill(payload)` ahead of the Payload skill (#22).
- Fix: instant fix rounds never started, because claude-code-action refuses runs started by `github-actions[bot]`. The manager
  now sets `allowed_bots: github-actions` (only there, enforced by `check-workflows.py`).
- `packages/data/override-allowlist.txt` is founder-only once it exists (CLAUDE.md, CODEOWNERS, `check-founder-files.sh`).
- Messages and fixes for every check: `docs/runbooks/ci-guards.md`.
