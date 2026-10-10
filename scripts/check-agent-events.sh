#!/usr/bin/env bash
# After each manager shift: the agents' account did nothing outside this repository (founder-owned). The agents' classic
# `repo` token can comment on or open issues in any repository the account can see, which the lock cannot stop
# (api.github.com is allowed), so an injected instruction could post data to a repository an attacker reads. This check
# reads the account's own event feed (private events included, since the token is the account's) and fails if any event
# since the shift started names another repository. Detection after the fact, not prevention (founder decision 1 in
# docs/runbooks/agent-network-lock.md); the fix is an organization-owned repository with a fine-grained token.
# Usage: scripts/check-agent-events.sh <accounts-file> <since: ISO-8601 UTC, e.g. 2026-10-10T05:00:00Z>
# Needs gh with GH_TOKEN (the agents' token). Inside GitHub Actions (GITHUB_ACTIONS set) gh comes from PATH and the
# repository from GITHUB_REPOSITORY; outside (tests) GH_BIN and GH_REPO may override. Prints counts and names, never a token.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/check-accounts-lib.sh
. "$HERE/check-accounts-lib.sh"
ACCOUNTS="${1:?accounts file}"; SINCE="${2:?since (ISO-8601 UTC)}"
if [ -n "${GITHUB_ACTIONS:-}" ]; then GH=gh; REPO="${GITHUB_REPOSITORY:-}"; else GH="${GH_BIN:-gh}"; REPO="${GH_REPO:-${GITHUB_REPOSITORY:-}}"; fi
[[ "$REPO" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || { echo "ERROR: GH_REPO or GITHUB_REPOSITORY (owner/repo) is missing or bad"; exit 1; }
[[ "$SINCE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || { echo "ERROR: since must be an ISO-8601 UTC time like 2026-10-10T05:00:00Z"; exit 1; }
rows=$(accounts_rows "$ACCOUNTS") || { echo "$rows"; exit 1; }
who=$("$GH" api user --jq '"\(.id) \(.login)"' 2>/dev/null || true)
read -r id login <<<"$who" || true
[[ "${id:-}" =~ ^[0-9]+$ && "${login:-}" =~ ^[A-Za-z0-9-]+$ ]] || { echo "ERROR: could not read the token's GitHub login (is GH_TOKEN set and valid?)"; exit 1; }
[ "$(account_field "$rows" "$id" 3)" = agent ] || { echo "ERROR: GH_TOKEN belongs to '$login' (ID $id), which is not an agent account in $ACCOUNTS."; exit 1; }
# The account's events (the API keeps about 90 days / 300 events; the token's own account sees its private events too)
events=$("$GH" api --paginate "users/$login/events?per_page=100" --jq '.[] | "\(.created_at) \(.type) \(.repo.name)"' 2>/dev/null) \
  || { echo "ERROR: could not read the events of '$login' (GitHub API error)."; exit 1; }
total=0; outside=""
while read -r at type repo; do
  [ -n "$at" ] || continue
  [[ "$at" > "$SINCE" || "$at" = "$SINCE" ]] || continue   # ISO-8601 UTC strings sort as times
  total=$((total+1))
  [ "$repo" = "$REPO" ] || outside="$outside$at $type $repo"$'\n'
done <<<"$events"
if [ -n "$outside" ]; then
  echo "ERROR: the agents' account '$login' acted outside $REPO since $SINCE:"
  printf '%s' "$outside"
  echo "A founder reads those events (what was posted where), rotates AGENT_GH_TOKEN and checks the shift's log; agents must not run until then."
  exit 1
fi
echo "Agent events OK: $total event(s) by '$login' since $SINCE, all in $REPO"
