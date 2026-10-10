# Agent company - setup (about 1 hour, once)

## The company
| Team | Agents | What they do |
|---|---|---|
| Leadership | **chief-engineer** (Claude Fable 5.1; Opus while Fable usage is unavailable) | Called only when the team is stuck: 3 failed review rounds, a builder can't do it, or main is broken. Finds the root cause and fixes it itself |
| Management | **manager** (every hour) | Picks issues, assigns builders, sends every review finding back until fixed, escalates to the Chief Engineer, logs each shift |
| Builders (5) | builder-intake, builder-ai, builder-crm, builder-inventory, builder-finance | Write the product, one folder each |
| Review team (6) | security, tester, architect, compliance, designer, docs | Check every pull request. **Any finding blocks the merge** |
| Support | devops | Infra, CI, Payload config and hosting, tenant-safe data helper, backups |
| Founders (2) | you | Write the contracts, decide blocked items, review and merge |

Flow: Issue -> manager -> builder -> pull request -> review team -> fixes (up to 3 rounds) -> Chief Engineer if still failing -> `ready-to-merge` -> founder merges. Only if the Chief Engineer's fix also fails does it come to you as `blocked`.

## Models
| Model | Agents |
|---|---|
| Claude Fable 5.1 | chief-engineer by default (only when stuck, max one job per shift). Not in use right now: a founder sets it back to claude-fable-5-1 when Fable usage is available again |
| Opus | manager, security, compliance, architect, builder-finance, builder-ai, weekly audit, chief-engineer (temporarily, while Fable usage is unavailable) |
| Sonnet | builder-intake, builder-crm, builder-inventory, tester, designer, devops, review coordinator |
| Haiku | docs, daily report |

Pace (max): manager every hour, up to 4 builder jobs per shift, review on every pull request.
On Max, Fable can use up to half of the weekly limit and uses it faster than Opus.
With one plan, put the **same** token in both `CLAUDE_TOKEN_BUILD` and `CLAUDE_TOKEN_REVIEW`.

## 1. Repo
1. Create a **private** GitHub repo (e.g. `itri/dealer-platform`).
2. Copy everything in this pack into it (keep the `.claude/` and `.github/` folders) and push to `main`.

## 2. Accounts and secrets (Settings -> Secrets and variables -> Actions)
| Secret | How to get it |
|---|---|
| `CLAUDE_TOKEN_BUILD` | **Founder 1** (Max plan) runs `claude setup-token` on their computer, pastes the token. Runs the manager, weekly audit, @claude |
| `CLAUDE_TOKEN_REVIEW` | **Founder 2** (Max plan) runs `claude setup-token`, pastes the token. Runs reviews and the daily report |
| `GUARDS_LEDGER_KEY` | Any random string of 32+ characters (`openssl rand -hex 32`). Signs the guards' record of who pushed each commit; the agents can never read it |
| `AGENT_GH_TOKEN` | Create a free GitHub account for the agents (e.g. `itri-agents`), add it to the repo with **Write** access, and from that account make a **classic token** with only the `repo` scope (fine-grained tokens can't reach a repo owned by another personal account). That account must own no repository of its own. Never use a founder's token here: the `guards` check trusts who opened and pushed each PR |

On one plan, use the same token for both. With two plans, splitting the tokens spreads the work over both.

3. Install the Claude GitHub App on the repo: https://github.com/apps/claude

## 3. Protect `main` (Settings -> Branches -> Add rule for `main`)
- Require a pull request before merging, **1 approval**
- Require status checks: `checks` (workflow **CI**) and `guards` (workflow **Guards**), both from the **GitHub Actions** app.
  The review team posts its result as a comment and the `ready-to-merge` label; a founder reads it before merging.
- Block force pushes and deletions
Agents can never merge. Only a founder can.

## 4. Labels, report issues, first tasks
```bash
gh auth login
bash scripts/setup-github.sh
bash scripts/starter-issues.sh
```
Then create a GitHub **Project** (board view), add all issues, group by `status`.
Open the **Daily reports** issue, pin it, and click **Subscribe**. You get every report by email and in the GitHub phone app.

## 5. Do your founder task, then switch it on
1. Write `packages/contracts` (the first issue, labeled `agent:founder`). Most agents wait for it. Ask Claude to help you draft it.
2. Go to **Actions -> Agent - Manager shift -> Run workflow**. From then on it runs every hour by itself.

When you (a founder) change a pinned file - anything under `.github/actions/`, a `scripts/check-*` script (tests excepted),
`.gitleaks.toml`, `.github/accounts.txt`, `CLAUDE.md`, a `CLAUDE.local.md`, a `.mcp.json` or anything under a `.claude/`
folder (the full rule is `pins_required` in `scripts/check-workflows-policy.json`) - run `bash scripts/check-pins.sh update`
in the same PR: every workflow checks those files against `.github/pins.txt` before it runs them, fails if the tree holds
one that is not listed, and the agents cannot change that check.

## 6. Your daily routine (about 30 minutes)
1. Read the morning **Daily report**. Founders' actions are listed first.
2. Merge PRs labeled `ready-to-merge`: open it, read the summary, click through the app on staging, approve, merge.
   Each founder reviews PRs from the other's area.
3. Answer anything `blocked` or `agent:founder`.
4. Add new issues with the **Agent task** template. Small and specific = faster and cheaper.

## Costs and limits (max pace)
- **Claude:** two Max plans ($400/month). If agents hit the limit they stop and the next shift continues.
  Seeing many stopped shifts? Turn on extra usage with a monthly cap, or slow the manager to every 4-6 hours (`cron` in `agent-manager.yml`).
- **GitHub Actions minutes:** private repos get a free monthly allowance; non-stop agents will go past it.
  Expect roughly $50-120/month of extra minutes at this pace, or run a **self-hosted runner** on a spare computer for free
  (change `runs-on: ubuntu-latest` to `runs-on: self-hosted`). Set a spending limit in GitHub billing.

## First-week checks
- After the first manager shift, read its log. If a tool was refused, add it to `--allowedTools` in the workflow.
- If the review didn't start on an agent's PR, check `AGENT_GH_TOKEN` is set (pushes with the default token don't start workflows).
- Check one PR end to end: issue -> PR -> review comment -> fix round -> `ready-to-merge`.

## Payload rules (keep dealers apart)
The CRM, admin and dealer websites run on **Payload** (MIT, free) with its multi-tenant plugin. Four locks keep dealers apart:
one tenant-safe data helper for all access, Postgres row-level security as a second lock, cross-dealer leak tests in CI,
and a pinned Payload version upgraded monthly. Credit and SSN data never go into Payload collections.
Have your lawyer review the setup before your first paying dealer.
