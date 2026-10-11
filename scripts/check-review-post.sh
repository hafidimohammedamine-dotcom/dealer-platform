#!/usr/bin/env bash
# Posts an agent's final answer from a fixed workflow step (the agent itself cannot post or label): scans the answer for
# secrets with the repo's .gitleaks.toml, then posts it.
#   pr mode:    the answer must start with "REVIEW TEAM RESULT: PASS|FAIL"; labels are set from that line.
#   issue mode: the answer is posted as a comment on the issue (a founder's @claude answer, claude.yml); no labels.
#   daily-reports mode: like issue mode on the open issue titled "Daily reports" (created if missing); no number argument.
# The answer comes from the ANSWER environment variable: the text a Claude job handed over as a job output
# (scripts/check-claude-answer.sh); the post job runs no Claude and has no execution file.
# Usage: ANSWER=<text> scripts/check-review-post.sh <pr|issue> <number>   or   check-review-post.sh daily-reports
#        GH_BIN / GITLEAKS_BIN may point to stubs.
set -euo pipefail
export LC_ALL=C.UTF-8   # ${#text} and ${text:0:60000} count characters, never bytes (a byte cut could split a multibyte character)
probe="${LOCALE_PROBE:-$'\xc3\xa9'}"   # "é": one character under a UTF-8 locale, two bytes if the runner lacks C.UTF-8 (tests may set LOCALE_PROBE)
[ "${#probe}" = 1 ] || { echo "ERROR: the C.UTF-8 locale is missing on this runner (bash counts bytes)"; exit 1; }
MODE="${1:?pr, issue or daily-reports}"
case "$MODE" in
  pr|issue) PR="${2:?number}";;
  daily-reports) PR="";;
  *) echo "ERROR: mode must be pr, issue or daily-reports"; exit 1;;
esac
GH="${GH_BIN:-gh}"
. "$(dirname "$0")/check-scan-lib.sh"   # scan_answer (GITLEAKS_BIN)
[ "$MODE" = daily-reports ] || [[ "$PR" =~ ^[0-9]+$ ]] || { echo "ERROR: bad PR number"; exit 1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

text="${ANSWER:-}"
if [ "$MODE" = daily-reports ]; then   # the founders' running thread; MODE becomes issue below
  PR=$("$GH" issue list --state open --search '"Daily reports" in:title' --json number,title --jq '[.[] | select(.title == "Daily reports")][0].number // empty')
  [ -n "$PR" ] || PR=$("$GH" issue create --title "Daily reports" --body "Daily founder reports and weekly audits." | sed 's#.*/##')
  [[ "$PR" =~ ^[0-9]+$ ]] || { echo "ERROR: could not find or create the Daily reports issue"; exit 1; }
  MODE=issue
fi
# The first line, cut in bash: `printf | head -n1` dies of SIGPIPE on a long answer (pipefail + set -e then exit 1 before
# anything is posted, which hid the review of PR #43 on 2026-10-11).
first="${text%%$'\n'*}"; first="${first//$'\r'/}"
if [ "$MODE" = issue ]; then
  [ -n "$text" ] || text="The agent job did not produce an answer. A founder should check the job log."
  first="REVIEW TEAM RESULT: PASS"   # format check only applies to PRs
fi
case "$first" in
  "REVIEW TEAM RESULT: PASS"|"REVIEW TEAM RESULT: FAIL") ;;
  *) text=$'REVIEW TEAM RESULT: FAIL\nThe review job did not produce a valid result (missing or wrong first line). A founder should re-run the review.'
     first="REVIEW TEAM RESULT: FAIL";;
esac
# Secret scan before anything is posted, on two files in one gitleaks run: the whole answer (a secret that straddles the
# 60000-character cut is caught whole) and the exact text that would be posted (a cut-off start of a long token, or the
# `(truncated)` marker next to it, could match a rule the whole token does not). The post body is written only on rc=0.
post="$text"; if [ "${#post}" -gt 60000 ]; then post="${post:0:60000}"$'\n\n(truncated)'; fi
mkdir -p "$T/scan"; printf '%s\n' "$text" > "$T/scan/full.md"; printf '%s\n' "$post" > "$T/scan/post.md"
set +e; scan_answer "$T/scan"; rc=$?; set -e
case $rc in
  0) cp "$T/scan/post.md" "$T/body.md";;
  3) printf '%s\n' "REVIEW TEAM RESULT: FAIL" "The agent's answer contained something that looks like a secret, so it was not posted. A founder should re-run the review (see docs/runbooks/ci-guards.md, \"Post the result\")." > "$T/body.md"
     first="REVIEW TEAM RESULT: FAIL";;
  *) echo "ERROR: the secret scan failed with exit code $rc"; exit 1;;
esac

if [ "$MODE" = issue ]; then
  "$GH" issue comment "$PR" --body-file "$T/body.md"
  echo "Posted to issue #$PR"; exit 0
fi
"$GH" pr comment "$PR" --body-file "$T/body.md"
if [ "$first" = "REVIEW TEAM RESULT: PASS" ]; then
  "$GH" pr edit "$PR" --add-label reviews-passed --add-label ready-to-merge --remove-label changes-requested
  echo "Posted PASS"
else
  "$GH" pr edit "$PR" --add-label changes-requested --remove-label reviews-passed --remove-label ready-to-merge
  echo "Posted FAIL"
fi
