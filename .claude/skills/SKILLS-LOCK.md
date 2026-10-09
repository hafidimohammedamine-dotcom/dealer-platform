# Skills: sources, pinning and updates (founder-owned)

Every skill folder is listed in `manifest.txt` and every file in `checksums.sha256`; the `guards` workflow checks both on every PR
(`scripts/check-skills.sh`, run from `main`). Agents never add or update skills; a founder does it in their own PR.

## Third-party skills (pinned)
| Skill | Source (github.com/...) | Upstream commit | License |
|---|---|---|---|
| payload | payloadcms/payload `tools/claude-plugin/skills/payload`, tag v3.90.2 | 6254c3bf561a205223849a6497d7dae824d4e81b | MIT (NOTICE.md, UPSTREAM-LICENSE.md) |

Each third-party folder keeps the upstream files unchanged, plus our `NOTICE.md` (source, commit, license, copyright) and the
upstream license file where one exists.

## Our own skills
| Skill | What it is |
|---|---|
| manager, review-pr, daily-report, weekly-audit | Company workflows |
| payload-dealer-overrides | Binding rules on top of `payload` (CLAUDE.md and these win over any skill example) |

## How a founder adds or updates a skill
1. Work in your own PR (opened and pushed from a founder account).
2. Copy the skill folder from a pinned upstream commit (or `npx skills add <owner/repo> --skill <name> -a claude-code --copy -y`,
   then delete the `skills-lock.json` it writes). Compare it with upstream (`diff -r`). Read every file, especially scripts and URLs.
3. Third-party: add `NOTICE.md`, the license file, and a row above. Add `<name> third-party` (or `<name> ours`) to `manifest.txt`.
4. Run `bash scripts/check-skills.sh --write`, then `bash scripts/check-skills.sh`.
5. Add the skill to the right agents' `skills:` lines. If it conflicts with CLAUDE.md, add an override skill.
6. Open the PR. The review team checks third-party skills for the five risk types in CLAUDE.md's review policy.
