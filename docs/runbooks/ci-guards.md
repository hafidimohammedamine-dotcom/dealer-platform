# Runbook: guards, review job and CI guard tests

**Who fixes these:** a founder makes any change to founder-only files. An agent may only **undo** an accidental change it
made to one of them, then ask with `REQUEST:` on its issue. A new founder is added by an existing founder's PR that adds their
login to `.github/founders.txt` (and to `.github/CODEOWNERS`).

How it fits together: `docs/architecture.md` ("CI and review").

## Workflow "Guards" (job `guards`)
Runs on `pull_request_target`: GitHub always runs the copy on `main`, with `main`'s scripts and config. The PR is fetched as data.

### Step "Fetch the PR as data into /tmp/pr" fails
`ERROR: bad PR number`, `already exists`, a git fetch error, or `rule files left in /tmp/pr`. Re-run the job once; if it fails
again, tell a founder.

### Step "Founder-only files (PR author and pusher must be founders)" fails
Message: `Not all of '<author>,<pusher>' are founders, and the PR changes founder-only files:` plus the paths.
Founder-only: `CLAUDE.md`, `CLAUDE.local.md`, `.mcp.json`, `.claude/` (in any folder), anything in `.github/`, `scripts/check-*`,
`scripts/gitleaks-config*`, `.gitleaks.toml`, `.gitleaksignore`, and `packages/data/override-allowlist.txt` once it exists (the
guard already protects that path). Renames count both ways.
Fix: undo those changes and comment `REQUEST: <path> - <change> - <why>` on the issue. If an agent pushed to a founder's PR,
the founder pushes once more after checking the agent's commits.
`founders file not found` / `could not diff` - the base checkout is broken; re-run once, then tell a founder.

### Step "Skills match manifest and checksums" fails
- `skill folder not in manifest: X` - add `X ours` or `X third-party` to `.claude/skills/manifest.txt`, or remove the folder.
- `manifest lists 'X' but the folder is missing` - remove the line or restore the folder.
- `manifest line for 'X' needs kind 'ours' or 'third-party'` - fix the second word on that line.
- `bad skill name in manifest: 'X'` - names are lowercase letters, digits and dashes.
- `third-party skill 'X' has no NOTICE.md` / `has no row in SKILLS-LOCK.md` - add the notice (source, commit, license) and the row.
- `symlink not allowed`, `special file not allowed`, `empty folder not allowed`, `file name with newline, backslash or control character`
  - replace with plain files with plain names, or delete.
- `unexpected file: .claude/skills/<name>` - only `manifest.txt`, `checksums.sha256` and `SKILLS-LOCK.md` may sit at the top.
- `files added`, `files removed or renamed`, `changed files` - files differ from `checksums.sha256`. Unintended: revert.
  Intended (founder): review the change, then `bash scripts/check-skills.sh --write`.
- `missing .claude/skills/manifest.txt` / `missing .claude/skills/checksums.sha256` - restore the file from `main`.
- `missing .claude/agents` - restore the folder from `main`.
- `<agent>.md: more than one 'skills:' line` - keep exactly one.
- `<agent>.md: 'skills:' must be a one-line comma list` - write it as `skills: a, b` (no YAML list, no brackets, not empty).
- `<agent>.md: skill 'X' is not in the manifest` - fix the spelling or add the skill.
- `<agent>.md: 'X' must be loaded together with 'Y'` - add `Y` to that agent's `skills:` line.
- `skill 'X' requires 'Y', which is not in the manifest` / `unknown option` - fix the manifest line (`<name> <kind> [requires=<skill>]`).
- `skill 'X' has no SKILL.md` / `front matter name is '...'` - each skill folder needs `SKILL.md` starting with `---`, `name: <folder>`.
- `third-party skill 'X' has no license file` - add the upstream license as `UPSTREAM-LICENSE` (plain, .md or .txt; exact
  upper-case name) at the top of the folder, non-empty. Upstream's own `LICENSE`/`LICENSE.md`/`LICENSE.txt` also counts.
- `NOTICE.md for 'X' has no full 40-character commit` / `commit for 'X' differs between SKILLS-LOCK.md and NOTICE.md` - write
  the same full lower-case commit SHA in NOTICE.md and the lock row.
- `SKILLS-LOCK.md row for 'X' must read '| X | owner/repo `path`, ... | <40-hex commit, lower case> | ...'` - fix the row's
  shape (the commit is the third cell). `has no row in SKILLS-LOCK.md` / `has more than one row` - one row per skill, first
  cell exactly the skill name.
- `listed more than once in the manifest` / `empty requires=` / `more than one requires=` / `needs requires=<our override skill>` /
  `must require one of our own (override) skills` / `CRLF` - fix `manifest.txt` (one LF line per skill; every third-party skill has
  exactly one `requires=` naming an `ours` skill).
- `skill 'X' is listed more than once in 'skills:'` - list each skill once on the agent's `skills:` line.

### Step "Secret scan of the PR's commits (base config, no ignore files, no inline allow)" fails
gitleaks found something that looks like a secret in this PR's commits (`main`'s `.gitleaks.toml`; `.gitleaksignore` and inline
`gitleaks:allow` are ignored). The log shows file, line and rule, with the secret redacted.
- **Real key: treat it as leaked even if the PR is closed.** Revoke it at the provider now (GitHub, Claude, Telnyx, Resend, AWS...),
  create a new one, store it only in GitHub secrets / Railway, and tell both founders. Deleting the commit is not enough.
- Documented fake value from vendor docs: a founder may add that exact value to `.gitleaks.toml` (anchored, `regexTarget = "secret"`)
  in a founder PR, with a case in `scripts/gitleaks-config.test.sh`.

## Workflow "Agent - Review team" (job `review`)
Also `pull_request_target`, also from `main`.
- **"Fetch the PR as data into /tmp/pr"** fails - as above.
- **"Wait for CI and guards on the PR head (max 30 min)"** prints `ci=<status> guards=<status>` every 30 seconds. After 30 minutes it
  passes `pending` to the reviewers, which makes the result FAIL; the review runs again on the next push.
- **"Review (read-only)"** fails or times out - the next step posts `REVIEW TEAM RESULT: FAIL` saying there was no valid result.
  Re-run the job once.
- **"Post the result (secret-scanned) and set labels"**: if the answer looked like it contained a secret, it posts FAIL without
  the text - a founder checks the job log and, if a real secret appeared, follows "Real key" above.

## Third-party skills compared with the base branch (guards, automatic)
`scripts/check-skills-vs-base.sh` (from `main`) compares the PR's manifest and SKILLS-LOCK.md rows with `main`'s. The log lists
every `CHANGED`, `NEW` and `REMOVED` third-party skill with its repo, path and commit, for the founders to read. Errors:
- `third-party skill 'X' is now listed as 'ours'` - a vendored skill stays third-party. To replace it, remove it and add a new one.
- `changed its source repo (a -> b)` - a different upstream (for example a fork) needs a new skill name.
- `removed from the manifest but its folder is still there` - delete the folder too, or keep the manifest line.

## Proving a third-party skill equals upstream (guards, automatic)
The `guards` job step "Third-party skills equal their pinned upstream with deletions only" runs
`scripts/check-skills-upstream-all.sh`: for each third-party skill it fetches the exact commit from its SKILLS-LOCK.md row and runs
`scripts/check-skill-upstream.sh`. Both read lock rows with `scripts/check-skills-lib.sh`, like `check-skills.sh`: the row whose
first cell is exactly the skill name, shaped `| <name> | <owner>/<repo> `<path>`, ... | <40-hex commit, lower case> |`.
It must print
`OK: .claude/skills/<name> = upstream with deletions only (<n> upstream file(s) removed) + top-level NOTICE.md/UPSTREAM-LICENSE; <name>.diff matches`.
Messages and fixes:
- `lines added or changed in <file>`, `file not in upstream: <file>`, `more than one UPSTREAM-LICENSE file`, `not a regular file or
  folder` - re-copy from upstream and only delete. The only files we may add are top-level `NOTICE.md` and one `UPSTREAM-LICENSE`
  (plain, .md or .txt).
- `lines removed from <file>: only whole-file deletions are allowed outside Markdown files` - delete the whole file or nothing.
- `deletions in <file> are not whole units` - deletions must be whole units (`scripts/check-skill-deletions.py`): a whole file;
  a heading's whole own body (the heading line up to the next heading of any level); a whole fenced code block (``` or ~~~, any
  length, an unclosed one runs to the end of the file); or a single table row, or a whole list item (marker line plus its deeper-indented continuation lines), with no warning or rule word (❌, ✅,
  WRONG, never, must, not, always, only, important, critical, required, access, overrideAccess, secret, token, ...). Partial prose,
  part of a code block (including indented code) or a heading without its body fails. Blank lines can go anywhere. To drop a whole
  file's text, delete the file rather than emptying it.
- `a section or code block with a warning or rule word (...) that is not in the reviewed list (add '<file>:<line>' ...)` - a
  whole section or code block removed from upstream contains a warning word. A founder reads it and, if removing it is safe
  (for example a list of links), adds `<file>:<upstream line of the heading or opening fence>` with a reason after `#` to
  `.claude/skills-patches/<name>.reviewed`. The guards log prints every such deletion as `REVIEWED <file>:<line> ...`.
  `stale entry in <name>.reviewed` - an entry no longer matches a deletion; remove it.
- `missing or empty record`, `<name>.diff does not match diff -ru of upstream and our copy`, `<name>.diff has added lines`,
  `records changes but our copy equals upstream` - regenerate the record from a folder holding the upstream copy as `upstream` and
  ours as `ours`:
  `diff -ru -a -x NOTICE.md -x UPSTREAM-LICENSE -x UPSTREAM-LICENSE.md -x UPSTREAM-LICENSE.txt upstream ours > .claude/skills-patches/<name>.diff`
- `diff failed on <file>` / `diff of upstream and ours failed (exit N)` - a file could not be read; fix permissions and re-run.
- `could not fetch <repo> at <commit>` - the repo or commit in the lock row is wrong, or GitHub was down (re-run once).
- `needs exactly one SKILLS-LOCK.md row` / `must read '| name | owner/repo `path`, ... | <40-hex commit> |'` - fix the lock row.
A founder can run it locally: `bash scripts/check-skills-upstream-all.sh .`

## "Workflow denies OK" (`guards` from `main`, and `checks`)
`scripts/check-workflows.sh` runs `scripts/check-workflows.py`, which parses every workflow as YAML (duplicate keys rejected) and
fails closed. `guards` runs the `main` copy on the PR's workflows as data, with both manifests, so a PR cannot switch it off.
Messages and fixes:
- `--disallowedTools does not deny Skill(<name>)` - add `Skill(<name>)` for `payload` and every third-party skill in the base or PR
  manifest to that step's `--disallowedTools "..."` in `claude_args`.
- `needs exactly one --disallowedTools (found N)` - one `--disallowedTools "a,b,..."` in `claude_args` (nothing in `prompt` counts).
- `claude_args cannot be parsed (...)` - fix the quoting in `claude_args`.
- `key '<x>' not allowed on a claude step` - a claude step has only id, name, uses, with, if, timeout-minutes,
  continue-on-error. `env not allowed on a claude step` - put allowed names in the job's env.
- `env '<x>' not allowed in a job with a claude step` - job env names are limited to the list in
  `scripts/check-workflows-policy.json` (`job_env`); `needs env CLAUDE_CODE_SUBPROCESS_ENV_SCRUB: "1"` - every claude job turns
  on Claude Code's subprocess isolation, so tools it runs never see the Claude token (the lock installs bubblewrap for it).
- `--permission-mode <x> not allowed` (only `bypassPermissions`, only in `agent-manager.yml`), `--add-dir <x> not allowed`
  (only `/tmp/pr` in `review.yml`), `--allowedTools item '<x>' not allowed outside agent-manager.yml` (answer-only jobs may
  allow only the read-only tools and Bash commands listed in `check-workflows-policy.json`: no `find`, no `git grep`, no
  writes).
- `a later checkout in a claude job must also use the default branch` / `runs or checks out PR code in a job with a claude
  step` - no PR head refs and no running anything inside `/tmp/pr` in a job that holds a Claude token.
- `'with' must be a mapping`, `steps must be a list`, `not a mapping`, `no jobs mapping` - malformed workflow; fix the YAML.
- `cannot read check-workflows-policy.json` - restore the founder-owned policy file next to the script.
- `claude_args flag '<x>' not allowed` - only `--model`, `--max-turns`, `--permission-mode`, `--allowedTools`, `--disallowedTools`,
  `--add-dir`, each with a value. `input '<x>' not allowed` - a claude step takes only `claude_code_oauth_token`, `github_token`,
  `prompt`, `claude_args`, `path_to_claude_code_executable`, and - only in `agent-manager.yml` - `allowed_bots: github-actions`
  (`allowed_bots may only be ...`). That lets `review.yml` start a fix round right after a failed review; without it the action
  refuses runs started by `github-actions[bot]`.
- `claude action must be one of [...]` - use the pinned `anthropics/claude-code-action@<sha>`.
- `a job with a claude step must start with actions/checkout, then ./.github/actions/agent-egress-lock` (with an `id`, no `if` or
  `continue-on-error`), and `path_to_claude_code_executable must be ${{ steps.<lock id>.outputs.claude-path }}`.
- `the checkout needs an explicit ref of the default branch (...)` / `needs persist-credentials: false` - a claude job checks
  out `main` (or `${{ github.event.repository.default_branch }}`; `${{ github.base_ref }}` only in a pull_request_target
  workflow), never the PR's code, and keeps no credentials in `.git/config`.
- `the ./.github/actions/agent-egress-lock step may only have id/uses/name` - no `with`, `env`, `if` or `continue-on-error`.
- `a workflow with a claude step must not run on pull_request` - PR code may never run in a job that holds a Claude token.
- `AGENT_LOCK_* variables (lock test hooks) are not allowed` - those exist only for the lock's own tests.
- `secrets used other than as secrets.<NAME> outside a claude step's claude_code_oauth_token` - no `secrets['x']`,
  `secrets[format(...)]`, `toJSON(secrets)`, `join(secrets)` or the whole object anywhere.
- `Claude/Anthropic credential secrets.<NAME> outside a claude step's claude_code_oauth_token` / `Claude/Anthropic credential
  variable ...` - a secret named *CLAUDE*/*ANTHROPIC*, `ANTHROPIC_API_KEY` or `CLAUDE_CODE_OAUTH_TOKEN` appears elsewhere.
- `manifest not found` / `--manifest needs a file` - guards passes both manifests; an explicit one must exist.
- `agent-manager.yml: missing deny <item>` / `expected exactly one claude step in agent-manager.yml (found N)`.
- `runs Claude outside the pinned claude-code-action` - no `claude` CLI (any path), `@anthropic-ai/...` or other claude-code action
  in `run:` or `uses:`.
- `local action not on the allow-list` (only `install-gitleaks` and `agent-egress-lock`), `not allowed: docker://...`,
  `reusable workflow not allowed`, `'container'/'services' not allowed`, `not valid YAML or has duplicate keys`.
- `python3 PyYAML is required` - GitHub's Ubuntu runners include it; locally `python3 -m pip install pyyaml==6.0.2`.

## Agent network lock (`.github/actions/agent-egress-lock`)
Every agent job runs it right after checking out `main`. It:
1. installs the pinned Claude Code binary from `downloads.claude.ai` and checks it against the sha256 pinned in `action.yml`
   (the claude-code-action then uses that binary instead of downloading one);
2. starts a local DNS server (dnsmasq) that answers only the names in `allow-domains.txt`;
3. starts a local proxy (nginx `stream` with `ssl_preread`) that reads the TLS server name (SNI) of each connection and connects
   only to allow-listed names. The firewall (iptables) sends every outbound port-443 connection, except the proxy's own, to
   that proxy and rejects everything else: plain HTTP, raw IPs without a name, other DNS servers, all IPv6. An allowed IP
   cannot be reused under another name;
4. stops Docker and removes the runner user's sudo, so no later step can undo it;
5. self-tests and fails the job on any problem.

Allowed names are exact hosts (GitHub API/git/downloads, `api.anthropic.com`, the npm/Yarn registries, the runner's own
services and log storage). Only `.actions.githubusercontent.com` is a wildcard (approved in `lock.sh`), because the runner uses
many generated names there.

Tests: `scripts/check-egress-lock.test.sh` (every failure branch, stubbed); `.github/workflows/egress-lock-test.yml` (the PR's
lock on a real runner, no secrets, plus a break-on-purpose run); `.github/workflows/egress-lock-claude.yml` (from `main` only:
the real claude-code-action under the lock and a `Skill(payload)` deny probe; on pushes to main, weekly and on demand).

Messages and fixes:
- `Linux x64 runners only` / `must run inside GitHub Actions` - only for GitHub-hosted Ubuntu x64 runners.
- `bad CLAUDE_CODE_VERSION` / `bad CLAUDE_CODE_SHA256` / `Claude Code download does not match its pinned sha256` /
  `Claude Code <v> not installed` - fix the pin in `action.yml` (see "Bumping the Claude Code pin").
- `empty allow-list` / `not a plain host name` / `suffix entry not approved` - fix `allow-domains.txt`.
- `no www-data user for nginx` / `nginx stream module missing` / `nginx config invalid` - the runner image changed; re-run once,
  then a founder checks the packages (`dnsmasq-base`, `nginx`, `libnginx-mod-stream`).
- `self-test: allowed host api.github.com not reachable` - the proxy or DNS is not working; the log shows the proxy log and a
  verbose curl. `self-test: sudo still works`, `Docker still reachable`, `blocked host example.com reachable`,
  `gist.github.com reachable`, `uploads.github.com reachable`, `allowed IP reachable under another name (SNI)`, `raw IP without
  a name reachable`, `plain HTTP (port 80) reachable`, `DNS for an allowed name does not resolve`, `DNS for a blocked name
  resolves`, `outside DNS server reachable`, `IPv6 reachable`, `group-writable admin socket still there` - the lock is not doing its job on this runner; do not bypass it,
  open an `area:security` issue for the founders.
- A tool in an agent job cannot download something it needs: add its exact host to `allow-domains.txt` in a founder PR.
- `Claude answered under the lock, and Skill(payload) was denied` fails (egress-lock-claude.yml) - either Claude could not reach
  `api.anthropic.com` through the lock, or the Skill deny did not hold; read the printed result and denials.

Bumping the Claude Code pin (founder PR, together with the claude-code-action SHA): the action's `src/entrypoints/run.ts` names
the Claude Code version it expects; take that version's `linux-x64` `checksum` from
`https://downloads.claude.ai/claude-code-releases/<version>/manifest.json` into `action.yml`. The reviewers check both pins, and
`egress-lock-test.yml` / `egress-lock-claude.yml` prove the result.

The job's processes keep the groups they started with (sudo, docker, adm): Linux cannot take them away mid-job. The lock makes
them powerless instead (no sudoers entry, Docker stopped and its socket gone) and the self-test fails if any socket writable by
docker/lxd/containerd remains. Each run also prints a `Known open routes` notice so the gaps below stay visible.

What the lock does not stop (it narrows the routes out, it is not a complete data boundary):
- an injected instruction that also carries an attacker's own credentials could still send data to an allowed service: GitHub
  (a push or issue in the attacker's repo), npm (a publish) or the Anthropic API (the attacker's key);
- domain fronting on the CDNs behind allowed names (an allowed server name with another site's `Host` header inside TLS), where
  the CDN allows it.
Claude Code's subprocess isolation keeps the Claude token out of every tool the agents run, but `GH_TOKEN` stays visible to them
(they need it to push and comment). So the GitHub token's scope is the real limit, and it must come from the agents' own account:
a fine-grained token for this repository only, with Contents, Pull requests and Issues (read/write), Actions (read), and **no
Workflows permission and no admin**. Without the Workflows permission it cannot push changes to `.github/workflows/`, so an
agent cannot add a workflow that would receive the Claude tokens. Until that account exists the agents use a founder's token
and none of this holds; the founders read every agent PR (Known limits). The command deny lists stay as a second layer, and
reviews plus founder merges stay the control for what lands in the repo.

Evidence for the Skill deny (Claude Code 2.1.295; tag v1.0.247 of claude-code-action is commit 2dca132f, whose
`src/entrypoints/run.ts` pins 2.1.295; the lock's sha256 is the `linux-x64` checksum in
`https://downloads.claude.ai/claude-code-releases/2.1.295/manifest.json`, all checked by a founder on 2026-10-09):
- CI: run https://github.com/hafidimohammedamine-dotcom/dealer-platform/actions/runs/37986311153 (an earlier version of the
  egress test that still ran the probe on the PR branch; the probe now runs only from `main` in `egress-lock-claude.yml`) printed
  `permission_denials: [{"tool_name": "Skill", ... "skill": "payload"}]` with the real claude-code-action under the lock.
- Local re-check a founder can repeat in an empty folder with `.claude/skills/probe/SKILL.md` (a skill telling Claude to reply
  `PROBE-LOADED-7731`) and two agents in `.claude/agents/`: `subprobe` (`skills: probe`) and `subskill` (`tools: Skill`, told to load
  `probe`):
  `claude -p "Use the Skill tool to load the skill named probe ..." --permission-mode bypassPermissions --disallowedTools "Skill(probe)" --output-format json`
  gives `permission_denials: [{'tool_name': 'Skill', ... 'skill': 'probe'}]`; asking it to run both subagents with the same flags
  gives `SUBPROBE: PROBE-LOADED-7731` (the preload still works) and `SUBSKILL: SUB-SKILL-DENIED` (the deny holds in a subagent).
Re-check when the pin changes.

## How the guards wiring is proven
The scripts have unit tests (below). The workflow wiring (`git archive` of the PR head, base scripts on PR data, the upstream fetch)
is proven by the live `guards` run: a guards change takes effect only after it merges, so the **next** PR's guards log must show
the new steps passing. For the guards PR itself, a founder runs the same commands locally on the PR head and posts the output.

## After changing agent permissions (founder, manual)
Run one `workflow_dispatch` of the manager and check the "Show blocked tool calls" step. Once vendored skills exist (the Payload
skill, #22), a `Skill(payload)` deny must not stop builders from preloading `payload` with `payload-dealer-overrides`. If a builder
reports it can't see the skill, **do not remove the deny**: open an `area:security` issue for the founders.

## Workflow "CI" (job `checks`), step "Guard script tests"
Run locally to see which case broke:
- `bash scripts/check-founder-files.test.sh`, `bash scripts/check-skills.test.sh`, `bash scripts/check-skill-upstream.test.sh`,
  `bash scripts/check-skill-deletions.test.sh`, `bash scripts/check-skills-upstream-all.test.sh`,
  `bash scripts/check-skills-vs-base.test.sh`, `bash scripts/check-workflows.sh`, `bash scripts/check-workflows.test.sh`,
  `bash scripts/check-egress-lock.test.sh`,
  `bash scripts/check-review-prepare.test.sh`, `bash scripts/check-pr-ci-status.test.sh`, `bash scripts/check-review-post.test.sh`
- `GITLEAKS=/path/to/gitleaks bash scripts/gitleaks-config.test.sh` (exits 2 if gitleaks can't run)
"Secret scan of all history (pushes to main)" failing means a secret reached `main`: follow "Real key" above.

## Known limits
- Agent pushes to `.github/**` cannot be blocked by a ruleset on the current plan (push rulesets need a paid plan for a
  private repo). The protection is the token: the agents' own fine-grained token without the Workflows permission (see
  "Agent network lock"). Until it exists, agents run on a founder's token and the founders read every agent PR.
- The founder check trusts GitHub accounts. It protects us only once the agents use their own account (`AGENT_GH_TOKEN` from
  the agents' account, not a founder's). Until that switch, founders read every PR that touches founder-only files.
- `CODEOWNERS` and required checks enforce nothing until branch protection is on (paid GitHub plan for a private repo).
- `ci.yml` runs from the PR (tests, no secrets). Anything a PR must not be able to change lives in `guards.yml` / `review.yml`.
