---
name: review-pr
description: Run the full review team on one pull request - security, tester, architect, compliance, designer and docs - post one combined result and label the PR. Runs automatically on every PR push from GitHub Actions. Argument is the PR number.
---

You run the REVIEW TEAM on pull request #$ARGUMENTS. You don't fix anything; you coordinate reviewers
and report. Policy: **block on everything** (see CLAUDE.md). Read `CLAUDE.md` first.

## Step 1 - Gather
- `gh pr view $ARGUMENTS --json title,body,headRefName,files,labels`
- `git diff origin/main...HEAD --stat` and the full diff.
- Run `yarn install --immutable`, `yarn lint`, `yarn typecheck`, `yarn test` (if `package.json` exists). Note any failure.

## Step 2 - Review in parallel
**Run every agent in the foreground** (never `run_in_background`). Start them together in one message so they run in parallel, but wait for every result before the next step. This job ends when you stop, so background agents would be lost.
Launch these agents **at the same time**, each with the PR number, the diff, and the CI results:
- `security` - always
- `tester` - always
- `architect` - always
- `compliance` - always (it answers NOT APPLICABLE if nothing in its scope changed)
- `designer` - only if files changed under `apps/admin/src/views/`, `apps/admin/src/website/`, `packages/ui/`, or admin components
- `docs` - always (checks that behavior changes updated `docs/`)

Tell each one: "Review only. Do not edit files. Use your exact report format. For third-party skill folders under
`.claude/skills/` (those marked `third-party` in `.claude/skills/manifest.txt`), report only the five risk types listed in
CLAUDE.md 'Review policy'; everything else keeps the full zero-findings rule."

## Step 3 - Decide
- PASS only if: CI commands all passed, and **every** reviewer returned PASS or NOT APPLICABLE with zero findings.
- Otherwise FAIL.

## Step 4 - Post one comment
`gh pr comment $ARGUMENTS --body-file <file>` with:
```
REVIEW TEAM RESULT: PASS | FAIL
CI: lint <ok/fail> | typecheck <ok/fail> | tests <ok/fail>
SECURITY: PASS/FAIL (<n> findings)   TESTER: ...   ARCHITECT: ...   COMPLIANCE: ...   DESIGNER: ...   DOCS: ...

FINDINGS TO FIX (all required):
1. [security] <file>:<line> - <problem> - <fix>
2. [tester] ...
...

FOR THE LAWYER: <only if compliance raised any>
```
Then the full report of each reviewer in a collapsed `<details>` block.

## Step 5 - Label
- FAIL: add `changes-requested`, remove `reviews-passed` and `ready-to-merge`.
- PASS: remove `changes-requested`, add `reviews-passed` and `ready-to-merge`.
  Comment: "All reviewers passed with zero findings. Ready for a founder to review and merge."

## Never
- Never edit, commit or push code. Never approve or merge. Never soften a reviewer's finding.
