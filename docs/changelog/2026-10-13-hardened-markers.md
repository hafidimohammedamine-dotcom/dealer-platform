# 2026-10-13 - hardened steps: the marker line and the hardened-check job (checker rules; the workflows follow)

Founder change under #50 (`scripts/check-workflows-hardened.py`, `scripts/check-workflows-claude.py`,
`scripts/check-workflows.py`, `scripts/check-workflows-policy.json`, the eight hardened steps' `env:` blocks and ids,
tests, runbook, pins). From the last reviews of #44 and #48:

- The one thing a step env cannot blank away: `LD_TRACE_LOADED_OBJECTS` makes every dynamically linked program, bash
  included, print its libraries and exit 0 before line 1, even with an empty value - `scripts/check-post-claude-shell.test.sh`
  now proves it against a full hardened body, next to the case where planted `PATH`, `BASH_ENV` and blanked loader
  names leave the body running. A hardened step that went green could therefore have run nothing. The answer is a
  positive marker: a hardened step ends with `echo "hardened=ok" >> "$GITHUB_OUTPUT"`, the job exports it as
  `<id>_ran`, and a `hardened-check` job with no Claude step (`needs` every job with marked steps, `if: always()`) fails
  unless every marker is `ok` or the job was skipped. The checker knows the whole shape (runbook, "After the claude
  step"). `post_claude_require_marker` is `false` here: the marker is allowed, not yet required, because the guards run
  main's checker over a PR's tree and main's checker refuses the marker line today; the next founder PR adds the marker
  and the check job to the eight steps and flips the flag. The `review` hand-off already fails closed on its own
  (`has_result` is never written, the post job is skipped); the manager's blocked-call listing and the three lock
  self-test steps are what the marker protects.
- Every hardened step needs an `id` and may carry only `name`, `if`, `id`, `shell`, `env`, `run`; `continue-on-error`
  is refused on every step and job of a claude job; `${{ ... }}` is refused anywhere in a hardened `run`, comments
  included; the `NAME=value` part of a script line is a mapping of exact values (`GITLEAKS_BIN=/tmp/gitleaks` only -
  the scan library's pinned constant is the one hash, so `GITLEAKS_SHA256=` leaves the eight lines); the rest of the
  loader's documented names and `MALLOC_MMAP_MAX_` are blanked as defence in depth; the pin-check substring rule skips
  comments (full-line and inline); `code_lines()` is shared by the two modules.
- Tests: `scripts/check-workflows-shell.test.sh` covers both marker states through the copy's own checker (the real
  workflows: on, all eight steps lack the marker; the fixture: outputs, the check job's every key, a check job with no
  marked step), the step keys, `${{`, `continue-on-error`, the case-twin names. `scripts/check-claude-answer.sh` counts
  denials with jq (a multi-line denied command is one denial; tested). The self-replacing gitleaks stub and the
  real-gitleaks gate (`real_gitleaks <name>`: FAIL under CI without the binary, a recorded skip elsewhere) live in
  `scripts/check-testlib.sh` and are used by the three tests that need them; the coverage fixture calls them.
