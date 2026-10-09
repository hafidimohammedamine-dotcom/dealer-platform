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
`scripts/gitleaks-config*`, `.gitleaks.toml`, `.gitleaksignore`, `packages/data/override-allowlist.txt`. Renames count both ways.
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
- `third-party skill 'X' has no license file` - add the upstream license (LICENSE, LICENSE.md/.txt or UPSTREAM-LICENSE*) at the top
  of the folder, non-empty.
- `no full 40-character commit` (SKILLS-LOCK.md or NOTICE.md) / `commit ... differs` - write the same full commit SHA in both.

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

## Proving a third-party skill equals upstream (founder, manual)
`bash scripts/check-skill-upstream.sh <upstream-skill-dir> <name>` must print exactly
`OK: .claude/skills/<name> = upstream with deletions only (<n> upstream file(s) removed) + top-level NOTICE.md/UPSTREAM-LICENSE*`.
Errors: `lines added or changed in <file>`, `file not in upstream: <file>`, `not a regular file or folder` (symlinks),
`upstream dir not found`, `no skill folder`. Fix by re-copying from upstream and deleting lines only.

## "Workflow denies OK" (in `checks`)
`scripts/check-workflows.sh` fails if an agent workflow that can use skills doesn't deny `Skill(payload)`, or if the manager job
lost one of its command denies. Put the deny back.

## After changing agent permissions (founder, manual)
Run one `workflow_dispatch` of the manager and check the "Show blocked tool calls" step: a `Skill(payload)` deny must not stop
builders from preloading `payload` with `payload-dealer-overrides` (preloads don't use the Skill tool). If a builder reports it
can't see the Payload skill, remove the deny and tell the founders.

## Workflow "CI" (job `checks`), step "Guard script tests"
Run locally to see which case broke:
- `bash scripts/check-founder-files.test.sh`, `bash scripts/check-skills.test.sh`, `bash scripts/check-skill-upstream.test.sh`, `bash scripts/check-review-prepare.test.sh`,
  `bash scripts/check-pr-ci-status.test.sh`, `bash scripts/check-review-post.test.sh`
- `GITLEAKS=/path/to/gitleaks bash scripts/gitleaks-config.test.sh` (exits 2 if gitleaks can't run)
"Secret scan of all history (pushes to main)" failing means a secret reached `main`: follow "Real key" above.

## Known limits
- The founder check trusts GitHub accounts. It protects us only once the agents use their own account (`AGENT_GH_TOKEN` from
  the agents' account, not a founder's). Until that switch, founders read every PR that touches founder-only files.
- `CODEOWNERS` and required checks enforce nothing until branch protection is on (paid GitHub plan for a private repo).
- `ci.yml` runs from the PR (tests, no secrets). Anything a PR must not be able to change lives in `guards.yml` / `review.yml`.
