# Skills: sources, pinning and updates (founder-owned)

What is checked automatically (`guards` workflow, scripts run from `main`, tests in `scripts/check-*.test.sh`):
`scripts/check-skills.sh` - every skill folder is in `manifest.txt` exactly once; every file matches `checksums.sha256`; third-party
skills have NOTICE.md, one license file, a row here with the same commit, and `requires=<our override skill>`; each skill's `name:`
matches its folder; agents preload only listed skills, each once and with its required override.
`scripts/check-skills-upstream-all.sh` - for every third-party skill, fetches the commit in its row below and runs
`scripts/check-skill-upstream.sh`: our copy is upstream with deletions only, and `.claude/skills-patches/<name>.diff` matches.
Agents never add or update skills.

## Third-party skills (pinned)
| Skill | Source (github.com/...) | Upstream commit | License | Patch |
|---|---|---|---|---|
| payload | payloadcms/payload `tools/claude-plugin/skills/payload`, tag v3.90.2 | 6254c3bf561a205223849a6497d7dae824d4e81b | MIT (NOTICE.md, UPSTREAM-LICENSE.md) | `.claude/skills-patches/payload.diff` (deletions only: install commands, link lists, "fetch these URLs", plugin guide) |

Upstream proof for `payload` (founder session, 2026-10-09, fresh clone of github.com/payloadcms/payload):
`git rev-parse v3.90.2^{commit}` = 6254c3bf561a205223849a6497d7dae824d4e81b, and `scripts/check-skill-upstream.sh` printed
`OK: .claude/skills/payload = upstream with deletions only (1 upstream file(s) removed) + top-level NOTICE.md/UPSTREAM-LICENSE; payload.diff matches`.
The `guards` job repeats this on every PR.

Security advisories checked (2026-10-09) at https://github.com/payloadcms/payload/security/advisories - every published advisory
is fixed at or before 3.87.0:
| Advisory | CVE | Package | Fixed in |
|---|---|---|---|
| [GHSA-4ww4-68q3-h7g5](https://github.com/payloadcms/payload/security/advisories/GHSA-4ww4-68q3-h7g5) field-level write access bypass | none | `@payloadcms/db-mongodb` (we use Postgres) | 3.87.0 |
| [GHSA-hp5w-3hxx-vmwf](https://github.com/payloadcms/payload/security/advisories/GHSA-hp5w-3hxx-vmwf) password recovery input validation (critical) | CVE-2026-34751 | `payload`, `@payloadcms/graphql` | 3.79.1 |
| [GHSA-7xxh-373w-35vg](https://github.com/payloadcms/payload/security/advisories/GHSA-7xxh-373w-35vg) SQL injection via query handling | CVE-2026-34747 | `payload` | 3.79.1 |
| [GHSA-p6mr-xf3r-ghq4](https://github.com/payloadcms/payload/security/advisories/GHSA-p6mr-xf3r-ghq4) CSRF protection bypass in auth | CVE-2026-34749 | `payload` | 3.79.1 |
| [GHSA-6r7f-q7f5-wpx8](https://github.com/payloadcms/payload/security/advisories/GHSA-6r7f-q7f5-wpx8) authenticated SSRF via uploads | CVE-2026-34746 | `payload` | 3.79.1 |
| [GHSA-mmxc-95ch-2j7c](https://github.com/payloadcms/payload/security/advisories/GHSA-mmxc-95ch-2j7c) stored XSS in admin panel | CVE-2026-34748 | `@payloadcms/next` | 3.78.0 |
| [GHSA-frq9-7j6g-v74x](https://github.com/payloadcms/payload/security/advisories/GHSA-frq9-7j6g-v74x) signed-URL filename validation | CVE-2026-34750 | `@payloadcms/storage-*` | 3.78.0 |
| [GHSA-hhfx-5x8j-f5f6](https://github.com/payloadcms/payload/security/advisories/GHSA-hhfx-5x8j-f5f6) SSRF in external file URL uploads | CVE-2026-27567 | `payload` | 3.75.0 |
| [GHSA-jq29-r496-r955](https://github.com/payloadcms/payload/security/advisories/GHSA-jq29-r496-r955) cross-collection IDOR in payload-preferences | CVE-2026-25574 | `payload` | 3.74.0 |
| [GHSA-xx6w-jxg9-2wh8](https://github.com/payloadcms/payload/security/advisories/GHSA-xx6w-jxg9-2wh8) SQL injection in JSON/richText queries on Postgres (critical) | CVE-2026-25544 | `@payloadcms/drizzle` | 3.73.0 |
| [GHSA-35jj-vqcf-f2jf](https://github.com/payloadcms/payload/security/advisories/GHSA-35jj-vqcf-f2jf) hidden fields leaked on readable collections | - | `payload` | published 2023, before Payload v3 |

Release notes (https://github.com/payloadcms/payload/releases) also list security fixes without advisories: 3.87.0 (multi-tenant
plugin applies the tenant on confirm; unauthenticated draft-mode access in the preview route; delete access on soft delete) and
3.87.1 (MCP plugin SDK; that plugin is banned for us). **Minimum: Payload 3.87.1. Pin: 3.90.2** (newest stable on 2026-10-09; the
skill matches it). Payload 4 is only canary builds so far; we move when 4.0.0 is stable and passes our leak tests on staging.

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
   **deleting only**, save `diff -ru -x NOTICE.md -x UPSTREAM-LICENSE -x UPSTREAM-LICENSE.md -x UPSTREAM-LICENSE.txt upstream ours` as
   `.claude/skills-patches/<name>.diff` (the script checks it matches), and post the output of `bash scripts/check-skill-upstream.sh /tmp/up/<path> <name>` and the `rev-parse`
   line on the PR. Also check the security advisories and release notes for that version and update the table above.
4. Add `NOTICE.md` (source, commit, license, copyright, what was removed), the upstream license file, a row above, and the manifest
   line (`<name> third-party requires=<our override skill>`; every third-party skill needs one).
5. Run `bash scripts/check-skills.sh --write`, then `bash scripts/check-skills.sh`.
6. Add it to the right agents' `skills:` lines (one-line comma list). If it conflicts with CLAUDE.md, extend an override skill.
7. Open the PR. The review team checks third-party skills for the five risk types in CLAUDE.md's review policy.
