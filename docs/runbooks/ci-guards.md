# Runbook: CI guard checks

**Who fixes these:** a founder. Agents never change the files these checks protect.

## "Use the base branch's guard scripts" fails
`ERROR: scripts/<name> is missing on main and this is not a founder/ branch` - a new guard script can only arrive from a
`founder/` branch. Agents: don't touch it; ask with `REQUEST:` on the issue.

## "Founder-only files unchanged" fails
The branch is not a `founder/` branch and changes a founder-only file: any `CLAUDE.md`, `CLAUDE.local.md`, `.mcp.json`,
`.claude/`, `.github/`, `scripts/check-*`, `scripts/gitleaks-config*`, `.gitleaks.toml`, `packages/contracts/`.
Renames count both ways (moving a file out of `.claude/` also fails).
Fix: undo those changes on the branch and comment on the issue `REQUEST: <path> - <change> - <why>`. The manager routes it to
the founders, who apply it on a `founder/` branch.

## "Skills match manifest and checksums" fails
Messages and what they mean:
- `skill folder not in manifest: X` - add `X ours` or `X third-party` to `.claude/skills/manifest.txt`, or remove the folder.
- `manifest lists 'X' but the folder is missing` - remove the line or restore the folder.
- `symlink not allowed`, `special file not allowed`, `empty folder not allowed`, `file name with newline, backslash or control character`
  - replace it with a plain file with a plain name, or delete it.
- `unexpected file: .claude/skills/<name>` - only `manifest.txt`, `checksums.sha256` and `SKILLS-LOCK.md` may sit at the top.
- `files added`, `files removed or renamed`, `changed files` - files differ from `.claude/skills/checksums.sha256`.
  If nobody meant to change skills, revert. If a founder did, review the change, then `bash scripts/check-skills.sh --write`.
- `missing .claude/skills/manifest.txt` / `missing .claude/skills/checksums.sha256` - restore the file from main.

In a PR, CI runs the **base branch's** copy of each guard script, so a change to a guard script itself only takes effect after it
is merged.

## "Guard script tests" fails
Run locally to see which case broke:
- `bash scripts/check-founder-files.test.sh`
- `bash scripts/check-skills.test.sh`
- `GITLEAKS=gitleaks bash scripts/gitleaks-config.test.sh` (proves `.gitleaks.toml` allows only AWS's documented example key)

## Known limits
- These checks run inside the PR's own `ci.yml`. A founder-only-file change to `ci.yml` itself is caught by the founder-files
  check, but only if the PR doesn't also remove that step. Founders read every `.github/` change.
- Agents push with a founder's GitHub token, so GitHub can't tell agent PRs from founder PRs by author; the `founder/` branch
  name and founders reviewing every PR are the controls. `CODEOWNERS` enforces nothing until branch protection requires it.
