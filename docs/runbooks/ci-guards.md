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
- `no full 40-character commit` (SKILLS-LOCK.md or NOTICE.md) / `commit ... differs` / `write the commit in lower case` - write the
  same full commit SHA, in lower case, in both.
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
- `deletions in <file> are not whole units` - deletions must be whole units (`scripts/check-skill-deletions.py`): a whole file;
  a heading's whole own body (the heading line up to the next heading of any level); a whole fenced code block (``` or ~~~, any
  length, an unclosed one runs to the end of the file); or a single table row or list item with no warning or rule word (❌, ✅,
  WRONG, never, must, not, always, only, important, critical, required, access, overrideAccess, secret, token, ...). Partial prose,
  part of a code block (including indented code) or a heading without its body fails. Blank lines can go anywhere. To drop a whole
  file's text, delete the file rather than emptying it.
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
- `claude_args flag '<x>' not allowed` - only `--model`, `--max-turns`, `--permission-mode`, `--allowedTools`, `--disallowedTools`,
  `--add-dir`, each with a value. `input '<x>' not allowed` - a claude step takes only `claude_code_oauth_token`, `github_token`,
  `prompt`, `claude_args`, `path_to_claude_code_executable`, and - only in `agent-manager.yml` - `allowed_bots: github-actions`
  (`allowed_bots may only be ...`). That lets `review.yml` start a fix round right after a failed review; without it the action
  refuses runs started by `github-actions[bot]`.
- `claude action must be one of [...]` - use the pinned `anthropics/claude-code-action@<sha>`.
- `a job with a claude step must start with actions/checkout, then ./.github/actions/agent-egress-lock` (with an `id`, no `if` or
  `continue-on-error`), and `path_to_claude_code_executable must be ${{ steps.<lock id>.outputs.claude-path }}`.
- `agent-manager.yml: missing deny <item>` / `expected exactly one claude step in agent-manager.yml (found N)`.
- `runs Claude outside the pinned claude-code-action` - no `claude` CLI (any path), `@anthropic-ai/...` or other claude-code action
  in `run:` or `uses:`.
- `Claude/Anthropic credential outside a claude step's claude_code_oauth_token` - `secrets.*CLAUDE*`, `secrets['...']`,
  `toJSON(secrets)`, `ANTHROPIC_API_KEY`, `CLAUDE_CODE_OAUTH_TOKEN` appear nowhere else (not in env at any level, not in `prompt`).
- `local action not on the allow-list` (only `install-gitleaks` and `agent-egress-lock`), `not allowed: docker://...`,
  `reusable workflow not allowed`, `'container'/'services' not allowed`, `not valid YAML or has duplicate keys`.
- `python3 PyYAML is required` - GitHub's Ubuntu runners include it; locally `python3 -m pip install pyyaml==6.0.2`.

## Agent network lock (`.github/actions/agent-egress-lock`)
Every agent job runs it right after checkout. It installs the pinned Claude Code release (the claude-code-action then uses that
binary), then: a local DNS server (dnsmasq) answers only the domains in `allow-domains.txt` (GitHub, Anthropic API, npm/Yarn
registries, the runner's log storage) and adds their addresses to a firewall set; the firewall (iptables) rejects every other
outbound connection, other DNS servers and all IPv6; Docker is stopped and the runner user's sudo is removed, so no later step can
undo it. A self-test then fails the job if an allowed host is unreachable or if a blocked host, a raw IP, outside DNS, IPv6, sudo or
Docker still works. `.github/workflows/egress-lock-test.yml` runs it, plus the real claude-code-action and a `Skill(payload)` deny
probe, whenever the lock changes.
- A job fails with `allowed host ... not reachable` or a tool cannot download something: add the domain to `allow-domains.txt` in a
  founder PR (plain domain names; subdomains are included), or pass `extra-domains:` for one job.
- What it does not stop: a prompt injection that also carries an attacker's own GitHub or npm credentials could still push data to
  GitHub or npm, which are allowed. The agents' token reaches this repo only. The command deny lists stay as a second layer
  (hygiene, not a boundary).
- Verified on the pinned Claude Code (2.1.295, the version this claude-code-action installs): `Skill(<name>)` in
  `--disallowedTools` denies the Skill tool for that skill, also under `bypassPermissions` and inside subagents, while a subagent's
  `skills:` preload is injected at start and still works.

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
  `bash scripts/check-skills-upstream-all.test.sh`, `bash scripts/check-skills-vs-base.test.sh`, `bash scripts/check-workflows.sh`,
  `bash scripts/check-workflows.test.sh`,
  `bash scripts/check-review-prepare.test.sh`, `bash scripts/check-pr-ci-status.test.sh`, `bash scripts/check-review-post.test.sh`
- `GITLEAKS=/path/to/gitleaks bash scripts/gitleaks-config.test.sh` (exits 2 if gitleaks can't run)
"Secret scan of all history (pushes to main)" failing means a secret reached `main`: follow "Real key" above.

## Known limits
- The founder check trusts GitHub accounts. It protects us only once the agents use their own account (`AGENT_GH_TOKEN` from
  the agents' account, not a founder's). Until that switch, founders read every PR that touches founder-only files.
- `CODEOWNERS` and required checks enforce nothing until branch protection is on (paid GitHub plan for a private repo).
- `ci.yml` runs from the PR (tests, no secrets). Anything a PR must not be able to change lives in `guards.yml` / `review.yml`.
