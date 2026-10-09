# 2026-10-09 - Guard checks for skills and agent workflows, and the agent network lock (#22 split, #31)

- **Agent network lock** (`.github/actions/agent-egress-lock`, right after the checkout of `main` in every agent job):
  installs gitleaks and the pinned Claude Code and Bun binaries, each checked against a pinned sha256 (the action's own Bun
  download is not used); DNS answers only allow-listed names; a local
  SNI-checking proxy (nginx stream) is the only way out on port 443 and connects only to allow-listed host names, so an allowed
  IP cannot be reused under another name; plain HTTP, raw IPs, other DNS servers and IPv6 are rejected; Docker is stopped and
  sudo removed (also group rules); bubblewrap may create user namespaces but its children may not and have no capabilities
  (AppArmor); a self-test fails the job on any problem, including domain fronting through any exact allowed name. GitHub's
  release storage and the Azure log-storage names were removed from the allow-list after they answered for other hosts
  (measurements in `docs/runbooks/agent-network-lock.md`). It narrows the routes out but is not a complete data boundary
  (limits in `docs/runbooks/ci-guards.md`). Tested by `scripts/check-egress-lock.test.sh` (stubbed, every failure branch),
  `egress-lock-test.yml` (the PR's lock on a real runner with no secrets, plus a break-on-purpose run) and
  `egress-lock-claude.yml` (from `main` only: the real claude-code-action under the lock and a `Skill(payload)` deny probe).
  Closes #31.
- **Claude Code's subprocess isolation is on in every agent job** (`CLAUDE_CODE_SUBPROCESS_ENV_SCRUB: "1"`, bubblewrap from
  the lock): the tools agents run never see the Claude token. Answer-only jobs may allow only read-only tools and a fixed list of Bash
  commands (`gh` views and lists, `yarn npm audit/info`, `yarn why`, `date`; no `git`, `find`, `sort`, `cat` or anything that
  can write a file). The review job no longer allows `Bash(git -C /tmp/pr grep:*)`, `Bash(find /tmp/pr:*)` or any git command:
  the PR's diff, commits and commit patches are written as plain files to `/tmp/pr-meta` before Claude starts (the weekly audit
  gets `/tmp/audit-meta`). `bypassPermissions` is only for the manager, `--add-dir` only those folders, and claude jobs take only
  allow-listed env names, `runs-on: ubuntu-latest`, allow-listed permissions, SHA-pinned actions and no `defaults`. The policy lists live in `scripts/check-workflows-policy.json`.
- **Agent jobs never run PR code next to a Claude token**: every claude job checks out `main` (the base branch for
  pull_request_target) without stored credentials, and every other checkout in the job may set only `ref`, `fetch-depth` and
  `persist-credentials`; only the reviewed prepare step may touch `/tmp/pr`; steps after Claude check the sha256 of the scripts
  they run; claude steps cannot run after a failure; workflows with a claude step cannot run on `pull_request`. The manager's git
  pushes now authenticate through `gh auth setup-git`, and the manager stops if its GitHub token belongs to a founder
  (`scripts/check-agent-token.sh`) - so it does not run until the agents' own account exists. The instant fix round starts only
  for a same-repository PR by the agents' login (`AGENT_GH_LOGIN` variable).
- **`guards` runs these checks from `main`** on every PR (the PR's files are data):
  - `scripts/check-skills-vs-base.sh`: a base third-party skill may not become anything else or move to another source repo;
    every commit/path change, new and removed skill is logged.
  - `scripts/check-skills-upstream-all.sh` + `scripts/check-skill-upstream.sh`: fetch each third-party skill's locked commit;
    our copy may only delete whole units (`scripts/check-skill-deletions.py`; Markdown only, other files whole; whole tables, nested
    list items with their parent); a removed section, code block, table or whole Markdown file with a warning word needs a
    founder entry in `.claude/skills-patches/<name>.reviewed`; the `.diff` record must equal today's diff.
  - `scripts/check-workflows.sh` (YAML-based, fails closed): `check-workflows.py` checks every workflow and local action,
    `check-workflows-claude.py` the jobs with a claude step (checkout, lock, binaries, env, permissions, PR data, git moves,
    post-step pin checks, tag mode only on issues), both through `check-workflows-lib.py`: Claude runs only through the pinned
    claude-code-action after the lock; `claude_args` has only known flags and one `--disallowedTools` that denies
    `Skill(<name>)` for `payload` and every third-party skill in the base or PR manifest; the manager keeps its 29 denies
    (`Skill(payload)`, 23 command denies including `gh api`, `gh gist` and `yarn npm publish/login`, and 5 path denies); `secrets` only as `secrets.<NAME>`, and Claude credentials only in
    a claude step's `claude_code_oauth_token`; no unlisted local action, reusable workflow, Docker action, container or service.
- `scripts/check-skills-lib.sh` holds the shared helpers (`manifest_lines`, `manifest_entries`, `valid_skill_name`,
  `lock_row_one`, `lock_row_error`, lock-row parsing) used by every skill guard, including `check-skills.sh`; its own test also
  checks that the Python manifest reader in `check-workflows.py` reads the same third-party names.
- Fix: instant fix rounds never started, because claude-code-action refuses runs started by `github-actions[bot]`. The manager
  now sets `allowed_bots: github-actions` (only there, enforced by `check-workflows.py`).
- Every claude step denies `Skill(payload)` ahead of the Payload skill (#22).
- `packages/data/override-allowlist.txt` is a reserved founder-only path (CLAUDE.md Payload rule 1, CODEOWNERS,
  `check-founder-files.sh`): the reviewed system jobs that may use `overrideAccess: true`. It does not exist yet; it is created
  together with the lint rule that reads it.
- CI runs every guard script test through `scripts/check-coverage.sh`, which fails below 90% line coverage for any guard script.
- `scripts/check-scrub-probe.sh`: run by Claude as a tool in the `scrub` job of `egress-lock-claude.yml` (from `main`); prints
  `SCRUB-PROBE env-tokens=<n> proc-tokens=<n> pid=<n>`, and the job fails unless both counts are 0.
- `claude.yml` (founder @claude mentions) answers on issues only: without a prompt the action checks out an open PR's code
  itself, and nested rule files from the PR would load.
- Messages and fixes for every check: `docs/runbooks/ci-guards.md`.
