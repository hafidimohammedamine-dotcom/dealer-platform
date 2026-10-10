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

### Step "Record who pushed the new commits (pusher ledger, signed statuses)" fails
Runs on `opened` and `synchronize` events only (their sender is the account that pushed). `scripts/check-pushers.sh record`
posts one commit status `guards/pusher` (`id=<user id> mac=<40 hex>`) on every commit of the PR that has no valid record
yet; the mac is an HMAC-SHA256 of "<sha> <id>" with the secret `GUARDS_LEDGER_KEY`, which nobody with the agents' token can
read, so a forged or copied status never verifies. `GUARDS_LEDGER_KEY is missing or shorter than 32 characters` - a founder
creates that repository secret (any random string of 32+ characters; `openssl rand -hex 32`). `could not record the pusher of
<sha>` - GitHub refused the status; re-run once. The job's concurrency never cancels a run in progress, so every push is
recorded. Known limit: commits pushed before the ledger existed have no record (see the next step).

### Step "Who pushed each commit (from the ledger)"
`scripts/check-pushers.sh verify` prints `<sha> <id> <founder|agent|unknown>` per commit, or `<sha> - unknown` when no
status carries a valid mac (none, deleted, or forged). It never fails by itself; the next step uses the list.
`GUARDS_LEDGER_KEY is missing` - as above.

### Step "Founder-only files (PR author and every pusher must be founders)" fails
Message: `Not all of '<author id>,<pusher id>' are founders, and the PR changes founder-only files:` plus the paths. The IDs
come from the event (the PR author and the account that triggered the run), never from the PR's files, and are compared with
the `founder` lines of the base branch's `.github/accounts.txt`. Or: `Commits not pushed by a founder (sha, pusher ID, role;
'-' = no pusher record), and the PR changes founder-only files:` - the author and the last pusher are founders, but a commit
in the PR was pushed by someone else, or has no record (pushed before the ledger existed, or its statuses were removed). A
founder rebases those commits out and re-creates the changes in commits of their own, then pushes. `pushers file not found` -
the previous step did not run; re-run the job.
Founder-only: `CLAUDE.md`, `CLAUDE.local.md`, `.mcp.json`, `.claude/` (in any folder), anything in `.github/`, `scripts/check-*`,
`scripts/gitleaks-config*`, `.gitleaks.toml`, `.gitleaksignore`, and `packages/data/override-allowlist.txt` (reserved, not
created yet: the reviewed system jobs that may use `overrideAccess: true`, see CLAUDE.md Payload rule 1). Renames count both ways.
Fix: undo those changes and comment `REQUEST: <path> - <change> - <why>` on the issue. If an agent pushed to a founder's PR,
the founder pushes once more after checking the agent's commits.
`accounts file not found`, `bad line <n> in <file>`, `no founder listed in <file>` / `could not diff` - the base checkout or
`.github/accounts.txt` is broken; re-run once, then a founder fixes the file on `main`.

### Step "Pinned Python packages for the guard scripts (hash-checked)" fails
`scripts/check-python-deps.sh` installs PyYAML and coverage.py from `scripts/check-python-requirements.txt` into a private
venv with `--require-hashes` (no system site-packages) and puts its `bin` on `PATH` for the following steps (CI does the same).
`could not install the pinned Python packages from <file> (hashes must match the pinned wheels)` - a hash in the requirements
file does not match the wheel for this runner's Python; take the sha256 from `https://pypi.org/pypi/<name>/<version>/json`
(cp312 and cp313 manylinux x86_64 wheels). `could not create the venv`, `requirements file not found`, `venv dir must be an
absolute path` - the runner or the call is broken; re-run once, then a founder looks.

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
- **"Review (read-only)"** fails or times out - the post step runs only when the action produced an execution file; when
  it did, it posts `REVIEW TEAM RESULT: FAIL` saying there was no valid result. If no result comment appears and no label
  changed, re-run the job once; a PR cannot get `ready-to-merge` without a posted PASS.
- **"Post the result (secret-scanned) and set labels"**: if the answer looked like it contained a secret, it posts FAIL without
  the text - a founder checks the job log and, if a real secret appeared, follows "Real key" above.
- **"Start a fix round now (agent PRs that failed review)"**: runs only for a PR from this repository, opened by the agents'
  account (user ID 250452267 in `.github/accounts.txt`), on an `agent/` branch. When the PR has the label `changes-requested`
  it starts `agent-manager.yml` and prints `Manager shift started for PR #<n>`; otherwise `Review passed or no result; no fix
  round needed`.

## Workflow "CI" (job `checks`), step "Guard script tests and coverage (every guard script at least 90%)"
The step (after "Pinned Python packages for the guard scripts", above) runs `bash scripts/check-workflows.sh` and
`bash scripts/check-coverage.sh 90`. The coverage script runs every
`scripts/*.test.sh` (it fails if a test file is missing from its `TESTS` list; `scripts/check-coverage-sh.test.sh` tests the
runner itself on a small tree). A test passes only if it exits 0 and its last line reads `<n> passed, 0 failed` with `<n>`
above 0. Then it measures line coverage:
- bash guard scripts (every `scripts/check-*.sh` except tests, plus `lock.sh`): each test run traces through a `BASH_ENV`
  hook, and `scripts/check-coverage.py` scores each command (a command that spans several lines counts once);
- Python guard scripts: coverage.py 7.6.1 (with PyYAML 6.0.2), installed with pinned hashes from
  `scripts/check-python-requirements.txt` by `scripts/check-python-deps.sh` into a private venv (no system site-packages) that
  is put in front of `PATH` as `python3` only for the tests.
Messages: `ERROR: <test> tests failed` (the failing test's output is printed above it), `<script> ... <-- below minimum` with
the commands that never ran, `ERROR: <path to script.py> line coverage N.NN% is below 90%` (two decimals, so 89.6% does not
round up), `ERROR: <file> is not in TESTS`, `ERROR: missing test <file>`, `bad minimum percent`, and `Coverage OK (every guard script
at least 90%)`. Fix: add a test case for the commands listed as not run. To see one test's cases, run it alone, for example
`bash scripts/check-egress-lock.test.sh`; `GITLEAKS=/path/to/gitleaks` is needed for `scripts/gitleaks-config.test.sh` (it
exits 2 if gitleaks can't run).
"Secret scan of all history (pushes to main)" failing means a secret reached `main`: follow "Real key" above.

## How the guards wiring is proven
The scripts have unit tests (above). `scripts/check-workflows-people.test.sh` also runs the real guards step that calls the
workflow checker on a temp checkout, so its archive paths and `--accounts` wiring are tested before merge. The rest of the
wiring (`git archive` of the PR head, base scripts on PR data, the upstream fetch) is proven by the live `guards` run: a guards
change takes effect only after it merges, so the **next** PR's guards log must show the new steps passing.

## Workflow "Main guard" (job `guard`)
Runs on every push to `main`. `scripts/check-main-push.sh` compares the pusher's user ID with the `founder` rows: a founder's
push (every merge) prints `Push to main by founder '<login>' (ID <id>): OK.` Any other push means guards, review and founder
approval were bypassed (the agents' token can push to `main`; the free plan cannot block it): the job prints `::error::push to
main by user ID <id> ...`, reverts the pushed commits with new commits (a merge commit against its first parent; never a force
push), pushes the reverts with its own token (which starts no workflow), disables `agent-manager.yml` and opens an issue
`SECURITY: non-founder push to main by user ID <id>` labeled `area:security`, `blocked`, `priority:1`, mentioning the
founders. Founders then: read what the pushed commits contained, check the repositories the pusher's account owns, rotate
`AGENT_GH_TOKEN` if the agents' account was involved, and re-enable the manager (Actions -> Agent - Manager shift -> Enable).
`revert of <sha> did not apply cleanly` / `the revert could not be pushed` / `could not disable` / `could not open the security
issue` - the job did what it could and prints the rest; a founder finishes by hand. Because the push itself could have
changed the script, its library or `.github/accounts.txt`, the workflow pins all three by sha256 (step "The guard's own
inputs are the reviewed ones"); on a mismatch it disables the manager and opens `SECURITY: push to main changed the main
guard's inputs` from the workflow file alone. A founder PR that changes any of the three updates the pins in
`main-guard.yml` (the test `scripts/check-main-push.test.sh` fails until they match).

## After changing agent permissions (founder, manual)
Run one `workflow_dispatch` of the manager and check the "Show blocked tool calls (names and commands only)" step. Once vendored
skills exist (the Payload skill, #22), a `Skill(payload)` deny must not stop builders from preloading `payload` with
`payload-dealer-overrides`. If a builder reports it can't see the skill, **do not remove the deny**: open an `area:security`
issue for the founders.

## Known limits
- Pushes by the agents' account cannot be blocked by a ruleset on the current plan (rulesets for a private repo need a paid
  plan). What holds instead: the token has no `workflow` scope (it cannot change `.github/workflows/`); a non-founder push to
  `main` is reverted by "Main guard" (above) and stops the agents; founder-only changes need every commit pushed by a founder
  (the pusher ledger); the agents' account may own no repository (`scripts/check-agent-token.sh`). Founder decision 4 in
  `docs/runbooks/agent-network-lock.md`.
- The agents' own account (`mohammedaminehafidi-ctrl`, ID 250452267) exists and holds the `AGENT_GH_TOKEN` secret's token. If
  that secret ever holds a founder's or anyone else's token, the manager stops at its step "Agents must run on their own GitHub
  token, never a founder's" on every run. That is on purpose: the founder check in `guards` trusts GitHub accounts, so agents
  must never push as a founder.
- `CODEOWNERS` and required checks enforce nothing until branch protection is on (paid GitHub plan for a private repo).
- `ci.yml` runs from the PR (tests, no secrets). Anything a PR must not be able to change lives in `guards.yml` / `review.yml`.
