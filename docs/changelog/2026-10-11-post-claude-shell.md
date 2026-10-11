# 2026-10-11 - the workflow checker allows one hardened shell after a Claude step

Founder change (`scripts/check-workflows-claude.py`, `scripts/check-workflows.py`, `scripts/check-workflows-policy.json`,
tests, runbook, pins; the eight workflow files change only by their `PINS_SHA256` value - no workflow behaviour changes
here). Split out of #44 because the guards run the base branch's checker over a PR's tree: #44's hand-off steps set a
`shell:`, and main's checker refused every `shell:` in a Claude job. This PR adds only the checker rules; no workflow in
this PR uses the shell (#44 puts it on the five hand-off steps).

What the checker now allows and requires (runbook `docs/runbooks/workflow-checker.md`, "After the claude step"):
- Exactly one shell, only on steps after the Claude step: `/usr/bin/bash --noprofile --norc -p -eo pipefail {0}` (policy
  `post_claude_shell`). An absolute bash is not found through a `PATH` the Claude step may have extended with
  `$GITHUB_PATH`. `--noprofile --norc` only skip the profile and rc files; it is `-p` (privileged mode) that makes bash
  ignore `BASH_ENV`, `ENV`, `SHELLOPTS`, `BASHOPTS`, `GLOBIGNORE` and functions from the environment, whatever the Claude
  step wrote to `$GITHUB_ENV`. Near-miss strings (a trailing space, a missing `{0}`, no `-p`, `/bin/bash`, `sh`, `pwsh`,
  `python`) are refused; so is the shell before the Claude step, with `working-directory`, or as a job default.
- A step with that shell must start its `run:` with `export PATH=/usr/bin:/bin` (policy `post_claude_run_first`; a
  comment or blank line may come before it): the commands inside the step are found through `PATH` too.
- No workflow-level `defaults:` in a workflow with a Claude step (a default shell or working directory would apply to
  every step; job-level `defaults` were already refused). Only one Claude step per job ("after the Claude step" must mean
  one thing). The shell does not excuse the other post-Claude rules (the pin check before repo scripts, no PR data, no
  `git` moves): tested.
- The hand-off rule (a step that runs `scripts/check-claude-answer.sh` must use that shell, empty the injectable
  variables and fix `HOME` in its own `env:`) is in the checker but switched on by the policy keys `post_claude_handoff`,
  `post_claude_empty_env` and `post_claude_fixed_env`, which #44 sets together with the hardened steps (its tests live
  there). Stated plainly: a Claude step can write `$GITHUB_ENV` and `$GITHUB_PATH` (the egress lock does not block those
  files, and the manager runs with bypassPermissions; nothing here claims otherwise). The rules above are what makes both
  harmless to the steps that follow.
- Checker tests for all of this, including the real `review.yml` with the hardened shell swapped onto its hand-off
  step (passes with the `PATH` line, fails without it).
