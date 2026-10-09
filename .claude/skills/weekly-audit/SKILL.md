---
name: weekly-audit
description: Weekly whole-codebase audit by security, architect, compliance and devops. Opens one GitHub issue per new finding so the manager schedules the fixes. Runs every Sunday from GitHub Actions.
---

Run the weekly audit of the whole repository. Read `CLAUDE.md` first.

## Step 1 - Audit in parallel
Launch at the same time, each told "Audit the whole repository, not a diff. Report only, don't edit":
- `security` - full security audit (its weekly checklist)
- `architect` - codebase health check
- `compliance` - full compliance pass over messaging, AI, pricing, credit, documents, reviews
- `devops` - CI health, backups, monitoring, dependency updates, Payload version (newer release? open security advisories?)

## Step 2 - File issues
For each finding:
1. Search open issues for the same problem (`gh issue list --search "<file> <keyword>"`). Skip duplicates.
2. Otherwise create an issue:
   - Title: `[<area>] <short problem>`
   - Body: file:line, problem, fix, which reviewer found it
   - Labels: `status:todo`, `area:<security|architecture|compliance|devops>`, the owning `agent:*` from CLAUDE.md,
     priority: CRITICAL/HIGH or MUST FIX -> `priority:1`; MEDIUM -> `priority:2`; LOW -> `priority:3`

## Step 3 - Summary
Comment on the **"Daily reports"** issue:
```
WEEKLY AUDIT - <date>
NEW ISSUES: security <n> (critical <n>) | architecture <n> | compliance <n> | devops <n>
TOP 3 RISKS: ...
PAYLOAD: running <version>, latest <version>, open advisories <n>, upgrade suggested yes/no
```
