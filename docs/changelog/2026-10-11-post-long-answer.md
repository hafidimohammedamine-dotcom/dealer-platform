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
  and NULs are removed before the cap is measured, so the handed text is never over 120000 bytes. The text goes jq ->
  python -> stdout (no temp file), and the output block is printed only once the whole text is in hand: a failing jq or
  python exits non-zero with no half-written block. End-to-end tests (hand-off, then post): a secret across 60000
  (withheld); 70000 four-byte characters in the answer, about 30000 posted with the marker; a token across the
  120000-byte cap (never handed over); a key block across the cap after multibyte filler (never handed over or posted).
- A withheld hand-off (the notice instead of the text) has no `REVIEW TEAM RESULT:` first line, so the post job posts
  FAIL and sets `changes-requested` whatever the review said; the review's result is lost (no job log holds it), and a
  founder re-runs the review (`docs/runbooks/ci-guards.md`, "Post the result").
- The cut is `scripts/check-claude-answer-cut.py` (pinned; its rules are in its docstring), run by the hand-off script.
