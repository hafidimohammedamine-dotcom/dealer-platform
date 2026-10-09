# Skills: sources, pinning and updates (founder-owned)

## What protects the skills
- **The real control is people:** a founder opens every skills PR and the security reviewer reads it. Reviewers always judge a
  PR with the base branch's CLAUDE.md and `.claude/` (agent-review.yml), so a PR cannot weaken the rules it is judged by.
- **CI catches drift, not intent:** `scripts/check-skills.sh` compares every file under `.claude/skills/` (third-party and our own,
  including NOTICE.md files) with `checksums.sha256`. It fails on unknown folders, symlinks, added, removed, renamed or changed files.
  In a PR, CI runs the **base branch's** copy of the script. Its own tests: `scripts/check-skills.test.sh`.
- **Agents can't touch it:** CI fails any `agent/*` branch that changes CLAUDE.md, `.claude/`, the check scripts, `.gitleaks.toml`,
  CODEOWNERS, agent workflows or `packages/contracts`.
- **Known gap:** a PR can still edit `ci.yml` itself, and our agents push with a founder's GitHub token, so GitHub cannot tell
  agent PRs from founder PRs. Founders read every `.github/` change. `CODEOWNERS` takes full effect once branch protection
  ("Require review from Code Owners") is on, which needs a paid GitHub plan for a private repo.

## Third-party skills (pinned)
| Skill(s) | Source (github.com/...) | Upstream commit | License |
|---|---|---|---|
| payload | payloadcms/payload `tools/claude-plugin/skills/payload`, tag v3.90.2 | 6254c3bf561a | MIT |
| payload-accessibility | payloadcms/payload `.agents/skills/payload-accessibility` | 518a946cff0a | MIT |
| frontend-design | anthropics/skills | 9d630808e4ad | Apache-2.0 |
| vercel-react-best-practices | vercel-labs/agent-skills | 063bee94c3f4 | MIT (README/SKILL.md only, no LICENSE file upstream) |
| vercel-composition-patterns | vercel-labs/agent-skills | 063bee94c3f4 | MIT (README/SKILL.md only, no LICENSE file upstream) |
| ui-ux-pro-max | nextlevelbuilder/ui-ux-pro-max-skill | 50d8a7de0900 | MIT |
| supabase-postgres-best-practices | supabase/agent-skills | c9be0e931b79 | MIT |
| nx-workspace, nx-run-tasks, link-workspace-packages | nrwl/nx-ai-agents-config | 49aa84ca1b4e | MIT |
| security-review | getsentry/skills | d18b7aa8ba87 | Apache-2.0 |
| agentic-actions-auditor, property-based-testing | trailofbits/skills | 82fe82262526 | CC BY-SA 4.0 (internal use; see NOTICE.md) |
| tdd, codebase-design | mattpocock/skills | 49dd158d1076 | MIT |
| playwright-cli | microsoft/playwright-cli | b85c7a736bb4 | Apache-2.0 |
| typescript-best-practices, principle-type-system-discipline, principle-boundary-discipline | cursor/plugins `pstack/skills` (copied by hand; the CLI can't find them) | ccb5507cec15 | MIT |
| nestjs-best-practices | kadajett/agent-nestjs-skills (community) | 3986e0cede33 | MIT (SKILL.md only, no LICENSE file upstream) |
| telnyx-messaging-javascript, telnyx-10dlc-javascript | team-telnyx/ai | 4d2ace03d087 | MIT. skills.sh shows a Snyk "Warn" with no reason given; files are API docs, no scripts |
| resend, email-best-practices | resend/resend-skills | 47e70983bd3f | MIT |

Every third-party folder has a `NOTICE.md` (source, commit, license, copyright) and, where upstream has one, the license text
(`LICENSE*` or `UPSTREAM-LICENSE*`). Files are otherwise unmodified.

## Our own skills
manager, review-pr, daily-report, weekly-audit (company workflows); payload-dealer-overrides and skill-overrides (binding rules on
top of third-party skills); web-interface-rules (vercel-labs/web-interface-guidelines `command.md` @ 434b7f91364, MIT) and
writing-rules (vercel-labs/writing-guidelines `command.md` @ 83e2316b034, MIT) as local copies so nothing is fetched at run time;
secure-coding, scalability, cost-reducer (the founder's own skills from his Claude account).

## Not installed on purpose
- `web-design-guidelines`, `writing-guidelines` (Vercel): download their rules from GitHub `main` on every run. Replaced by the local copies above.
- ElevenLabs skills: voice provider being reconsidered.
- Railway `use-railway`: installs its CLI with `curl | sh`; agents never touch production.
- Next.js skills (vercel/next.js): target Next.js 16 cache components; Payload owns our Next.js setup.
- The full Trail of Bits repo: it has its own `review-pr` skill that would clash with ours.

## How a founder adds or updates a skill
1. On a `founder/...` branch (never `agent/...`), get the files: `npx skills add <owner/repo> --skill <name> -a claude-code --copy -y`
   (or copy the folder from a pinned upstream commit). Delete the `skills-lock.json` the tool writes; we don't use it.
2. Compare the folder with the upstream commit you pinned (`diff -r`). Read every file, especially scripts and any URLs.
3. Add or update `NOTICE.md` and the license file. Update the table above.
4. New skill folder: add its name to `PINNED` (third-party) or `FIRST_PARTY` (ours) in `scripts/check-skills.sh`.
   Because CI runs the **base branch's** script, land the script change first in its own PR, then the skill.
5. Run `bash scripts/check-skills.sh --write`, `bash scripts/check-skills.sh` and `bash scripts/check-skills.test.sh`.
6. Add the skill to the right agents' `skills:` lines and, if it conflicts with our rules, to `skill-overrides`.
7. Open the PR; the review team (security first) must pass it. A founder merges.

Runbook when the check fails: `docs/runbooks/pinned-skills-check.md`.
