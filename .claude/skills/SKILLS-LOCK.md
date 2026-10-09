# Skills: sources, pinning and updates (founder-owned)

Every skill folder is listed in `manifest.txt` and every file in `checksums.sha256`. The `guards` workflow checks both on every PR
(`scripts/check-skills.sh`, run from `main`), plus: third-party skills have a NOTICE.md, a license file and a row here with the same
commit; every `skills:` entry in `.claude/agents/*.md` exists; skills marked `requires=` are always loaded with their override; each
skill's `name:` matches its folder. Agents never add or update skills; a founder does it in their own PR.

## Third-party skills (pinned)
| Skill | Source (github.com/...) | Upstream commit | License |
|---|---|---|---|
| payload | payloadcms/payload `tools/claude-plugin/skills/payload`, tag v3.90.2 | 6254c3bf561a205223849a6497d7dae824d4e81b | MIT (NOTICE.md, UPSTREAM-LICENSE.md) |

Each third-party folder keeps the upstream files unchanged, plus our `NOTICE.md` (source, commit, license, copyright) and the
upstream license file.

**The `payload` skill tag must equal the Payload version pinned in `apps/admin/package.json`.** A Payload upgrade PR also updates the
skill to the same tag (founder PR); until then the upgrade is blocked.

### Known lines in third-party skills that our rules neutralize (founder decision)
Per the review policy, these are risk types 1-2 found in the unchanged upstream text. We keep the files unchanged (so they stay
verifiable against upstream) and neutralize the lines with override rules; the founders accept this by merging the PR that lists them.
| Skill | Line(s) | Risk type | Neutralized by |
|---|---|---|---|
| payload | `SKILL.md` Quick Start (`npx create-payload-app@latest`, `pnpm dev`); `reference/PLUGIN-DEVELOPMENT.md` (`npm run ...`) | 1 (runs/installs) | payload-dealer-overrides "Stack differences" (never run them); manager job denies `npx`/`npm` |
| payload | `SKILL.md` Resources (`llms-full.txt`); end of `reference/ADVANCED.md` ("fetch these URLs") | 2 (fetched at run time) | payload-dealer-overrides "Never fetch"; review, report and audit jobs have no web access |

## Our own skills
| Skill | What it is |
|---|---|
| manager, review-pr, daily-report, weekly-audit | Company workflows |
| payload-dealer-overrides | Binding rules on top of `payload` (CLAUDE.md > overrides > payload) |

## How a founder adds or updates a skill
1. Work in your own PR (opened and pushed from a founder account).
2. Get the exact upstream files at a full commit SHA - never with `npx`:
   `git clone https://github.com/<owner>/<repo> /tmp/up && git -C /tmp/up checkout <full-sha>` (for a tag, check
   `git -C /tmp/up rev-parse <tag>^{commit}` equals the SHA), then `cp -r /tmp/up/<path> .claude/skills/<name>`.
3. Prove it is unchanged: `diff -r /tmp/up/<path> .claude/skills/<name>` must list only `NOTICE.md` and the license file. Post the
   output on the PR. Read every file, especially scripts and URLs.
4. Add `NOTICE.md` (source, commit, license, copyright), the upstream license file, a row above, and the manifest line
   (`<name> third-party`, plus `requires=<override>` if it needs one).
5. Run `bash scripts/check-skills.sh --write`, then `bash scripts/check-skills.sh`.
6. Add it to the right agents' `skills:` lines. If it conflicts with CLAUDE.md, add or extend an override skill.
7. Open the PR. The review team checks third-party skills for the five risk types in CLAUDE.md's review policy.
