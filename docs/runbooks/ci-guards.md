# Runbook: guards, review job and CI guard tests

**Who fixes these:** a founder makes any change to founder-only files. An agent may only **undo** an accidental change it
made to one of them, then ask with `REQUEST:` on its issue. People are identified by numeric GitHub user ID in
`.github/accounts.txt` ("<id> <login> founder|agent"; the ID is at `https://api.github.com/users/<login>`). A new founder is
added by an existing founder's PR that adds a `founder` line there (and the login to `.github/CODEOWNERS`); the agents' account
is the `agent` line.

How it fits together: `docs/architecture.md` ("CI and review"). Related runbooks: `docs/runbooks/skill-guards.md` (skill
checks), `docs/runbooks/workflow-checker.md` (workflow rules), `docs/runbooks/agent-network-lock.md` (network lock, agents'
token).

## Workflow "Guards" (job `guards`)
Runs on `pull_request_target`: GitHub always runs the copy on `main`, with `main`'s scripts and config. The PR is fetched as data.

### Step "Fetch the PR as data into /tmp/pr" fails
`ERROR: bad PR number`, `already exists`, a git fetch error, or `rule files left in /tmp/pr`. Re-run the job once; if it fails
again, tell a founder.

### Step "Founder-only files (PR author and pusher must be founders)" fails
Message: `Not all of '<author id>,<pusher id>' are founders, and the PR changes founder-only files:` plus the paths. The IDs
come from the event (the PR author and the account that triggered the run), never from the PR's files, and are compared with
the `founder` lines of the base branch's `.github/accounts.txt`.
Founder-only: `CLAUDE.md`, `CLAUDE.local.md`, `.mcp.json`, `.claude/` (in any folder), anything in `.github/`, `scripts/check-*`,
`scripts/gitleaks-config*`, `.gitleaks.toml`, `.gitleaksignore`, and `packages/data/override-allowlist.txt` (reserved, not
created yet: the reviewed system jobs that may use `overrideAccess: true`, see CLAUDE.md Payload rule 1). Renames count both ways.
Fix: undo those changes and comment `REQUEST: <path> - <change> - <why>` on the issue. If an agent pushed to a founder's PR,
the founder pushes once more after checking the agent's commits.
`accounts file not found`, `bad line <n> in <file>`, `no founder listed in <file>` / `could not diff` - the base checkout or
`.github/accounts.txt` is broken; re-run once, then a founder fixes the file on `main`.

### Steps for skills
"Skills match manifest and checksums", "Third-party skills compared with the base branch (no quiet switch to 'ours' or to
another repo)" and "Third-party skills equal their pinned upstream with deletions only (fresh fetch of the locked commit)":
every message and fix is in `docs/runbooks/skill-guards.md`.

### Step "Agent workflows keep their denies (base script, PR's workflows as data)"
Unpacks the PR's `.github/workflows` and `.github/actions` as data and runs the `main` copy of `scripts/check-workflows.sh` on
them, with both skill manifests and the base branch's `.github/accounts.txt` (so a PR cannot list itself). Every message and
fix: `docs/runbooks/workflow-checker.md`.

### Step "Secret scan of the PR's commits (base config, no ignore files, no inline allow)" fails
gitleaks found something that looks like a secret in this PR's commits (`main`'s `.gitleaks.toml`; `.gitleaksignore` and inline
`gitleaks:allow` are ignored). The log shows file, line and rule, with the secret redacted.
- **Real key: treat it as leaked even if the PR is closed.** Revoke it at the provider now (GitHub, Claude, Telnyx, Resend, AWS...),
  create a new one, store it only in GitHub secrets / Railway, and tell both founders. Deleting the commit is not enough.
- Documented fake value from vendor docs: a founder may add that exact value to `.gitleaks.toml` (anchored, `regexTarget = "secret"`)
  in a founder PR, with a case in `scripts/gitleaks-config.test.sh`.

## Workflow "Agent - Review team" (job `review`)
Also `pull_request_target`, also from `main`.
- **"Fetch the PR as data into /tmp/pr"** fails - as above. It also writes the PR's history as plain files to `/tmp/pr-meta`:
  `files.txt`, `diff-stat.txt`, `diff.patch`, `log.txt` and `log-patch.txt` (every commit's patch, merge commits as combined
  diffs); reviewers read those instead of running git. `bad base ref` / `base ref not found` / `/tmp/pr-meta already exists`
  - re-run once, then tell a founder.
- **"Wait for CI and guards on the PR head (max 30 min)"** prints `ci=<status> guards=<status>` every 30 seconds. After 30 minutes it
  passes `pending` to the reviewers, which makes the result FAIL; the review runs again on the next push. `ERROR: bad PR number`
  / `ERROR: bad head sha` (`scripts/check-pr-ci-status.sh`) - the event data is broken; re-run once.
- **"Review (read-only)"** fails or times out - the next step posts `REVIEW TEAM RESULT: FAIL` saying there was no valid result.
  Re-run the job once.
- **"Post the result (secret-scanned) and set labels"**: if the answer looked like it contained a secret, it posts FAIL without
  the text - a founder checks the job log and, if a real secret appeared, follows "Real key" above.
- **"Start a fix round now (agent PRs that failed review)"**: runs only for a PR from this repository, opened by the agents'
  account (user ID 250452267 in `.github/accounts.txt`), on an `agent/` branch. When the PR has the label `changes-requested`
  it starts `agent-manager.yml` and prints `Manager shift started for PR #<n>`; otherwise `Review passed or no result; no fix
  round needed`.

## Workflow "CI" (job `checks`), step "Guard script tests and coverage (every guard script at least 90%)"
The step runs `bash scripts/check-workflows.sh` and `bash scripts/check-coverage.sh 90`. The coverage script runs every
`scripts/*.test.sh` (it fails if a test file is missing from its `TESTS` list; `scripts/check-coverage-sh.test.sh` tests the
runner itself on a small tree). A test passes only if it exits 0 and its last line reads `<n> passed, 0 failed` with `<n>`
above 0. Then it measures line coverage:
- bash guard scripts (every `scripts/check-*.sh` except tests, plus `lock.sh`): each test run traces through a `BASH_ENV`
  hook, and `scripts/check-coverage.py` scores each command (a command that spans several lines counts once);
- Python guard scripts: coverage.py 7.6.1, installed with pinned hashes from `scripts/check-coverage-requirements.txt` into a
  private venv that is put in front of `PATH` as `python3` only for the tests.
Messages: `ERROR: <test> tests failed` (the failing test's output is printed above it), `<script> ... <-- below minimum` with
the commands that never ran, `ERROR: <script.py> line coverage N.NN% is below 90%` (two decimals, so 89.6% does not round
up), `ERROR: <file> is not in TESTS`, `ERROR: missing test <file>`, `bad minimum percent`, and `Coverage OK (every guard script
at least 90%)`. Fix: add a test case for the commands listed as not run. To see one test's cases, run it alone, for example
`bash scripts/check-egress-lock.test.sh`; `GITLEAKS=/path/to/gitleaks` is needed for `scripts/gitleaks-config.test.sh` (it
exits 2 if gitleaks can't run).
"Secret scan of all history (pushes to main)" failing means a secret reached `main`: follow "Real key" above.

## How the guards wiring is proven
The scripts have unit tests (above). `scripts/check-workflows-people.test.sh` also runs the real guards step that calls the
workflow checker on a temp checkout, so its archive paths and `--accounts` wiring are tested before merge. The rest of the
wiring (`git archive` of the PR head, base scripts on PR data, the upstream fetch) is proven by the live `guards` run: a guards
change takes effect only after it merges, so the **next** PR's guards log must show the new steps passing.

## After changing agent permissions (founder, manual)
Run one `workflow_dispatch` of the manager and check the "Show blocked tool calls (names and commands only)" step. Once vendored
skills exist (the Payload skill, #22), a `Skill(payload)` deny must not stop builders from preloading `payload` with
`payload-dealer-overrides`. If a builder reports it can't see the skill, **do not remove the deny**: open an `area:security`
issue for the founders.

## Known limits
- Agent pushes to `.github/**` cannot be blocked by a ruleset on the current plan (push rulesets need a paid plan for a
  private repo). The protection is the token: the agents' own token (classic with only `repo`, or fine-grained), which has no
  `workflow` scope (see `docs/runbooks/agent-network-lock.md`).
- The agents' own account (`mohammedaminehafidi-ctrl`, ID 250452267) exists and holds the `AGENT_GH_TOKEN` secret's token. If
  that secret ever holds a founder's or anyone else's token, the manager stops at its step "Agents must run on their own GitHub
  token, never a founder's" on every run. That is on purpose: the founder check in `guards` trusts GitHub accounts, so agents
  must never push as a founder.
- `CODEOWNERS` and required checks enforce nothing until branch protection is on (paid GitHub plan for a private repo).
- `ci.yml` runs from the PR (tests, no secrets). Anything a PR must not be able to change lives in `guards.yml` / `review.yml`.
