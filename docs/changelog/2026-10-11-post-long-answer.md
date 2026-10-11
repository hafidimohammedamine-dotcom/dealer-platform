# 2026-10-11 - the post job survives a review over 60000 characters

Founder change (`scripts/check-review-post.sh`, `scripts/check-claude-answer.sh`, pins). The re-review of PR #43
(run 38111418181) completed, but the post job died with `printf: write error: Broken pipe` before posting: the first
line of the answer was taken with `printf | head -n1`, and on a long answer `head` closes the pipe early, `printf`
fails, and `set -e -o pipefail` exits. Same bug class as 2026-10-11-long-review-answer.md (the hand-off step); both
are gone.
- `check-review-post.sh`: the first line is now cut in bash. The 60000-character comment cut is computed, then gitleaks
  scans the whole handed text and the exact text to be posted in one run, and only then is anything posted (before, a
  secret straddling the 60000-character cut was posted in part). The cut counts characters (`LC_ALL=C.UTF-8`), never
  bytes. Tests: long PASS and FAIL answers, a long single-line answer, a CR first line, a secret across the cut.
- `check-claude-answer.sh` (the hand-off) no longer cuts at 60000: it hands over at most 120000 bytes of UTF-8 (the post
  job receives the answer as one environment variable; Linux rejects one over 128 KiB), and that handed text is all the
  post job ever sees or scans. Before it leaves the review job it is scanned with the pinned gitleaks (installed by the
  egress lock action): a job output is printed in the post job's log header, and the repo is public, so anything that
  looks like a secret is replaced by a fixed notice there (the post job then posts FAIL); the post job's own scan stays.
  A longer answer is cut at the last line break, space or tab before the cap, and never inside a `-----BEGIN ...
  -----END` block (blocks paired like brackets: an END line closes the nearest open BEGIN; the kept text stops before
  the first BEGIN left open), so a token or a key block is never handed over in part; when nothing before the cap is
  safe to keep, the text is withheld and a notice is handed over. Every cut ends with a fixed `(truncated)` line so a
  reader sees the end is missing even when the post job's own cut does not run. Bytes that are not UTF-8 become U+FFFD
  and NULs are removed before the cap is measured, so the handed text is never over 120000 bytes. The cut uses no temp
  file (jq -> python -> stdout); the scan writes the cut text to a temporary directory deleted on exit; and the output
  block is printed only once the whole text is in hand: a failing jq or python exits non-zero with no half-written
  block. End-to-end tests (hand-off, then post): a secret across 60000 (withheld); 70000 four-byte characters in the
  answer, about 30000 posted with the marker; a token across the 120000-byte cap (never handed over); a key block across
  the cap after multibyte filler (never handed over or posted).
- A withheld hand-off (the notice instead of the text) has no `REVIEW TEAM RESULT:` first line, so the post job posts
  FAIL and sets `changes-requested` whatever the review said; the review's result is lost (no job log holds it), and a
  founder re-runs the review (`docs/runbooks/ci-guards.md`, "Post the result").
- The cut is `scripts/check-claude-answer-cut.py` (pinned; its rules are in its docstring), run by the hand-off script.
- Failure path: if the hand-off fails (jq or the cutter fails, the scanner is missing, or the scanner exits with a code
  other than 0 or 3), the step fails with the cause in the review job log, the post job is skipped, nothing is posted
  and no label changes; a founder re-runs the review. A cut PASS keeps its labels (its verdict line is posted; a PASS
  has no findings to lose); only a withheld answer loses its result.
- `scripts/check-scan-lib.sh` (pinned): the one gitleaks call (`scan_answer <dir>`) both the hand-off and the post
  script use; `check-review-post.sh` stops if the runner lacks the C.UTF-8 locale (bash would count bytes).
- The scan checks the scanner: `scan_answer` compares `/tmp/gitleaks` with the pinned binary sha256 (a swapped or edited
  binary is an error, nothing is handed over or posted), and every hand-off and blocked-call step runs the script under
  `/usr/bin/env -i` with `PATH=/usr/bin:/bin`, `GITLEAKS_BIN=/tmp/gitleaks`, an empty `GITLEAKS_SHA256` (the pinned
  constant in `check-scan-lib.sh` is the one copy of the hash), `BASH_ENV` and `LD_PRELOAD` empty, and
  `/usr/bin/sha256sum` by absolute path, so nothing a Claude step put on `PATH` or in `$GITHUB_ENV` is used (the manager
  runs Claude with full Bash). A cut that would keep nothing (a line break at index 0) hands over the withheld notice,
  never an empty answer. `scripts/check-claude-answer-cut.test.sh` tests `cut()` directly; the post tests run one case
  with the real pinned gitleaks when it is installed.
- `check-claude-answer.sh blocked` scans the denied-call lines before printing them: on a hit it prints `BLOCKED <tool>:
  (withheld: looks like a secret)` per denial; a scanner error fails the step with nothing printed (the post job is then
  skipped in the jobs that have one).
- Review round 18 (founder decisions): the five post-Claude steps use the one shell the workflow checker now allows
  after a Claude step (`/usr/bin/bash --noprofile --norc -eo pipefail {0}`, policy key `post_claude_shell`) with
  `BASH_ENV` and `LD_PRELOAD` emptied in the step's own `env:`; the scan hashes and runs a private copy of the scanner
  (so the file that was checked is the file that runs; the directory is still the runner user's, which is the same
  accepted leftover-process risk). Not done, on purpose: a composite action for the hand-off step (the checker forbids
  local actions after a Claude step, since their files could have changed; nine near-identical lines are the price of
  that rule), and copying the pinned scripts themselves before running them (the pins check and the run are in one step,
  and a process left over from the sandboxed Claude step would also have to own the checkout; accepted as a residual
  risk).
- Review round 19: the hand-off steps also empty `LD_LIBRARY_PATH`, `LD_AUDIT`, `SHELLOPTS`, `BASHOPTS`, `PS4`,
  `GLOBIGNORE`, `GCONV_PATH` and `ENV` and fix `HOME` in their own `env:`; the inner run uses `HOME=/nonexistent` and
  `TMPDIR=/tmp`; the workflow checker requires all of that on any step that runs the hand-off script (policy keys
  `post_claude_empty_env`, `post_claude_fixed_env`, `post_claude_handoff`). `check-claude-answer.sh` fixes `HOME` itself
  (jq never loads a planted `~/.jq`) and, when the blocked-call lines look like a secret, prints one fixed line with the
  count. `scripts/check-scan-lib.test.sh` tests the scan library on its own, and checks the pinned hash against the
  installed binary wherever it is installed (CI). The three egress probe jobs keep their own step: they run
  `check-claude-probe.py` on a fixed prompt and hand nothing to a post job (founder decision).
