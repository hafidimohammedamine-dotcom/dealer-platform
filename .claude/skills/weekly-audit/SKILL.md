---
name: weekly-audit
description: Weekly whole-codebase audit by security, architect, compliance and devops. Writes one audit report; the manager opens an issue per new finding. Runs every Sunday from GitHub Actions.
---

**This job runs with a short command allow-list:** one command per Bash call (no pipes, `&&`, `;` or redirection), no web access, no file edits, and you can't post or create anything: your **final message** is the report, which a
fixed workflow step scans for secrets and posts on the "Daily reports" issue.

Run the weekly audit of the whole repository. Read `CLAUDE.md` first.

## Step 1 - Audit in parallel
**Run every agent in the foreground** (never `run_in_background`). Start them together in one message so they run in parallel, but wait for every result before the next step. This job ends when you stop, so background agents would be lost.
Launch at the same time, each told "Audit the whole repository, not a diff. Report only, don't edit":
- `security` - full security audit (its weekly checklist)
- `architect` - codebase health check
- `compliance` - full compliance pass over messaging, AI, pricing, credit, documents, reviews
- `devops` - CI health, backups, monitoring, dependency updates, Payload version (newer release? open security advisories?)

## Step 2 - Check for duplicates
For each finding, search open issues for the same problem (`gh issue list --search "<file> <keyword>"`) and mark duplicates.

## Step 3 - Final message (the report)
```
WEEKLY AUDIT - <date>
NEW FINDINGS: security <n> (critical <n>) | architecture <n> | compliance <n> | devops <n>
TOP 3 RISKS: ...
PAYLOAD: running <version>, latest <version>, open advisories <n>, upgrade suggested yes/no

FINDINGS (new only; duplicates listed at the end):
1. [<area>] <short problem> | <file>:<line> | fix: ... | found by: <reviewer> | priority: 1|2|3 | owner: agent:<name>
...
DUPLICATES OF OPEN ISSUES: #<n> ...
```
Priority: CRITICAL/HIGH or MUST FIX -> 1; MEDIUM -> 2; LOW -> 3. Owner from the CLAUDE.md owner table.
Never include secrets, tokens or environment variables.
