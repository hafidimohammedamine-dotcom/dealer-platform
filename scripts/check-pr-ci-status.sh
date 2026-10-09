#!/usr/bin/env bash
# Waits for the two workflow runs a PR head needs, found by WORKFLOW FILE and EVENT (not by check name, which a PR
# could imitate), then prints "ci=<result> guards=<result>" where result is success|failure|cancelled|...|pending.
#   CI:     .github/workflows/ci.yml,     event pull_request,        headSha == <head-sha>
#   Guards: .github/workflows/guards.yml, event pull_request_target, title "Guards PR #<n> @ <head-sha>"
#           (pull_request_target runs carry the base commit as headSha, so guards.yml puts the PR head in its run-name)
# Usage: scripts/check-pr-ci-status.sh <pr-number> <head-sha> [timeout-seconds=1800] [interval-seconds=30]
# GH_BIN may point to a stub for tests.
set -euo pipefail
PR="${1:?pr number}"; SHA="${2:?head sha}"; TIMEOUT="${3:-1800}"; INTERVAL="${4:-30}"
GH="${GH_BIN:-gh}"
[[ "$PR" =~ ^[0-9]+$ ]] || { echo "ERROR: bad PR number"; exit 1; }
[[ "$SHA" =~ ^[0-9a-f]{40}$ ]] || { echo "ERROR: bad head sha"; exit 1; }

latest() { # latest <workflow-file> <event> <jq-filter-on-run> -> "status/conclusion" of newest matching run, or "missing"
  local r
  r=$("$GH" run list --workflow "$1" --event "$2" --limit 50 --json headSha,displayTitle,status,conclusion,createdAt \
       --jq "[.[] | select($3)] | sort_by(.createdAt) | last | if . == null then \"missing\" else .status + \"/\" + (.conclusion // \"\") end")
  echo "${r:-missing}"
}
result() { case "$1" in completed/*) echo "${1#completed/}";; *) echo pending;; esac; }

deadline=$(( $(date +%s) + TIMEOUT ))
while :; do
  ci=$(latest ci.yml pull_request ".headSha == \"$SHA\"")
  guards=$(latest guards.yml pull_request_target ".displayTitle == \"Guards PR #$PR @ $SHA\"")
  echo "ci=$ci guards=$guards" >&2
  if [[ "$ci" == completed/* && "$guards" == completed/* ]] || [ "$(date +%s)" -ge "$deadline" ]; then break; fi
  sleep "$INTERVAL"
done
echo "ci=$(result "$ci") guards=$(result "$guards")"
