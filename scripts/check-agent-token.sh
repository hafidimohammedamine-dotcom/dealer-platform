#!/usr/bin/env bash
# Fails if the GitHub token the agents run with (GH_TOKEN) belongs to a founder (founder-owned).
# Agents must use their own account's fine-grained token (this repo only, no Workflows permission, no admin): with a
# founder's token an agent's pushes look like a founder's, so founder-only checks would pass for them.
# Usage: scripts/check-agent-token.sh <founders-file>     GH_BIN may point to a stub (tests).
set -euo pipefail
FOUNDERS="${1:?founders file}"; GH="${GH_BIN:-gh}"
[ -f "$FOUNDERS" ] || { echo "ERROR: founders file not found: $FOUNDERS"; exit 1; }
login=$("$GH" api user --jq .login 2>/dev/null || true)
[[ "$login" =~ ^[A-Za-z0-9-]+$ ]] || { echo "ERROR: could not read the token's GitHub login (is GH_TOKEN set and valid?)"; exit 1; }
while IFS= read -r f; do
  f="${f%%#*}"; f="${f//[[:space:]]/}"
  [ -n "$f" ] || continue
  if [ "${f,,}" = "${login,,}" ]; then
    echo "ERROR: the agents' GH_TOKEN belongs to founder '$login'. Create the agents' own account and token (see docs/runbooks/agent-network-lock.md) and put it in the AGENT_GH_TOKEN secret."
    exit 1
  fi
done < "$FOUNDERS"
echo "Agent token OK: runs as '$login' (not a founder)"
