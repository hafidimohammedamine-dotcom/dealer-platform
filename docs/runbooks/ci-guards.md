# Runbook: guard checks (`guards`) and CI guard tests (`checks`)

**Who fixes these:** a founder makes any change to founder-only files. An agent may only **undo** an accidental change it
made to one of them, then ask with `REQUEST:` on its issue.

The `guards` workflow (`.github/workflows/guards.yml`) runs on `pull_request_target`: GitHub always runs the copy on `main`,
with `main`'s scripts and config. The PR's files are fetched as data and never run. Changes to the guards take effect after merge.

## "Founder-only files (by PR author, not branch name)" fails
The PR was opened by an account not listed in `.github/founders.txt` and it changes a founder-only file: `CLAUDE.md`,
`CLAUDE.local.md`, `.mcp.json`, `.claude/` (in any folder), anything in `.github/`, `scripts/check-*`, `scripts/gitleaks-config*`,
`.gitleaks.toml`, `.gitleaksignore`, `packages/contracts/`. Renames count both ways.
Fix: the PR's author undoes those changes and comments `REQUEST: <path> - <change> - <why>` on the issue; the manager routes it
to the founders, who make the change in their own PR.
Other messages: `founders file not found` or `could not diff` - the base checkout is broken; re-run the job once, then tell a founder.

## "Skills match manifest and checksums" fails
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

## "Secret scan of the PR's commits" fails
gitleaks found something that looks like a secret in a commit of this PR. It uses `main`'s `.gitleaks.toml`, ignores any
`.gitleaksignore` and inline `gitleaks:allow` comments. The output shows the file, line and rule (secret redacted).
- **If it is a real key: treat it as leaked even if the PR is closed.** Revoke it at the provider now (GitHub token, Claude
  token, Telnyx, Resend, AWS...), create a new one, store it only in GitHub secrets / Railway, and tell both founders.
  Removing the commit is not enough; the old value stays in history and in forks/caches.
- If it is a documented fake value from vendor docs: a founder may add that exact value to `.gitleaks.toml` (anchored,
  `regexTarget = "secret"`) in a founder PR, with a case in `scripts/gitleaks-config.test.sh`.

## Review job: "Check out the base branch" / "Fetch the PR as data" fails
`refs/pull/<n>/head` could not be fetched or the worktree could not be created. Re-run the job once; if it fails again, tell a founder.
"Wait for CI and guards" prints the check states every 30 seconds; after 30 minutes reviewers report them as pending (result FAIL).

## "Guard script tests" fails (in `checks`)
Run locally to see which case broke:
- `bash scripts/check-founder-files.test.sh`
- `bash scripts/check-skills.test.sh`
- `GITLEAKS=/path/to/gitleaks bash scripts/gitleaks-config.test.sh` (exits 2 if gitleaks can't run)

## Known limits
- Until the agents have their own GitHub account, every PR is opened by a founder's account, so the founder-files check
  passes for agent PRs too. Founders read every PR that touches founder-only files.
- `CODEOWNERS` enforces nothing until branch protection requires code-owner review (paid plan for a private repo).
- `ci.yml` runs from the PR (it runs the PR's tests without secrets). Anything a PR must not be able to change lives in `guards.yml`.
