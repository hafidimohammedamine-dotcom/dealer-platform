---
name: daily-report
description: Write the founders' daily report - what merged, what's ready to merge, what's blocked, what the agents are working on, failures and risks - and post it to the Daily reports issue. Runs every morning from GitHub Actions.
---

Write the daily report for the two founders. Plain English, short, no jargon. Read `CLAUDE.md` first.

## Gather (last 24 hours)
- Merged PRs: `gh pr list --state merged --search "merged:>=<yesterday>" --json number,title`
- Ready to merge: `gh pr list --label ready-to-merge --json number,title,url`
- Blocked: `gh issue list --label blocked` and `gh pr list --label blocked`
- In progress: `gh issue list --label status:in-progress`
- Review rounds: PRs with `round-2`, `round-3` or `escalated` (Chief Engineer)
- Failed workflow runs: `gh run list --status failure --limit 20`
- Manager log comments from the last 24 hours
- Open security issues: `gh issue list --label area:security`

## Post
Comment on the open issue titled **"Daily reports"** (create it if missing). Format:
```
DAILY REPORT - <date>

YOUR ACTIONS TODAY (founders)
1. Merge: #<pr> <title> (all reviews passed)
2. Decide: #<issue> <blocked question>
3. Approve request: #<issue> <contract or rule change>

DONE YESTERDAY: <n> PRs merged - <titles>
IN PROGRESS: <issue> (<agent>, round <n>) ...
STUCK OR SLOW: <PRs on round 2-3, failed runs, and why>
CHIEF ENGINEER: <escalations in the last 24h: root cause and decision>
SECURITY: <open security issues count, any critical>
PROGRESS: <issues done / total> toward the current milestone
NEXT 24 HOURS: <what the manager will pick next>
```
Put the founders' actions first. If nothing needs them, say "Nothing needs you today."
