#!/usr/bin/env bash
# Posts an agent's final answer from a fixed workflow step (the agent itself cannot post or label).
# Reads the final answer from the claude-code-action execution file, scans it for secrets with the repo's
# .gitleaks.toml, and posts it.
#   pr mode:    the answer must start with "REVIEW TEAM RESULT: PASS|FAIL"; labels are set from that line.
#   issue mode: the answer is posted as a comment on the issue (daily report, weekly audit); no labels.
# Usage: scripts/check-review-post.sh <pr|issue> <number> <execution-file>   GH_BIN / GITLEAKS_BIN may point to stubs.
set -euo pipefail
MODE="${1:?pr or issue}"; PR="${2:?number}"; EXEC="${3:?execution file}"
case "$MODE" in pr|issue) ;; *) echo "ERROR: mode must be pr or issue"; exit 1;; esac
GH="${GH_BIN:-gh}"; GITLEAKS="${GITLEAKS_BIN:-/tmp/gitleaks}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ "$PR" =~ ^[0-9]+$ ]] || { echo "ERROR: bad PR number"; exit 1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

text=""
if [ -f "$EXEC" ]; then
  text=$(jq -r '[.[]? | select(.type == "result")] | last | .result // empty' "$EXEC" 2>/dev/null || true)
fi
first=$(printf '%s\n' "$text" | head -n1 | tr -d '\r')
if [ "$MODE" = issue ]; then
  [ -n "$text" ] || text="The scheduled agent job did not produce a report. A founder should check the job log."
  first="REVIEW TEAM RESULT: PASS"   # format check only applies to PRs
fi
case "$first" in
  "REVIEW TEAM RESULT: PASS"|"REVIEW TEAM RESULT: FAIL") ;;
  *) text=$'REVIEW TEAM RESULT: FAIL\nThe review job did not produce a valid result (missing or wrong first line). A founder should re-run the review.'
     first="REVIEW TEAM RESULT: FAIL";;
esac
if [ "${#text}" -gt 60000 ]; then text="${text:0:60000}"$'\n\n(truncated)'; fi

printf '%s\n' "$text" > "$T/body.md"
mkdir -p "$T/scan" "$T/noignore"; cp "$T/body.md" "$T/scan/body.md"
set +e
"$GITLEAKS" detect --no-git --source="$T/scan" --config="$ROOT/.gitleaks.toml" --gitleaks-ignore-path="$T/noignore" \
  --ignore-gitleaks-allow --exit-code 3 --redact >/dev/null 2>&1
rc=$?
set -e
case $rc in
  0) ;;
  3) printf '%s\n' "REVIEW TEAM RESULT: FAIL" "The agent's answer contained something that looks like a secret, so it was not posted. A founder should check the job." > "$T/body.md"
     first="REVIEW TEAM RESULT: FAIL";;
  *) echo "ERROR: gitleaks failed with exit code $rc"; exit 1;;
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
