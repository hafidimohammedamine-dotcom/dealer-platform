# Third-party skills (founder-owned)

Every third-party skill here is pinned to the upstream commit below and checked by CI (`scripts/check-skills.sh`,
`checksums.sha256`). Agents never update skills. A founder opens a PR to update one; the security reviewer must pass it.

| Skill | Source (github.com/...) | Upstream commit | License |
|---|---|---|---|
| payload | payloadcms/skills | 832d5bc4258a | MIT (payload/NOTICE.md) |
| payload-accessibility | payloadcms/payload | 518a946cff0a | MIT |
| frontend-design | anthropics/skills | 9d630808e4ad | Apache-2.0 (LICENSE.txt in folder) |
| web-design-guidelines | vercel-labs/agent-skills | 063bee94c3f4 | MIT (README; no LICENSE file upstream) |
| vercel-react-best-practices | vercel-labs/agent-skills | 063bee94c3f4 | MIT (README; no LICENSE file upstream) |
| vercel-composition-patterns | vercel-labs/agent-skills | 063bee94c3f4 | MIT (README; no LICENSE file upstream) |
| writing-guidelines | vercel-labs/agent-skills | 063bee94c3f4 | MIT (README; no LICENSE file upstream) |
| ui-ux-pro-max | nextlevelbuilder/ui-ux-pro-max-skill | 50d8a7de0900 | MIT |
| supabase-postgres-best-practices | supabase/agent-skills | c9be0e931b79 | MIT |
| nx-workspace | nrwl/nx-ai-agents-config | 49aa84ca1b4e | MIT |
| nx-run-tasks | nrwl/nx-ai-agents-config | 49aa84ca1b4e | MIT |
| link-workspace-packages | nrwl/nx-ai-agents-config | 49aa84ca1b4e | MIT |
| security-review | getsentry/skills | d18b7aa8ba87 | Apache-2.0 |
| agentic-actions-auditor | trailofbits/skills | 82fe82262526 | CC BY-SA 4.0 (docs; internal use, keep attribution, share changes alike) |
| property-based-testing | trailofbits/skills | 82fe82262526 | CC BY-SA 4.0 (same) |
| tdd | mattpocock/skills | 49dd158d1076 | MIT |
| codebase-design | mattpocock/skills | 49dd158d1076 | MIT |
| playwright-cli | microsoft/playwright-cli | b85c7a736bb4 | Apache-2.0 |
| typescript-best-practices | cursor/plugins (pstack) | ccb5507cec15 | MIT (LICENSE in folder) |
| principle-type-system-discipline | cursor/plugins (pstack) | ccb5507cec15 | MIT |
| principle-boundary-discipline | cursor/plugins (pstack) | ccb5507cec15 | MIT |
| nestjs-best-practices | kadajett/agent-nestjs-skills | 3986e0cede33 | MIT (SKILL.md; no LICENSE file upstream) - community |
| telnyx-messaging-javascript | team-telnyx/ai | 4d2ace03d087 | MIT - Snyk 'Warn' on skills.sh |
| telnyx-10dlc-javascript | team-telnyx/ai | 4d2ace03d087 | MIT - Snyk 'Warn' on skills.sh |
| resend | resend/resend-skills | 47e70983bd3f | MIT |
| email-best-practices | resend/resend-skills | 47e70983bd3f | MIT |

## Our own skills (not pinned; changed through normal founder PRs)
manager, review-pr, daily-report, weekly-audit (company workflows); payload-dealer-overrides (binding Payload rules);
web-interface-rules (local pinned copy of vercel-labs/web-interface-guidelines `command.md` @ 434b7f91364, MIT);
secure-coding, scalability, cost-reducer (founder's own skills from his Claude account).

## Not installed on purpose
- ElevenLabs skills: voice provider being reconsidered by founders.
- Railway `use-railway`: installs its CLI with `curl | sh`; agents never touch production.
- Next.js skills (vercel/next.js): target Next.js 16 cache components; Payload owns our Next.js setup.
- Trail of Bits full repo: has its own `review-pr` skill that would clash with ours.

To update a pinned skill: reinstall it, update the commit above, run `bash scripts/check-skills.sh --write`, open a PR.
