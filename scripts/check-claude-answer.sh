#!/usr/bin/env bash
# Reads the claude-code-action execution file after a Claude step (founder-owned; runs in every Claude job, pinned):
#   blocked <execution-file>   print "BLOCKED <tool>: <command or path>" for every denied tool call (names and commands
#                              only, 300 characters each), so the job log shows what the deny lists stopped
#   answer  <execution-file>   print GitHub job outputs: has_result=true|false and, when there is an answer, `answer` as a
#                              multi-line output for the post job: the last result's text, at most 120000 bytes of UTF-8.
#                              The post job receives it as ONE environment variable (ANSWER), and Linux rejects a single
#                              variable over 128 KiB at exec time, so the cap is in bytes, measured after the text is
#                              cleaned. A longer answer is cut at the last line break or blank before the cap, and never
#                              inside a -----BEGIN ... -----END block (the cut moves to before the BEGIN line), so a
#                              token or a key block is never handed over in part; when nothing before the cap is safe
#                              to keep, the text is withheld and a notice is handed over instead. A fixed ASCII
#                              "(truncated)" line is added after every cut so the reader can see the end is missing.
#                              The handed text goes to check-review-post.sh, which scans it (all of it, and the
#                              60000-character cut it posts) for secrets before posting; it is all the post job sees.
#                              Nothing is written to disk: the text goes jq -> python -> stdout, and the output block is
#                              printed only once the whole text is in hand (a failure prints no half block and exits
#                              non-zero).
# Usage: scripts/check-claude-answer.sh blocked|answer <execution-file>   (an empty or missing file is "no result")
set -euo pipefail
CMD="${1:-}"; EXEC="${2:-}"
case "$CMD" in blocked|answer) ;; *) echo "usage: check-claude-answer.sh blocked|answer <execution-file>" >&2; exit 2;; esac
have=0; [ -n "$EXEC" ] && [ -f "$EXEC" ] && jq -e 'type == "array"' "$EXEC" >/dev/null 2>&1 && have=1
if [ "$CMD" = blocked ]; then
  [ "$have" = 1 ] || { echo "no execution file"; exit 0; }
  jq -r '[.[]? | select(.type == "result")] | last | (.permission_denials // [])[]
         | "BLOCKED " + (.tool_name // "?") + ": " + ((.tool_input.command // .tool_input.file_path // .tool_input.url // "") | tostring | .[0:300])' "$EXEC"
  exit 0
fi
if [ "$have" != 1 ]; then echo "has_result=false"; exit 0; fi
# Read the whole text, then cut it in Python: `jq | head -c` would kill jq with SIGPIPE on a long answer and, under
# pipefail, fail this script (a review over 60000 characters then posted nothing). Python reads all of stdin, so jq is
# never cut off. Bytes that are not UTF-8 become U+FFFD (never dropped) and NUL bytes are removed (a job output cannot
# carry them) before the cap is measured. Trailing newlines are not kept.
text=$(jq -r '[.[]? | select(.type == "result")] | last | .result // empty' "$EXEC" | python3 -I -c '
import sys
LIMIT, MARK = 120000, b"\n\n(truncated)"
b = sys.stdin.buffer.read().decode("utf-8", "replace").encode("utf-8").replace(b"\0", b"").rstrip(b"\n")   # clean, then measure
if len(b) > LIMIT:
    keep = LIMIT - len(MARK)
    cut = max(b.rfind(b"\n", 0, keep + 1), b.rfind(b" ", 0, keep + 1), b.rfind(b"\t", 0, keep + 1))   # last line break or blank
    if cut >= 0:   # a key or certificate block (-----BEGIN ... -----END) open at the cut: cut before its BEGIN line instead
        begin = b.rfind(b"-----BEGIN", 0, cut)
        if begin > b.rfind(b"-----END", 0, cut): cut = b.rfind(b"\n", 0, begin)
    if cut < 0:   # nothing safe to keep: never hand over a part of a token or of a block (a cut one could pass the scan)
        b = b"(answer withheld: no line break or blank before the 120000-byte limit)"
    else:
        b = b[:cut].rstrip(b"\n")
    b += MARK
sys.stdout.buffer.write(b)
')
d="ANSWER_$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"   # a delimiter the answer cannot contain by accident
echo "has_result=true"
echo "answer<<$d"
printf '%s\n' "$text"
echo "$d"
