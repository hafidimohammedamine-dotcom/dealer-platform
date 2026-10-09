# 2026-10-09 - Guard checks for skills and agent workflows, and the agent network lock (#22 split, #31)

- **Agent network lock** (`.github/actions/agent-egress-lock`, right after the checkout of `main` in every agent job):
  installs the pinned Claude Code binary checked against a pinned sha256; DNS answers only allow-listed names; a local
  SNI-checking proxy (nginx stream) is the only way out on port 443 and connects only to allow-listed host names, so an allowed
  IP cannot be reused under another name; plain HTTP, raw IPs, other DNS servers and IPv6 are rejected; Docker is stopped and
  sudo removed; a self-test fails the job on any problem. It narrows the routes out but is not a complete data boundary
  (limits in `docs/runbooks/ci-guards.md`). Tested by `scripts/check-egress-lock.test.sh` (stubbed, every failure branch),
  `egress-lock-test.yml` (the PR's lock on a real runner with no secrets, plus a break-on-purpose run) and
  `egress-lock-claude.yml` (from `main` only: the real claude-code-action under the lock and a `Skill(payload)` deny probe).
  Closes #31.
- **Claude Code's subprocess isolation is on in every agent job** (`CLAUDE_CODE_SUBPROCESS_ENV_SCRUB: "1"`, bubblewrap from
  the lock): the tools agents run never see the Claude token. Answer-only jobs may allow only read-only tools and Bash commands
  (no `find`, no `git grep`, no writes), `bypassPermissions` is only for the manager, `--add-dir` only `/tmp/pr` in review,
  and claude jobs take only allow-listed env names. The policy lists live in `scripts/check-workflows-policy.json`.
- **Agent jobs never run PR code next to a Claude token**: every claude job checks out `main` (the base branch for
  pull_request_target) without stored credentials; workflows with a claude step cannot run on `pull_request`. The manager's git
  pushes now authenticate through `gh auth setup-git`.
- **`guards` runs these checks from `main`** on every PR (the PR's files are data):
  - `scripts/check-skills-vs-base.sh`: a base third-party skill may not become anything else or move to another source repo;
    every commit/path change, new and removed skill is logged.
  - `scripts/check-skills-upstream-all.sh` + `scripts/check-skill-upstream.sh`: fetch each third-party skill's locked commit;
    our copy may only delete whole units (`scripts/check-skill-deletions.py`; Markdown only, other files whole); a removed section or code block with a warning
    word needs a founder entry in `.claude/skills-patches/<name>.reviewed`; the `.diff` record must equal today's diff.
  - `scripts/check-workflows.sh` (`check-workflows.py`, YAML-based, fails closed): Claude runs only through the pinned
    claude-code-action after the lock; `claude_args` has only known flags and one `--disallowedTools` that denies
    `Skill(<name>)` for `payload` and every third-party skill in the base or PR manifest; the manager keeps its 25 denies
    (`Skill(payload)`, 19 command denies and 5 path denies); `secrets` only as `secrets.<NAME>`, and Claude credentials only in
    a claude step's `claude_code_oauth_token`; no unlisted local action, reusable workflow, Docker action, container or service.
- `scripts/check-skills-lib.sh` holds the shared helpers (`manifest_entries`, `valid_skill_name`, `lock_row_one`, lock-row
  parsing) used by the skill guards; `check-skills.sh` still parses the manifest itself because it validates every option.
- Fix: instant fix rounds never started, because claude-code-action refuses runs started by `github-actions[bot]`. The manager
  now sets `allowed_bots: github-actions` (only there, enforced by `check-workflows.py`).
- Every agent workflow step denies `Skill(payload)` ahead of the Payload skill (#22).
- `packages/data/override-allowlist.txt` is founder-only once it exists (CLAUDE.md, CODEOWNERS, `check-founder-files.sh`).
- Messages and fixes for every check: `docs/runbooks/ci-guards.md`.
