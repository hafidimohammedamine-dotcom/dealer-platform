# Runbook: guards, review job and CI guard tests

**Who fixes these:** a founder makes any change to founder-only files. An agent may only **undo** an accidental change it
made to one of them, then ask with `REQUEST:` on its issue. People are identified by numeric GitHub user ID in
`.github/accounts.txt` ("<id> <login> founder|agent"; the ID is at `https://api.github.com/users/<login>`). A new founder is
added by an existing founder's PR that adds a `founder` line there (and the login to `.github/CODEOWNERS`); the agents' account
is the `agent` line.

How it fits together: `docs/architecture.md` ("CI and review"). Related runbooks: `docs/runbooks/skill-guards.md` (skill
checks), `docs/runbooks/workflow-checker.md` (workflow rules), `docs/runbooks/agent-network-lock.md` (network lock, agents'
token).

## Pinned files in every workflow
Every workflow except `ci.yml` and `egress-lock-test.yml` (which run PR code on purpose, with no secrets) runs the same
step right after each checkout: `The repository files this job runs are the reviewed ones (pinned here, outside any push's
reach)`. It checks `.github/pins.txt` against the sha256 written in the workflow file (`PINS_SHA256`), then every pinned
file against `pins.txt`, then (`bash scripts/check-pins.sh verify`, a script the second line just proved) that the tree holds
no pinned-kind file `pins.txt` does not list. The pinned files are `pins_required` in `scripts/check-workflows-policy.json`:
all of `.github/actions/`, every `scripts/check-*` script except `*.test.sh` and `*testlib.sh`, `.gitleaks.toml`,
`.github/accounts.txt`, `.yarnrc.yml`, and - anywhere in the tree outside `.git`, `.worktrees` and `node_modules` - every `CLAUDE.md`,
`CLAUDE.local.md`, `.mcp.json` and every file under a `.claude/` folder (the files Claude loads from a checkout). The agents'
token cannot change workflow files, so a push that changes a pinned file, or adds an agent-instruction file, without a
founder's workflow change fails every job before any secret, sudo or Claude is used. `the pinned files do not match
.github/pins.txt (...)` lists what is wrong: a founder reviews the change and runs `update`. Steps that run a pinned script after
Claude repeat the check. A founder who changes a pinned file runs `bash scripts/check-pins.sh update` in the same PR (it
rewrites `pins.txt` and every `PINS_SHA256`); `scripts/check-pins.test.sh` and the workflow checker fail until it is done.
`pusher-ledger.yml` runs on a pushed branch but checks out the default branch, so its pin step takes the expected hash
from the default branch's own `guards.yml` instead of its env (the checker requires that exact form). Until this PR is on
`main`, that step fails on every branch (no `pins.txt` on `main` yet); it works from the first push after merge.
Failure messages: `sha256sum: WARNING: 1 computed checksum did NOT match` (a pinned file differs from the reviewed state:
either run `update` in a founder PR or, if the push was not a founder's, see "Main guard"); from the checker, `PINS_SHA256
is <x> but .github/pins.txt is <y>`, `<file> changed but its pin did not`, `does not list <file>`, `lists <file>, which is
not a pinned file`, `the step after the checkout must be the pin step`, `the pin step's run must be exactly the policy's
pins_step_run` - all fixed by `bash scripts/check-pins.sh update` or by restoring the step.

## Workflow "Guards" (job `guards`)
Runs on `pull_request_target`: GitHub always runs the copy on `main`, with `main`'s scripts and config. The PR is fetched as data.

### Step "Fetch the PR as data into /tmp/pr" fails
`ERROR: bad PR number`, `already exists`, a git fetch error, or `rule files left in /tmp/pr`. Re-run the job once; if it fails
again, tell a founder. `symlinks or special files in the PR (only regular files and folders are reviewed)` lists them: the
PR must remove them (a symlink such as `docs/x.md -> /proc/self/environ` would show a reviewer's tool the job's environment).

### Workflow "Pusher ledger" (job `record`) fails
Its own workflow (`pusher-ledger.yml`, no concurrency group, so no push is ever dropped or cancelled) runs on every push to
a branch other than `main` (the push event's sender is the account that pushed; opening a PR records nothing, so a commit
pushed before the PR existed is never credited to whoever opens it). The workflow file comes from the pushed branch (the
agents' token cannot change workflow files); the scripts come from the default branch, pinned. It records exactly the
commits GitHub's push event lists as new to the repository with this push (`commits[].distinct`; measured on 2026-10-10,
runs 38033794584, 38033796197 and 38033869617: a commit pushed once is never listed again, not even on a new branch after
the branch that held it was rewound away) as pushed by the sender (`Recording the <n> commit(s) GitHub lists as new ...`):
`scripts/check-pushers.sh record` posts one commit status `guards/pusher` (`id=<user id> mac=<40 hex>`) on every such
commit without a valid record; the mac is an HMAC-SHA256 of "<sha> <id>" with
the secret `GUARDS_LEDGER_KEY`, which nobody with the agents' token can read, so a forged or copied status never verifies.
A commit with valid records naming more than one pusher verifies as `unknown (valid records name more than one pusher)`.
`GUARDS_LEDGER_KEY is missing or shorter than 32 characters` - a founder creates that repository secret (any random string
of 32+ characters; `openssl rand -hex 32`). `could not record the pusher of <sha>` / `could not read the statuses of <sha>
(GitHub API error)` - re-run the workflow once (nothing is recorded as "unknown" on an API error). `before/after must be 40-hex commit
shas` / `could not read the push event` / `the event lists <sha>, which is not on the pushed branch` - the event is
inconsistent; re-run once (a fresh push: see "Re-runs" below), then tell a founder. `the push event lists 2048 commits
(GitHub's limit)` - push in smaller batches. `branch deleted; nothing to record` is normal. Known limit: a commit that
reached GitHub without a ledger run (pushed before the ledger existed, with `[skip ci]` in its head commit's message, or
with its run cancelled) stays unknown for good: GitHub never lists it as new again, so re-pushing it records nothing. For a
founder-only change that is the point (an agent's unrecorded commit can never be credited to a founder); to get such
commits through, a founder makes new ones (a rebase or a squash) and answers for them.

### Re-runs and `[skip ci]`
Every job that holds a secret runs only on a run's first attempt (`github.run_attempt == '1'`): a re-run keeps the original
commit and workflow file but gets today's secrets, so re-running an old run would hand a current token to code that
predates the guards (the secrets were renamed to `..._V2` for the same reason). To run something again, push again or start
a fresh `workflow_dispatch`; a re-run of a secret-holding job is skipped. A push whose head commit message contains
`[skip ci]`, `[ci skip]`, `[no ci]`, `[skip actions]` or `[actions skip]` starts no push workflow at all - no ledger run
(the commits stay unknown, above) and no main-guard run; for `main` the next main-guard run, or the hourly scheduled one,
finds that push unchecked and stops the agents (see "Main guard").

### Step "Who pushed each commit (from the ledger written by pusher-ledger.yml)"
First `the fetched PR head is not this event's head sha (...); the PR moved, see the newer run` - this run judges only the
head its event names; the newer push has its own run. Then `scripts/check-pushers.sh verify` prints `<sha> <id>
<founder|agent|unknown>` per commit, or `<sha> - unknown` when no status carries a valid mac (none, deleted, or forged);
`could not read the statuses of <sha>` is a GitHub API error (re-run once); `GUARDS_LEDGER_KEY is missing: a founder sets
this GitHub secret` - create the secret (above); `could not list commits <base>..<head>` - the base or head ref is not in
the checkout (re-run once, then a founder looks). The next step uses the list.

### Step "Founder-only files (PR author and every pusher must be founders)" fails
Message: `Not all of '<author id>,<pusher id>' are founders, and the PR changes founder-only files:` plus the paths. The IDs
come from the event (the PR author and the account that triggered the run), never from the PR's files, and are compared with
the `founder` lines of the base branch's `.github/accounts.txt`. Or: `Commits not pushed by a founder (sha, pusher ID, role;
'-' = no pusher record), and the PR changes founder-only files:` - the author and the last pusher are founders, but a commit
in the PR was pushed by someone else, or has no record (pushed before the ledger existed, or its statuses were removed). A
founder rebases those commits out and re-creates the changes in commits of their own, then pushes. `pushers file not found` -
the previous step did not run; re-run the job.
Founder-only: `CLAUDE.md`, `CLAUDE.local.md`, `.mcp.json`, `.claude/` (in any folder), anything in `.github/`, `scripts/check-*`,
`scripts/gitleaks-config*`, `.gitleaks.toml`, `.gitleaksignore`, `packages/data/override-allowlist.txt` (reserved, not
created yet: the reviewed system jobs that may use `overrideAccess: true`, see CLAUDE.md Payload rule 1), `.yarnrc.yml` and
`.yarn/` (lifecycle scripts stay off) and `.gitattributes` (in any folder: the guards read every PR tree with attributes off,
and an `export-ignore` must not hide a file from them). Renames count both ways.
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

### Step "Agent workflows keep their denies and pins (base script, the PR's tree as data)"
Unpacks the PR head's whole tree as data (`git archive`, into `/tmp/pr-wf`) and runs the `main` copy of `scripts/check-workflows.sh`
on it, with both skill manifests and the base branch's `.github/accounts.txt` (so a PR cannot list itself). Every message and
fix: `docs/runbooks/workflow-checker.md`.

### Step "Secret scan of the PR's commits (base config, no ignore files, no inline allow)" fails
gitleaks found something that looks like a secret in this PR's commits (`main`'s `.gitleaks.toml`; `.gitleaksignore` and inline
`gitleaks:allow` are ignored). The log shows file, line and rule, with the secret redacted.
- **Real key: treat it as leaked even if the PR is closed.** Revoke it at the provider now (GitHub, Claude, Telnyx, Resend, AWS...),
  create a new one, store it only in GitHub secrets / Railway, and tell both founders. Deleting the commit is not enough.
- Documented fake value from vendor docs: a founder may add that exact value to `.gitleaks.toml` (anchored, `regexTarget = "secret"`)
  in a founder PR, with a case in `scripts/gitleaks-config.test.sh`.
- Rule `anthropic-claude-token` (`sk-ant-<kind><nn>-...`) is ours: gitleaks 8.18's default rules match neither a Claude OAuth
  token nor an API key (measured), and the same config scans every answer before it is posted.

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
- The `review` job runs Claude with a read-only token; its last step runs the pinned `scripts/check-claude-answer.sh`,
  which prints the blocked tool calls and hands the answer (text, at most 60000 bytes) to the job `post` as a job
  output. `post` is the only job with write scopes and runs no Claude: `scripts/check-review-post.sh pr <n>` reads the
  answer from `ANSWER`, scans it, posts it and sets labels. The daily report and weekly audit do the same with
  `check-review-post.sh daily-reports` (the open "Daily reports" issue, created if missing), and "Claude on mention"
  (`claude.yml`: a founder's `@claude` comment on an issue) with `check-review-post.sh issue <n>` - Claude gets a prompt
  naming the issue (never tag mode, so the action adds no comment or git tools and swaps no OIDC token), reads the thread
  with `gh issue view`, and its answer is posted by the `post` job after the scan. The daily and weekly runs, like the
  manager's, start only from their schedule or a founder's manual run. The weekly audit has a `deps` job first (no secret)
  that runs `yarn npm audit` and uploads `npm-audit.json`; the `audit` job downloads it as data.
- **"The default branch's head passed the main guard"** (every Claude job, before the lock: `scripts/check-main-head.sh`)
  fails with `the default branch's head (<sha>) has no successful main-guard run (...)` - the push that put that head on
  `main` was never checked (a `[skip ci]` head commit, a cancelled run): a founder looks before any Claude job runs again
  (see "Main guard"); `the main-guard run for <sha> has not finished after 120s` - right after a merge, start a fresh run.
- **"Post the result (secret-scanned) and set labels"** (job `post`): if the answer looked like it contained a secret, it
  posts FAIL without the text - a founder checks the job log and, if a real secret appeared, follows "Real key" above.
- **"Start a fix round now (agent PRs that failed review)"** (job `post`): runs only for a PR from this repository, opened by the agents'
  account (user ID 250452267 in `.github/accounts.txt`), on an `agent/` branch. When the PR has the label `changes-requested`
  it starts `agent-manager.yml` and prints `Manager shift started for PR #<n>`; otherwise `Review passed or no result; no fix
  round needed`.

## Workflow "CI" (job `checks`), step "Guard script tests and coverage (every guard script at least 90%)"
The step (after "Pinned Python packages for the guard scripts", above) runs `bash scripts/check-workflows.sh` and
`bash scripts/check-coverage.sh 90`. The coverage script runs every
`scripts/*.test.sh` (it fails if a test file is missing from its `TESTS` list; `scripts/check-coverage-sh.test.sh` tests the
runner itself on a small tree). The Python packages come from PyPI with `--require-hashes`, so this step and
`scripts/check-python-deps.test.sh` need network access to `pypi.org` (GitHub's runners have it; an offline run fails at
the install, which is unrelated to the code - founder decision: no vendored wheels until a mirror exists). A test passes only if it exits 0 and its last line reads `<n> passed, 0 failed` with `<n>`
above 0. Then it measures line coverage:
- bash guard scripts (every `scripts/check-*.sh` except tests, plus `lock.sh`): each test run traces through a `BASH_ENV`
  hook, and `scripts/check-coverage.py` scores each command (a command that spans several lines counts once);
- Python guard scripts: coverage.py 7.16.2 (with PyYAML 6.0.3), installed with pinned hashes from
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
Runs on every push to `main`, hourly (`schedule`) and by hand (`workflow_dispatch`, below). First, every push or scheduled
run checks the chain: the previous push's head (hourly: `main`'s head) must have passed the main guard itself (`Chain: ok
<sha> passed the main guard` - a successful run started by a push; the schedule and by-hand runs of the same commit do not
count, so the hourly run never finds itself; `Chain: ok <sha> carries the guards/main-guard status (...)` - the commit status
below; or `Chain: ok <sha> is on the default branch before the main guard existed (floor <sha>)`: the floor is
`MAIN_GUARD_FLOOR` in `scripts/check-github-lib.sh`, main's head when the guard was written, and a commit passes without a
run only if GitHub's compare API says it is an ancestor of it). `commit <sha> reached main without passing the main guard
(missing <sha> (runs: ...))` means a push whose head commit said `[skip ci]` (no run at all), a run someone cancelled, or
the workflow disabled at the time: the job cancels and disables the secret-holding workflows and opens `SECURITY: a push to
main passed no main-guard run (commit <sha>)` without reverting anything (it cannot tell what that push contained);
founders read that commit and the pushes after it (`git log --first-parent`), revert what should not be there, rotate
`AGENT_GH_TOKEN_V2` if the agents' account pushed it, **accept the commit** and re-enable the workflows. `the main-guard
run for <sha> has not finished after 120s; re-run this job later` - the previous run is still going (rare; the hourly run
will check).

**The `guards/main-guard` commit status** stands in for a run on commits that can have none: the revert commit the guard
pushes (a push made with a workflow's token starts no workflow) is marked right after the push (`revert by main-guard run
<id>`), and a commit a founder has read is marked by running the workflow by hand: Actions -> Main guard -> Run workflow,
`accept_sha` = the 40-hex sha (`Accepted: commit <sha> now carries the guards/main-guard status (founder ID <id>)`). The
script posts the status only when the account that started the run is a `founder` row (`only a founder may accept a
commit; user ID <id> is not one` - the agents' token can start the workflow, but is refused) and only for a commit on
`main` (`is not on main (this checkout)`). The chain check accepts the status only when its creator is github-actions[bot]
(user ID 41898282): a status the agents' token posts carries the agents' account as creator, and the workflow checker lets
`statuses: write` into `main-guard.yml` and `pusher-ledger.yml` only, whose scripts are pinned. `could not be marked with
the guards/main-guard status` - the revert went up but the status post failed; the next run flags the revert commit as
unchecked, and a founder accepts it by hand. A re-run of a main-guard job, or a run whose push `main` has already moved past,
reverts nothing (`main is no longer at <sha> (a later push, or a re-run of this job); nothing reverted`): reverting the same
commits again would put them back. Then `scripts/check-main-push.sh` compares the
pusher's user ID with the `founder` rows: a founder's push (every merge) prints `Push to main by founder '<login>' (ID <id>): OK.` Any other push means guards, review and founder
approval were bypassed (the agents' token can push to `main`; the free plan cannot block it): the job prints `::error::push to
main by user ID <id> ...`, reverts the pushed first-parent commits with new commits (a merge commit against its first parent;
never a force push), pushes the reverts with its own token (which starts no workflow), cancels every running or queued run
of the eight workflows that hold a secret or judge pushes (the manager, review team, founder mentions, daily report, weekly
audit, the Claude lock probe, the pusher ledger and guards) and disables them (`cancelled <n> running or queued run(s);
disabled ...`) so nothing runs tampered code with a token even if the revert failed, and opens an issue `SECURITY: non-founder push to main
by user ID <id>` labeled `area:security`, `blocked`, `priority:1`, mentioning the founders. Founders then: read what the
pushed commits contained, check the repositories the pusher's account owns, rotate `AGENT_GH_TOKEN_V2` if the agents' account
was involved, and re-enable the workflows (Actions -> each workflow -> Enable).
`revert of <sha> did not apply cleanly` / `the revert could not be pushed` / `could not disable` / `could not open the security
issue` - the job did what it could and prints the rest; a founder finishes by hand. A force push is undone by putting
`main` back to the previous tip (`main was force-pushed and could not be restored` means a founder does it by hand); the
guard restores only a tip that passed the main guard itself (the chain check runs first), never an unchecked commit.
Because the push itself could have changed the script, its library or `.github/accounts.txt`, the job's pin step (above)
runs first; on a mismatch, the fallback step - written in the workflow file alone, with the founders' user IDs - undoes the
push the same way (revert or restore), cancels and disables the same workflows and opens `SECURITY: push to main changed pinned files`;
if the pusher was a founder it only fails with `pinned files changed by a founder's push ... run scripts/check-pins.sh
update`. `scripts/check-main-push.test.sh` checks the fallback's condition, IDs, labels and that its workflow list equals
the script's.

## After changing agent permissions (founder, manual)
Run one `workflow_dispatch` of the manager and check the "Show blocked tool calls (names and commands only, pinned script)" step. Once vendored
skills exist (the Payload skill, #22), a `Skill(payload)` deny must not stop builders from preloading `payload` with
`payload-dealer-overrides`. If a builder reports it can't see the skill, **do not remove the deny**: open an `area:security`
issue for the founders.

## Known limits
- Pushes by the agents' account cannot be blocked by a ruleset on the current plan (rulesets for a private repo need a paid
  plan). What holds instead: the token has no `workflow` scope (it cannot change `.github/workflows/`); a non-founder push to
  `main` is reverted by "Main guard" (above) and stops the agents; founder-only changes need every commit pushed by a founder
  (the pusher ledger); the agents' account may own no repository, the four guard workflows must be active and the default
  branch's head must have passed the main guard (`scripts/check-agent-token.sh`, start of every shift and again in the
  manager's job `after`: the token could disable those workflows or cancel their runs, and this is what turns that into a
  visible failure); and the agents' account must have no event outside this repository in the last 24 hours
  (`scripts/check-agent-events.sh`, before each shift and again in job `after`: the token can comment on or open issues
  in any repository it can see; a rolling day rather than "since the shift started" because the events feed can lag, so
  the check before the next shift sees what this one missed). Job `after` is a fresh runner (`needs: shift`,
  `if: always() && github.run_attempt == '1'`), because the shift's Claude runs with bypassPermissions
  and could have written its own job's `$GITHUB_ENV` or `$GITHUB_PATH`; inside Actions both scripts ignore every
  environment override (`GH_BIN`, `GH_REPO`, `GUARD_WORKFLOWS`, `AGENT_TOKEN_WAIT`) and take gh from PATH and the
  repository from `GITHUB_REPOSITORY`. `the agents' account '<login>' acted outside <repo> since <time>:` lists the
  events: a founder reads what was posted where, rotates `AGENT_GH_TOKEN_V2` and checks the shift's log; `could not read the
  events of '<login>'` - start a fresh run. Founder decisions 1 and 4 in `docs/runbooks/agent-network-lock.md`.
- The agents' own account (`mohammedaminehafidi-ctrl`, ID 250452267) exists and holds the `AGENT_GH_TOKEN_V2` secret's token. If
  that secret ever holds a founder's or anyone else's token, the manager stops at its step "Agents must run on their own GitHub
  token, never a founder's" on every run. That is on purpose: the founder check in `guards` trusts GitHub accounts, so agents
  must never push as a founder.
- `CODEOWNERS` and required checks enforce nothing until branch protection is on (paid GitHub plan for a private repo).
- `ci.yml` runs from the PR (tests, no secrets). Anything a PR must not be able to change lives in `guards.yml` / `review.yml`.
