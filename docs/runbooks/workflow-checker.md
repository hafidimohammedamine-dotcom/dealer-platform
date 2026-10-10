# Runbook: workflow checker (`scripts/check-workflows.sh`)

Runs in the `guards` step "Agent workflows keep their denies and pins (base script, the PR's tree as data)" (the `main` copy,
on the PR head's whole tree unpacked as data with `git archive`, with the base branch's `.github/accounts.txt`), and in CI inside the step "Guard
script tests and coverage (every guard script at least 90%)" (the PR's own copy). Overview: `docs/runbooks/ci-guards.md`.

`scripts/check-workflows.sh` reads the skill manifests (`manifest_entries` from `scripts/check-skills-lib.sh`) and
`.github/accounts.txt` (`accounts_rows` from `scripts/check-accounts-lib.sh`), the same helpers every other guard uses, and
hands the third-party names and the validated account rows to `scripts/check-workflows.py` (general rules) with
`scripts/check-workflows-claude.py` (rules for jobs with a claude step) and `scripts/check-workflows-people.py` (who may start
what, and the agents' token check); all use `scripts/check-workflows-lib.py` (the policy lists from
`scripts/check-workflows-policy.json`, the error list and the secrets checks). Python needs PyYAML, installed hash-pinned by
`scripts/check-python-deps.sh` (guards and CI add its venv to `PATH` first). It parses every workflow and every composite action in `.github/actions/` as YAML (duplicate
keys rejected), fails closed, and prints `Workflow denies OK (Skill denies: ...)` when everything holds. Because `guards` runs
the `main` copy, a PR cannot switch it off. Every message, with its fix:

Files and arguments
- `PyYAML is missing; run through the venv from scripts/check-python-deps.sh (pinned in scripts/check-python-requirements.txt)`
  - guards and CI put that venv's `bin` on `PATH` first; locally run `bash scripts/check-python-deps.sh` and use the printed
  folder's `python3`, or install PyYAML yourself.
- `cannot read check-workflows-policy.json (...)` - restore the founder-owned policy file next to the script.
- `bad argument '<x>'`, `--manifest needs a file`, `--accounts needs a file`, `manifest not found: <file>` - guards passes both
  manifests and the base branch's accounts file; an explicit manifest must exist. `run through scripts/check-workflows.sh` -
  `check-workflows.py` was started directly; the wrapper supplies the parsed manifests and accounts.
- `accounts file not found: <file>`, `bad line <n> in <file> (want '<id> <login> founder|agent')`, `no founder listed in
  <file>` - fix `.github/accounts.txt` (see `docs/runbooks/ci-guards.md`, "Who fixes these").
- `no workflows folder <dir>`, `no workflow files in <dir>` - wrong root folder.
- `<file>: not valid YAML or has duplicate keys (...)`, `no jobs mapping`, `<job>: not a mapping`, `steps must be a list`,
  `step <n>: not a mapping`, `'with' must be a mapping` - malformed workflow; fix the YAML.

Any workflow or composite action
- `.github/pins.txt is missing`, `<file> changed but its pin did not`, `does not list <file>`, `lists <file>, which is not
  a pinned file`, `line <n>: want '<sha256>  <path>'` - the pins file must list exactly `pins_required` from the policy: all
  of `.github/actions/`, every `scripts/check-*` script (not tests or test libraries), `.gitleaks.toml`,
  `.github/accounts.txt`, `.yarnrc.yml`, and every `CLAUDE.md`, `CLAUDE.local.md`, `.mcp.json` and `.claude/` file anywhere
  outside `.git`, `.worktrees` and `node_modules`, with their current sha256 (`bash scripts/check-pins.sh verify` applies the same rule in
  every pin step): `bash scripts/check-pins.sh update`. `no actions/checkout step (every job outside pins_exempt ...)`, `the step after
  the checkout must be the pin step '...'`, `the pin step's run must be exactly the policy's pins_step_run`, `PINS_SHA256 is
  <x> but .github/pins.txt is <y>`, `the pin step may only have name, env (PINS_SHA256), run and id` - every job in a workflow
  outside `pins_exempt` (`ci.yml`, `egress-lock-test.yml`) checks out and then runs the exact pin step from the policy
  (`pins_step_name`, `pins_step_run`) with the current hash; a step is the pin step only when its name, run and env match
  exactly (plus an optional `id`), so a decoy with the right name is reported as a wrong pin step; `update` rewrites the hash. `the pin step's run must be
  exactly the policy's pins_step_run_default_branch` / `may only have name, run and id` - a workflow in
  `pins_default_branch_workflows` (`pusher-ledger.yml`) reads the hash from the default branch's `guards.yml`.
- `github_token must be exactly ${{ github.token }} (...)` (`${{ secrets.AGENT_GH_TOKEN_V2 }}` in the manager; policy
  `claude_github_token`) - every Claude step passes the job's own token; without one, claude-code-action trades the job's
  OIDC token for an app token that the job's `permissions:` block does not limit. With it, `id-token: write` is needed
  nowhere but the probe workflow's `oidc` job (`per_file_permission_scopes`).
- `needs a job 'after' that runs the after-shift checks on a fresh runner`, `must have needs: shift and if: always()`,
  `must run exactly '<script>'`, `after Claude ran, the event check belongs in job 'after' only`, `the event check before
  the shift must run exactly '...'` (policy `after_shift`) - the manager's checks that run after Claude
  (`scripts/check-agent-token.sh`, `scripts/check-agent-events.sh`) live in their own job, which the shift's Claude
  (bypassPermissions) cannot have touched; the event check may also run in the shift job before Claude, with the same
  24-hour window.
- `holds a secret, so its 'if' must contain github.run_attempt == '1' (a re-run of an old run would get today's secrets)`
  (policy `rerun_guard`) - every job whose body mentions `secrets.` runs only on a run's first attempt: a re-run keeps the
  original commit and workflow file but gets today's secrets.
- `stop_workflows in the policy must be every workflow holding a secret or a write scope (except main-guard.yml): ...`,
  `main-guard.yml: the fallback step's 'for w in ...' list must be exactly the policy's stop_workflows`,
  `scripts/check-main-push.sh: the MAIN_GUARD_WORKFLOWS default must be exactly the policy's stop_workflows` - the list of
  workflows the main guard cancels and disables after a bad push lives once in the policy; a new workflow with a secret or
  write scope must be added there (the checker's own fixtures, `checker_test_fixtures`, are left out).
- `a workflow with a claude step must not run on push` - a push trigger would run freshly pushed code next to a Claude
  token before the main guard could act; use schedule or a founder-gated `workflow_dispatch`.
- `--disallowedTools does not deny <x> (every claude step must)` - every Claude step denies the policy's `claude_denies`
  (`WebFetch`, `WebSearch`, the `Read(//...)` paths: `/proc`, `/sys`, `/dev`, `/etc`, the runner's `_temp`, dot-folders
  and `runners` install folder, and `Read(./.git/**)`), not only the manager; `missing deny <x>` - the manager's own
  `manager_denies` (27 command denies) come on top.
- `runs-on must be ubuntu-latest or ['self-hosted', 'agents']` - a job runs either on GitHub's Ubuntu runner (the short checks,
  inside the free minutes) or on the agents' runners with exactly that label list. `a self-hosted job must use runs-on:
  ['self-hosted', 'agents']` - a bare `self-hosted`, the `agents` label alone or an extra label would let a job land on another
  machine. `runs-on must be a plain string or list of labels` - no expressions (`${{ vars.X }}`) and no missing `runs-on`.
- `secrets used other than as secrets.<NAME> outside a claude step's claude_code_oauth_token` - no `secrets['x']`,
  `secrets[format(...)]`, `toJSON(secrets)`, `join(secrets)` or the whole object anywhere.
- `Claude/Anthropic credential secrets.<NAME> ...` / `Claude/Anthropic credential variable ...` - a secret named
  *CLAUDE*/*ANTHROPIC*, `ANTHROPIC_API_KEY` or `CLAUDE_CODE_OAUTH_TOKEN` appears outside a claude step's
  `claude_code_oauth_token` (also inside `.github/actions/*`).
- `runs Claude outside the pinned claude-code-action` - no `claude` CLI (any path), `@anthropic-ai/...` or other claude-code
  action in `run:` or `uses:`.
- `local action not on the allow-list: <x>` (only `install-gitleaks` and `agent-egress-lock`), `not allowed: docker://...` or a
  workflow file, `reusable workflow not allowed`, `'container' not allowed`, `'services' not allowed`.
- `.github/actions/<x>/action.yml: not a composite action with steps`; `... step <n>: action must be pinned to a full commit
  SHA: <uses>` - local actions are composite, and every remote action in them is pinned by a 40-character commit.

Workflows with a claude step
- `no workflow-level env in a workflow with a claude step (use the job's env)` - move the names into the job's `env`.
- `a workflow with a claude step must not run on pull_request` / `... on workflow_run` (PR code or its artifacts next to a
  Claude token).
- `expected exactly one claude step in agent-manager.yml (found N)`; `agent-manager.yml: missing deny <item>` - the manager keeps
  every deny in `manager_denies`.

Who may start what, and the agents' token (any workflow)
- `<where>: refers to a login in 'if' (logins can be re-registered); compare the numeric user ID` - no `github.actor`,
  `github.triggering_actor` or `*.login` in an `if`, in any spelling or order, except compared with a bot name such as
  `'github-actions[bot]'` (bot names cannot be registered).
- `<where>: user ID <n> is not in .github/accounts.txt` - every user ID an `if` compares must be listed (founder or agent).
- `<where>: compare user IDs only as '<user id> == <number>' (no contains/fromJSON/variables)`.
- `<file>: must let only a founder account start it` / `... an agent account ...` - the workflows in `id_gated` keep an `if`
  comparing a founder's ID (`agent-manager.yml`, `claude.yml`, `agent-daily-report.yml`, `agent-weekly-audit.yml`,
  `egress-lock-claude.yml`) or the agents' ID (`review.yml`, fix rounds).
- `<job>: holds the agents' token, so its first step after checkout and the lock must run 'bash scripts/check-agent-token.sh
  .github/accounts.txt'` - every job that mentions `AGENT_GH_TOKEN_V2` (any case), and the manager always, checks the token
  first (`docs/runbooks/agent-network-lock.md`, "The agents' GitHub token"). `the agents' token check step may only have name
  and run (found ...)` - no `if`, `env`, `continue-on-error` or `working-directory` on it. `<file>: the agents' token may only be
  set in a job's env, after its token check` - never at workflow level.

Jobs with a claude step
- `a job with a claude step must start with actions/checkout, the pin step, 'bash scripts/check-main-head.sh' (name and
  run only), then ./.github/actions/agent-egress-lock`; `the ./.github/actions/agent-egress-lock step may only have
  id/uses/name (found ...)`; `... step needs an id` - checkout, the pin step, the main-head check (the checked-out head of
  the default branch passed the main guard: a push whose head said `[skip ci]` has no run and must not run next to a Claude
  token; policy `main_head_guard`), then the bare lock step (no `with`, `env`, `if` or `continue-on-error`, so its test
  hooks cannot be set).
- `a run step before the claude step must be one line 'bash scripts/check-<name>.sh ...' (a pinned guard), not: ...` /
  `may only have name/if/id/run/env`; `before the claude step only <actions> may be used (found ...)` / `<action> may only
  have name/if/id/with and the inputs ...` - between the lock and the claude step nothing free-form runs: every `run` is
  one line calling a pinned `scripts/check-*.sh` with plain arguments (no `&&`, `;`, pipes, redirections, backticks or
  `$(...)`, except the one substitution in `pre_claude_run_allowed_substitutions`, the events check's 24-hour window), and
  every `uses` is in `pre_claude_actions` (`actions/download-artifact`, pinned, inputs `name` and `path` only: a downloaded
  artifact is data). So no repository or third-party code - a `.yarnrc.yml`'s `yarnPath`, a plugin, an install script -
  runs next to a Claude token, and nothing can write `$GITHUB_ENV` or `$GITHUB_PATH` for the Claude step. The weekly
  audit's `yarn npm audit` therefore runs in its own job (`deps`, no secret) and arrives as an artifact.
- `needs env YARN_ENABLE_SCRIPTS: "false"` (policy `manager_env_required`) - the manager's installs run with lifecycle
  scripts off whatever a PR's `.yarnrc.yml` says (the environment beats rc files): a dependency's install script would run
  with the agents' token in the environment.
- `checkout input(s) <x> not allowed in a claude job (only fetch-depth, persist-credentials, ref)` - no `repository`, `path`,
  `token` or other inputs on any checkout in the job.
- `the checkout needs an explicit ref of the default branch (...), never the PR's code` / `the checkout needs
  persist-credentials: false` - every checkout uses `main` (or `${{ github.event.repository.default_branch }}`;
  `${{ github.base_ref }}` only in a pull_request_target workflow) and keeps no credentials in `.git/config`.
- `step <n>: action must be pinned to a full commit SHA: <uses>` - every remote action, including the first checkout.
- `env '<x>' not allowed in a job with a claude step (allowed: ...)` - job env names are limited to `job_env` in the policy.
  `needs env CLAUDE_CODE_SUBPROCESS_ENV_SCRUB: "1"` - every claude job turns on Claude Code's subprocess isolation, so tools it
  runs never see the Claude token (the lock installs bubblewrap for it).
- `runs-on must be ['self-hosted', 'agents'] (jobs with a claude step run on the agents' runners)` - every job with a claude
  step runs on the agents' self-hosted runners (`.github/agent-runner`, `docs/runbooks/agent-runner.md`), never on GitHub's
  machines. `'defaults' not allowed in a job with a claude step`; `'working-directory' not allowed` / `'shell' not allowed in a
  job with a claude step`.
- `job <x>: no permissions (set them on the job or the workflow; the repository's default token is not allowed)` - a job with
  no `permissions` of its own in a workflow without a workflow-level `permissions` block would run with the repository's
  default job token, which can hold every write scope (`statuses: write` among them: enough to post a `guards/main-guard`
  status as github-actions[bot] from any job that runs code the agents can change).
- `permissions must be a mapping of scopes (no read-all/write-all)`; `permission <scope>: <value> not allowed (...)` - for
  every job and the workflow level: only the scopes in `permission_scopes` (`actions`, `contents`, `issues`,
  `pull-requests`), plus those in `per_file_permission_scopes` for the files listed there (`id-token` only in
  `egress-lock-claude.yml`, for its `oidc` job; `statuses` only in `main-guard.yml` and `pusher-ledger.yml`, whose
  pinned scripts post the `guards/main-guard` and ledger commit statuses as github-actions[bot] - no job the agents'
  code runs in can post a status in that identity), each read, write or none. `id-token: write, so its 'if' must contain
  github.run_attempt == '1'` / `... must run 'bash scripts/check-main-head.sh' before the lock` - a job that can mint an
  OIDC token runs only on a first attempt and only after the main-head check. `id-token: write is not allowed in a workflow that
  runs on pull_request/pull_request_target` - a PR could trade the OIDC token for cloud access. `permission <scope>: write
  is not allowed in <file> (its job token is read-only; the agents act with their own token)` - a workflow in
  `read_only_workflows` (`agent-manager.yml`) may hold no write scope at any level.
- `runs or checks out PR code in a job with a claude step (only the reviewed prepare step may touch /tmp/pr)` - no step may
  mention `/tmp/pr` (other than `/tmp/pr-meta`), the PR head, `head_ref`, `merge_commit_sha`, `refs/pull/`, `pull/<n>`,
  `gh pr checkout` or `event.issue.number`, except the exact prepare command in `pr_data_runs`.
- `'git <cmd>' not allowed in a job with a claude step (the checkout must stay on the default branch)` - no `git fetch`,
  `checkout`, `switch`, `worktree`, `pull`, `clone`, `reset`, `restore` or `submodule` in a run step (the prepare step does its
  own, reviewed).
- `no local action after the claude step (its files could have changed)`; `a step after the claude step must check its pinned
  files (sha256sum --check --strict) before running repo scripts` - steps after Claude may run `scripts/...` or
  `/tmp/gitleaks` only after checking the sha256 values a step before Claude wrote (the `pin` step).

Claude steps
- `claude action must be one of [...], got <x>` - use the pinned `anthropics/claude-code-action@<sha>`.
- `key '<x>' not allowed on a claude step` - only id, name, uses, with, if and timeout-minutes (no `continue-on-error`).
  `env not allowed on a claude step (job env names: ...)` - put allowed names in the job's env.
- `a claude step may not run after a failure (no always()/failure()/cancelled() in its if)`.
- `input '<x>' not allowed (allowed: ...)` - only `claude_code_oauth_token`, `github_token`, `prompt`, `claude_args`,
  `path_to_claude_code_executable`, `path_to_bun_executable`, `classify_inline_comments` and `allowed_bots`; `allowed_bots may only be ...` - only `github-actions`, only in
  `agent-manager.yml` (it lets `review.yml` start a fix round right after a failed review). `<problem> in input '<x>'` - a
  secrets problem inside an input. `input 'classify_inline_comments' must be 'false' (...)` - `claude_inputs_required`
  in the policy: the action's own post-session step "Post buffered inline comments" (read at the pinned commit) runs
  `if: always() && inputs.classify_inline_comments != 'false'` with `GITHUB_TOKEN` (the step's `github_token`, so the
  agents' token in the manager) and `bun` from `PATH` when the action's own copy is missing; after a session that ran with
  `bypassPermissions`, nothing on `PATH` is trusted, so the step is turned off (the quoted string `"false"`, exactly what
  the action compares). The other post-session steps of the action hold no token: "Re-prepend system bin dirs to PATH"
  (only with `allowed_non_write_users`), the SSH-signing cleanup (unused) and "Revoke app token" (only without a
  `github_token` input, which every step here sets).
- `path_to_claude_code_executable must be ${{ steps.<lock id>.outputs.claude-path }}` / `path_to_bun_executable must be ${{
  steps.<lock id>.outputs.bun-path }}` - the binaries the lock installed and checked (it writes those outputs only after its
  self-test passed; the action's own Bun download would need hosts the lock closes).
- `a claude step without a prompt (tag mode) may run only on issue_comment, issues (found ...)` / `... needs the job if to
  contain '!github.event.issue.pull_request'` - without a prompt the action checks out an open PR's code itself and restores
  only the top-level rule files, so nested `CLAUDE.md` files from the PR would load. No workflow uses tag mode any more
  (`claude.yml` passes a prompt and posts through its `post` job); the rule stays for any step that drops its prompt.
- `claude_args cannot be parsed (...)` - fix the quoting. `claude_args flag '<x>' not allowed (allowed: ...)` / `claude_args flag
  <x> needs a value` - only `--model`, `--max-turns`, `--permission-mode`, `--allowedTools`, `--disallowedTools`, `--add-dir`,
  each with a value.
- `needs exactly one --disallowedTools (found N)`; `--disallowedTools does not deny Skill(<name>)` - add `Skill(<name>)` for
  `payload` and every third-party skill in the base or PR manifest.
- `--permission-mode <x> not allowed (only bypassPermissions, only in agent-manager.yml)`.
- `--add-dir <x> not allowed (allowed: ...)` - only `/tmp/pr` and `/tmp/pr-meta` in `review.yml`, `/tmp/audit-meta` in
  `agent-weekly-audit.yml`.
- `--allowedTools item '<x>' not allowed outside agent-manager.yml (read-only tools only)` - answer-only jobs may allow only
  `read_only_tools` (`Read(./**)`, never a bare `Read`: Read is allowed under the checkout only, and Grep and Glob follow the
  Read rules, so the process that holds the Claude token cannot be made to read `/proc`, `/dev` or the runner's folders;
  measured, see `docs/runbooks/agent-network-lock.md`) and the fixed `read_only_bash` commands (`gh` views and lists, and
  exactly `date -u`: `date:*` would allow `date -f <file>`, which echoes a file's lines; yarn commands are gone from the
  Claude steps because yarn runs code from `.yarnrc.yml` and `.yarn/plugins`, so the weekly audit's `deps` job (no secret)
  runs `yarn npm audit` and the `audit` job downloads `npm-audit.json` as an artifact into `/tmp/audit-meta`), plus any `extra_tools` listed for that file (`Read(//tmp/pr/**)` and
  `Read(//tmp/pr-meta/**)` for the review, `Read(//tmp/audit-meta/**)` for the audit, the scrub probe's one command). No `git`, `find`, `sort`, `cat` or anything that can write a file: the PR's history
  is written as plain files before Claude starts (`/tmp/pr-meta`, `/tmp/audit-meta`).
