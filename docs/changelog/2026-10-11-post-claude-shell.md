# 2026-10-11 - the workflow checker: one hardened shell after a Claude step, and what a step with it must look like

Founder change (`scripts/check-workflows-claude.py`, `scripts/check-workflows.py`, `scripts/check-workflows-policy.json`,
tests, runbook, pins; the eight workflow files change only by their `PINS_SHA256` value - no workflow behaviour changes
here). Split out of #44 because the guards run the base branch's checker over a PR's tree: #44's hand-off steps set a
`shell:`, and main's checker refused every `shell:` in a Claude job. This PR adds only the checker rules; no workflow in
this PR uses the shell (#44 puts it on the post-Claude steps and turns the `post_claude_require_shell` flag on).

Plainly, the problem: a Claude step can write `$GITHUB_ENV` and `$GITHUB_PATH` (the egress lock does not block those
files; the manager runs with bypassPermissions), and a later step's default `bash` honours both - `PATH`, `BASH_ENV`,
`LD_PRELOAD`, planted `BASH_FUNC_<name>%%` functions. On main today every post-Claude step runs that way, with only its
pin check between the Claude session and the repository scripts it runs (and `sha256sum` itself is found through
`PATH`). This PR does not change that; it defines, in the checker, the shape of a step that is immune to it, so that #44
can switch the workflows over and the checker can then refuse anything else (runbook `docs/runbooks/workflow-checker.md`,
"After the claude step"):
- The one shell allowed after the Claude step: `/usr/bin/bash --noprofile --norc -p -eo pipefail {0}` (policy
  `post_claude_shell`; near-misses, lists, mappings, the shell before the Claude step, on a `uses` step, with
  `working-directory`, or as a job or workflow default are refused). An absolute bash is not found through `PATH`; `-p`
  (privileged mode) makes bash read no `BASH_ENV` or `ENV` file, ignore `SHELLOPTS` and `BASHOPTS` from the environment
  and import no function from it (`--noprofile --norc` only skip the profile and rc files). New
  `scripts/check-post-claude-shell.test.sh` proves each of these on the bash that runs the tests (the runners' bash in CI)
  against the policy string, with a control case without `-p`; `GLOBIGNORE` is not claimed (from the environment it has
  no effect with or without `-p` on bash 5.2, and the step env empties it anyway).
- A step with that shell must: set every name in `post_claude_empty_env` to `""` and `post_claude_fixed_env` (`HOME:
  /nonexistent`, `TMPDIR: /tmp`) in its own `env:` (which wins over `$GITHUB_ENV`) - loader, bash, locale, proxy and git
  variables; start its `run:` with `export PATH=/usr/bin:/bin` (`post_claude_run_first`); and have no other line than
  `set -u`, the two pin lines with `/usr/bin/sha256sum` (`post_claude_run_lines`) and pinned scripts started under
  `/usr/bin/env -i PATH=/usr/bin:/bin HOME=/nonexistent TMPDIR=/tmp ...` (`post_claude_script_line`, which may not set a
  loader variable). So no command in the step is found through `PATH` or inherits anything, and a child `bash
  scripts/...` runs in a fresh environment (no `BASH_ENV`, no planted function).
- `post_claude_require_shell` (`false` here, `true` in #44): every run step after the Claude step must be a hardened one.
  Tested both ways against the real workflows: off, they pass; on, every hand-off and probe step is refused.
- Also refused: a workflow-level `defaults:` in a workflow with a Claude step (job-level `defaults` on a job without a
  Claude step stays allowed), more than one Claude step per job, and `shell`/`working-directory` on steps 1-4. The other
  post-Claude rules (pin check before repo scripts, no PR data, no `git` moves, no local action) are tested under the
  hardened shell too.
- `check_other_steps` is split: `check_hardened_step` holds the hardened-step rules; `after` is computed once.
