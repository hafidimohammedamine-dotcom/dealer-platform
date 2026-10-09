# Skills: sources, pinning and updates (founder-owned)

What is checked automatically (`guards` workflow, `scripts/check-skills.sh` run from `main`, 49 tests in
`scripts/check-skills.test.sh`): every skill folder is in `manifest.txt`; every file matches `checksums.sha256`; third-party skills
have NOTICE.md, a license file and a row here with the same commit; each skill's `name:` matches its folder; agents preload only
listed skills, each with its required override. What is **not** automatic: proving a third-party copy equals upstream - a founder
runs `scripts/check-skill-upstream.sh` and posts the output on the PR (step 3 below). Agents never add or update skills.

## Third-party skills (pinned)
| Skill | Source (github.com/...) | Upstream commit | License | Patch |
|---|---|---|---|---|
| payload | payloadcms/payload `tools/claude-plugin/skills/payload`, tag v3.90.2 | 6254c3bf561a205223849a6497d7dae824d4e81b | MIT (NOTICE.md, UPSTREAM-LICENSE.md) | `.claude/skills-patches/payload.diff` (deletions only: install commands, link lists, "fetch these URLs", plugin guide) |

Payload version: no version is pinned in `apps/admin/package.json` yet. When it is, a founder keeps the skill on the same tag
(manual step).

## Our own skills
| Skill | What it is |
|---|---|
| manager, review-pr, daily-report, weekly-audit | Company workflows |
| payload-dealer-overrides | Binding rules on top of `payload` (CLAUDE.md > overrides > payload) |

## How a founder adds or updates a skill
1. Work in your own PR (opened and pushed from a founder account).
2. Get the exact upstream files at a full commit SHA - never with `npx`:
   `git clone https://github.com/<owner>/<repo> /tmp/up && git -C /tmp/up checkout <full-sha>` (for a tag, check that
   `git -C /tmp/up rev-parse <tag>^{commit}` equals the SHA), then `cp -r /tmp/up/<path> .claude/skills/<name>`.
3. Read every file. Remove risky lines (install/run commands, links to fetch, plugin or tooling guides we don't use) by
   **deleting only**, save `diff -ru upstream ours` as `.claude/skills-patches/<name>.diff`, and post the output of
   `bash scripts/check-skill-upstream.sh /tmp/up/<path> <name>` and the `rev-parse` line on the PR.
4. Add `NOTICE.md` (source, commit, license, copyright, what was removed), the upstream license file, a row above, and the manifest
   line (`<name> third-party`, plus `requires=<override>` if it needs one).
5. Run `bash scripts/check-skills.sh --write`, then `bash scripts/check-skills.sh`.
6. Add it to the right agents' `skills:` lines (one-line comma list). If it conflicts with CLAUDE.md, extend an override skill.
7. Open the PR. The review team checks third-party skills for the five risk types in CLAUDE.md's review policy.
