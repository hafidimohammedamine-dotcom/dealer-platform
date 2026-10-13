# 2026-10-11 - the workflow checker: one hardened shell after a Claude step, and what a step with it must look like

Founder change (`scripts/check-workflows-hardened.py` (new), `scripts/check-workflows-claude.py`,
`scripts/check-workflows.py`, `scripts/check-workflows-policy.json`, tests, runbook, pins; the eight workflow files
change only by their `PINS_SHA256` value - no workflow behaviour changes here). Split out of #44 because the guards run
the base branch's checker over a PR's tree: #44's hand-off steps set a `shell:`, and main's checker refused every
`shell:` in a Claude job. This PR adds only the checker rules; no workflow in this PR uses the shell (#44 puts it on the
post-Claude steps and turns `post_claude_require_shell` on).

Plainly, the problem: a Claude step can write `$GITHUB_ENV` and `$GITHUB_PATH` (the egress lock does not block those
files; the manager runs with bypassPermissions), and a later step's default `bash` honours both - `PATH`, `BASH_ENV`,
`LD_PRELOAD`, planted `BASH_FUNC_<name>%%` functions. On main today every post-Claude step runs that way, with only its
pin check between the Claude session and the repository scripts it runs (and `sha256sum` itself is found through
`PATH`). **Founder decision (risk accepted for the window between the two merges):** this PR merges first with
`post_claude_require_shell: false`, and #44 - the same checker, the flag on, the eight post-Claude steps hardened - is
already in review and merges next; the two cannot be one PR, and the window is hours, during which the agents' jobs run
as they have since the first shift. This PR defines, in the checker, the shape of a step that is immune to the problem
(runbook `docs/runbooks/workflow-checker.md`, "After the claude step"):
- The one shell allowed after the Claude step: `/usr/bin/bash --noprofile --norc -p -eo pipefail {0}` (policy
  `post_claude_shell`; near-misses, lists, mappings, the shell before the Claude step, on a `uses` step, with
  `working-directory`, or as a job or workflow default are refused). An absolute bash is not found through `PATH`; `-p`
  (privileged mode) makes bash read no `BASH_ENV` or `ENV` file, ignore `SHELLOPTS`, `BASHOPTS` and `CDPATH` from the
  environment and import no function from it (`--noprofile --norc` only skip the profile and rc files). New
  `scripts/check-post-claude-shell.test.sh` proves those five on the bash that runs the tests (it prints the version;
  the runners' bash in CI) against the policy string, with a control case without `-p`. `GLOBIGNORE` is not claimed
  (from the environment it has no effect with or without `-p` on bash 5.2; the step env empties it anyway).
- A step with that shell must: set every name in `post_claude_empty_env` to `""` (bash, loader and libc, locale and
  time, resolver, proxy and git variables - the full list is in the runbook) and `post_claude_fixed_env` (`HOME:
  /nonexistent`, `TMPDIR: /tmp`) in its own `env:` (which wins over `$GITHUB_ENV`); set `PINS_SHA256` there to the hash
  of `.github/pins.txt` (never from `$GITHUB_ENV`) and every other `$NAME` its body reads (`GITHUB_OUTPUT` excepted:
  `GITHUB_*` cannot be overridden - "the assignment is ignored", GitHub Docs, "Variables reference"); hold only
  printable ASCII, tabs and newlines in its `run:` (bash and the checker split the same lines; `\r`, `\v`, `\f`,
  U+0085, U+2028, U+2029 are refused); start with `export PATH=/usr/bin:/bin`, `set -u` and the two pin lines with
  `/usr/bin/sha256sum`, in that order (`post_claude_run_first`, `post_claude_run_prefix`; a comment is not a pin
  check); and have no other line than pinned scripts started under `/usr/bin/env -i PATH=/usr/bin:/bin HOME=/nonexistent
  TMPDIR=/tmp ...` (`post_claude_script_line`; extra `NAME=value` only from `post_claude_script_env`, so no second `PATH`,
  `HOME`, `TMPDIR` or loader variable). So no command in the step is found through `PATH` or inherits anything, and a
  child `bash scripts/...` runs in a fresh environment.
- `post_claude_require_shell` (`false` here, `true` in #44): every run step after the Claude step must be a hardened one.
  Tested both ways against the real workflows: off, they pass; on, exactly the eight post-Claude steps (five hand-off,
  three probe) are refused, each by name.
- Also refused: a workflow-level `defaults:` in a workflow with a Claude step (job-level `defaults` on a job without a
  Claude step stays allowed), more than one Claude step per job, and `shell`/`working-directory` on steps 1-4. The other
  post-Claude rules (pin check before repo scripts - comment lines no longer count -, no PR data, no `git` moves, no
  local action) are tested under the hardened shell too.
- Layout: the hardened-step rules are their own module, `scripts/check-workflows-hardened.py` (pinned); their tests are
  `scripts/check-workflows-shell.test.sh`, with the shared helpers in `scripts/check-workflows-testlib.sh`.
