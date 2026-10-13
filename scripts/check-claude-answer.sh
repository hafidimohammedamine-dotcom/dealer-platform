#!/usr/bin/env bash
# Reads the claude-code-action execution file after a Claude step (founder-owned; runs in every Claude job, pinned):
#   blocked <execution-file>   print "BLOCKED <tool>: <command or path>" for every denied tool call (names and commands
#                              only, 300 characters each), so the job log shows what the deny lists stopped; the lines
#                              are scanned with the pinned gitleaks first; on a hit one fixed line with the count is printed
#   answer  <execution-file>   print GitHub job outputs: has_result=true|false and, when there is an answer, `answer` as a
#                              multi-line output for the post job: the last result's text, cut to at most 120000 bytes of
#                              UTF-8 by scripts/check-claude-answer-cut.py (rules in its docstring), then scanned with the
#                              pinned gitleaks (GITLEAKS_BIN, default /tmp/gitleaks, installed by the egress lock action) so
#                              nothing that looks like a secret ever leaves the job (a job output shows up in the post
#                              job's log header); the output block is printed only once the whole text is in hand (a
#                              failure prints no half block and exits non-zero)
# Usage: scripts/check-claude-answer.sh blocked|answer <execution-file>   (an empty or missing file is "no result")
set -euo pipefail
CMD="${1:-}"; EXEC="${2:-}"
case "$CMD" in blocked|answer) ;; *) echo "usage: check-claude-answer.sh blocked|answer <execution-file>" >&2; exit 2;; esac
export HOME=/nonexistent   # jq would load $HOME/.jq; nothing of the caller's home is used here
have=0; [ -n "$EXEC" ] && [ -f "$EXEC" ] && jq -e 'type == "array"' "$EXEC" >/dev/null 2>&1 && have=1
. "$(dirname "$0")/check-scan-lib.sh"   # scan_answer: the pinned gitleaks (GITLEAKS_BIN); the job log is public
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; mkdir -p "$T/scan"
denials='[.[]? | select(.type == "result")] | last | (.permission_denials // [])[]'   # the last result's denied tool calls
if [ "$CMD" = blocked ]; then
  [ "$have" = 1 ] || { echo "no execution file"; exit 0; }
  # The denied tool inputs are Claude's own commands, paths and URLs: scanned before they reach the log, like the answer.
  jq -r "$denials"' | "BLOCKED " + (.tool_name // "?") + ": " + ((.tool_input.command // .tool_input.file_path // .tool_input.url // "") | tostring | .[0:300])' "$EXEC" > "$T/scan/blocked.md"
  set +e; scan_answer "$T/scan"; rc=$?; set -e
  case $rc in
    0) cat "$T/scan/blocked.md";;
    3) echo "BLOCKED: $(jq "[$denials] | length" "$EXEC") denied tool call(s); the names and inputs are withheld (something looks like a secret)";;
    *) echo "ERROR: the secret scan failed with exit code $rc" >&2; exit 1;;
  esac
  exit 0
fi
if [ "$have" != 1 ]; then echo "has_result=false"; exit 0; fi
# Read the whole text, then cut it with check-claude-answer-cut.py (the rules are in its docstring): `jq | head -c` would
# kill jq with SIGPIPE on a long answer and, under pipefail, fail this script (a review over 60000 characters then posted
# nothing). The cutter reads all of stdin, so jq is never cut off.
text=$(jq -r '[.[]? | select(.type == "result")] | last | .result // empty' "$EXEC" | python3 -I "$(dirname "$0")/check-claude-answer-cut.py")
# Secret scan BEFORE the text leaves this job: the post job gets it as a step `env:` value, and GitHub prints those in the
# step's log header (public logs). Anything that looks like a secret is replaced by a fixed notice (the post job then posts
# FAIL); a missing scanner or a scanner error fails this step (nothing is handed over, the post job is skipped).
printf '%s\n' "$text" > "$T/scan/answer.md"
set +e; scan_answer "$T/scan"; rc=$?; set -e
case $rc in 0) ;; 3) text="(answer withheld: it contained something that looks like a secret)";; *) echo "ERROR: the secret scan failed with exit code $rc" >&2; exit 1;; esac
d="ANSWER_$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"   # a delimiter the answer cannot contain by accident
echo "has_result=true"
echo "answer<<$d"
printf '%s\n' "$text"
echo "$d"
