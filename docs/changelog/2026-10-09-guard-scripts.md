# 2026-10-09 - Guard checks for skills and agent workflows, and the agent network lock (#22 split, #31)

- **Agent network lock** (`.github/actions/agent-egress-lock`, right after the checkout of `main` in every agent job):
  installs gitleaks and the pinned Claude Code and Bun binaries, each checked against a pinned sha256 (the action's own Bun
  download is not used); DNS answers only allow-listed names (since round 10 with a fixed sink address, forwarding nothing);
  a local
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
  pushes now authenticate through `gh auth setup-git`, and the manager stops unless its GitHub token belongs to the agents'
  account (`scripts/check-agent-token.sh`). The instant fix round starts only for a same-repository PR whose author has the
  agents' account ID.
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
    `Skill(<name>)` for `payload` and every third-party skill in the base or PR manifest; the manager keeps its 32 denies
    (`Skill(payload)`, `WebFetch`, `WebSearch`, 24 command denies including `gh api`, `gh gist`, `gh repo` and `yarn npm publish/login`, and 5 path denies); `secrets` only as `secrets.<NAME>`, and Claude credentials only in
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
- Messages and fixes for every check: `docs/runbooks/ci-guards.md` (overview, guards, review job, CI), with
  `docs/runbooks/skill-guards.md`, `docs/runbooks/workflow-checker.md` and `docs/runbooks/agent-network-lock.md`.
- People are matched by numeric GitHub user ID: `.github/accounts.txt` ("<id> <login> founder|agent") replaces
  `.github/founders.txt`. Guards checks the PR author and pusher IDs; workflow conditions compare IDs (the checker rejects any
  login comparison except with a bot name, and IDs that are not listed). The agents' token check requires the token to belong
  to the `agent` account and be classic with exactly `repo` (fine-grained tokens cannot cover a personal account's repo for a
  collaborator) or fine-grained with no classic scopes; it is the first step after checkout and the lock in every job that
  holds `AGENT_GH_TOKEN`.
- The lock allows exact names only (superseded in round 8: the runner's own services are allowed by exact name plus the
  run service's name pattern): the `.actions.githubusercontent.com` wildcard is gone (the runner needed none during the
  steps); a job with `id-token: write` also allows its own OIDC host for that run. It installs Node 20 before it closes,
  checks that every allowed name answers, and gives nginx room for long generated names.
- `log-patch.txt` for reviewers includes merge commits (combined diffs).
- The lock unloads the image's other AppArmor profiles that grant user namespaces (browsers, podman, lxc, ...) and removes
  the setuid bits from `newuidmap`/`newgidmap` (`podman unshare` was root with every capability in a user namespace on a
  real runner even with the profiles unloaded; the self-test now checks the helpers and `podman unshare id -u`).
- `scripts/check-claude-probe.py` decides the Claude probes (was inline Python); `scripts/check-coverage-sh.test.sh` tests
  the coverage runner, and Python coverage is compared with two decimals.
- Founder decisions on the remaining open routes, the measurements, post-merge first runs and the agents' token are proposed
  in `docs/runbooks/agent-network-lock.md` ("Founder decisions") and accepted by the merge of this PR; the pins were
  compared with the vendors' sources in the PR's session.
- **Round 8:** `main-guard.yml` (`scripts/check-main-push.sh`) reverts any non-founder push to `main`, disables the manager and
  opens a blocked security issue; the **pusher ledger** (`scripts/check-pushers.sh`: `guards/pusher` commit statuses signed
  with the `GUARDS_LEDGER_KEY` secret) records who pushed every commit, and founder-only changes now need every commit pushed
  by a founder; the agents' account must own no repository (`scripts/check-agent-token.sh`); the manager denies `gh repo`.
  The lock allows the runner's own services (`broker`, `results-receiver` and the `run-actions-<n>-azure-<region>` run
  service, measured: a locked job hung until its timeout without them) and probes every allowed name with five foreign
  Host values (`example.com`, `www.cloudflare.com`, `claude.ai`, `pypi.org`, `storage.googleapis.com`); AppArmor grants are
  searched in `/etc/apparmor.d` and snapd's folder recursively. Python packages for the guard scripts are hash-pinned (`scripts/check-python-requirements.txt`,
  `scripts/check-python-deps.sh`: PyYAML too). `scripts/check-workflows.sh` reads the manifests and `.github/accounts.txt`
  with the shared bash helpers and passes the results to Python (one parser per format). `scripts/check-testlib.sh` holds the
  test bookkeeping every `scripts/*.test.sh` shares. A loose `|` line in a vendored skill is no longer a deletable unit.
- **Round 9:** the pusher ledger is written by its own workflow `pusher-ledger.yml` (no concurrency group, the event's own
  `before..after`, never a later fetch; `guards` fails if its fetched head is not the event's head); the main guard's
  pin-mismatch fallback reverts (or restores after a force push) from the workflow file alone, with the founders' IDs
  written there; `check-main-push.sh` restores `main` after a force push and reverts first-parent commits only; the
  `oidc` lock test moved to `egress-lock-claude.yml` (main only) and the checker applies the permissions allow-list to
  every job and workflow and rejects `id-token: write` on PR triggers; the review, daily report and weekly audit jobs run
  Claude with a read-only token and hand the answer (text) to a second `post` job that holds the write scope; the lock masks
  the Docker units and its self-test checks that systemd and polkit cannot bring them back, and names a failed Claude Code
  or Bun download; `accounts_rows` rejects a user ID listed twice and `account_field` is the one lookup; `check-pushers.sh`
  treats a GitHub API error as an error, never as "no record"; coverage.py 7.16.2 and PyYAML 6.0.3 (current releases, hashes
  from PyPI); `require_pinned` is the one pin check.
- **Round 10:** every workflow but CI and the hosted lock test pins the files it runs (`.github/pins.txt`, its sha256 in the
  workflow file as `PINS_SHA256`, `scripts/check-pins.sh update`); `egress-lock-claude.yml` has no push trigger (schedule
  and founder-started runs only); the checker rejects `push` for Claude workflows and requires the pin step in every job;
  the pusher ledger runs on every push to a non-main branch (opening a PR records nothing); the main guard disables every
  secret-holding workflow and its fallback reverts inline; dnsmasq forwards nothing (sink address, the proxy resolves exact
  names; subdomains die at the proxy, self-tested); `scripts/check-claude-answer.sh` replaces the pasted jq steps and
  `check-review-post.sh` takes the answer from `ANSWER` with a `daily-reports` target; every Claude step must deny
  `WebFetch`, `WebSearch` and the `Read(//...)` paths (`claude_denies`); after its shift the manager re-checks that the
  agents' account owns no repository; tests for the remaining branches (`check-accounts-lib`, `check-pins`,
  `check-claude-answer`, empty ranges, failed pushes, diff errors); the seven remaining tests use `assert_result`.
- **Round 11:** the main guard (script and fallback) cancels every running or queued run of the workflows it disables, and
  `guards.yml` is on that list; the manager's job token is read-only (`read_only_workflows` in the policy; the agents act
  with their own token), and the pins cover `.claude/` and `CLAUDE.md`; the pin step is matched exactly (name, run and
  env), so a decoy step with the right name fails; `scripts/check-pins.sh` keeps only `update` (the list comes from
  `pins_required` in the policy; the checker verifies); the ledger records by reachability (`before..after` on a
  fast-forward, everything since the default branch on a new branch or force push, always minus what other branches
  already hold) and two valid records naming different pushers verify as `unknown`; the review prepare step refuses
  symlinks and special files; the fallback revert handles a zero `before`; `egress-lock-claude.yml`'s probe and scrub
  use the standard pin step; `lock.sh` and `check-skills.sh` are split into functions of at most 50 lines; measured:
  GitHub refuses a rewind of `main` past a workflow change even with no new commits (decision 4 in the lock runbook).
- **Round 12:** `scripts/check-agent-token.sh` also requires the four guard workflows to be active and the default branch's
  head to have a successful main-guard run (the agents' token could disable or cancel them); the manager denies
  `gh workflow`, `gh run cancel` and `gh run delete`; the pin step's third line, `bash scripts/check-pins.sh verify`, fails
  on any unlisted file of a pinned kind, and the pinned kinds now include every `CLAUDE.md`, `CLAUDE.local.md`, `.mcp.json`
  and `.claude/` file anywhere (`pins_required`); Read is allowed only under the checkout (`Read(./**)`, plus the review's
  and audit's data folders) with `/dev` and the runner's install folder denied, proved by the new `reads` probe job
  (`check-claude-probe.py read-deny`); `.gitleaks.toml` gains a rule for Claude tokens; the ledger also excludes commits
  any pull request head holds; one `pins_step_problems` rule, `check-pins.sh` reads its list from the checker library,
  the main-push test checks the stop list against every workflow holding a secret or write scope, the review poster
  takes the answer only from `ANSWER`; docs corrected (pinned-file list, step names, bytes, the ledger's messages, founder
  decisions proposed rather than recorded as accepted).

## Founder steps before and after merging this PR
1. Before merge: the repository secret `GUARDS_LEDGER_KEY` (any random string of 32+ characters) must exist, or the pusher
   ledger and the guards' ledger step fail on every PR.
2. Merge in the web UI (that also re-registers the schedules).
3. Right after merge, start `Agent egress lock - Claude probe` by hand (Actions -> Run workflow) and read its three jobs
   (founder decision 3 in `docs/runbooks/agent-network-lock.md`); a failure is a revert trigger.
4. Earlier PRs have no ledger records: re-push each open founder branch (a rebase, or one empty commit of your own) so the
   ledger records them under your ID; founder-only changes fail the guards until then.
5. Whenever a founder PR changes a pinned file (`pins_required` in `scripts/check-workflows-policy.json`: anything under
   `.github/actions/`, a `scripts/check-*` script except tests and test libraries, `.gitleaks.toml`, `.github/accounts.txt`,
   `CLAUDE.md`, any `CLAUDE.local.md` or `.mcp.json`, anything under a `.claude/` folder), run
   `bash scripts/check-pins.sh update` in that PR.
