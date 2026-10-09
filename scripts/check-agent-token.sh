#!/usr/bin/env bash
# Fails unless the GitHub token the agents run with (GH_TOKEN) is the agents' own, limited token (founder-owned):
#  - a fine-grained token (github_pat_..., no classic scopes), or
#  - a classic token (ghp_...) whose only scope is exactly `repo`: no `workflow` (so it cannot change .github/workflows),
#    no admin, gist or other scopes. Fine-grained tokens cannot cover a personal account's repo for a collaborator, so the
#    agents' account (a collaborator on this repo only) uses this until the repo moves to an organization.
# With a founder's token an agent's pushes look like a founder's. Founders are matched by numeric ID and by login.
# Usage: scripts/check-agent-token.sh <founder-ids-file: "<id> <login>" lines>     GH_BIN may point to a stub (tests).
set -euo pipefail
FOUNDERS="${1:?founder ids file}"; GH="${GH_BIN:-gh}"
[ -f "$FOUNDERS" ] || { echo "ERROR: founders file not found: $FOUNDERS"; exit 1; }
# The token itself is never printed; only its kind is checked.
case "${GH_TOKEN:-}" in
  github_pat_*) kind=fine-grained;;
  ghp_*) kind=classic;;
  *) echo "ERROR: GH_TOKEN is not a fine-grained (github_pat_...) or classic (ghp_...) token. Use the agents' own token (see docs/runbooks/agent-network-lock.md)."; exit 1;;
esac
who=$("$GH" api user --jq '"\(.id) \(.login)"' 2>/dev/null || true)
read -r id login <<<"$who" || true
[[ "${id:-}" =~ ^[0-9]+$ && "${login:-}" =~ ^[A-Za-z0-9-]+$ ]] || { echo "ERROR: could not read the token's GitHub login (is GH_TOKEN set and valid?)"; exit 1; }
scopes=$("$GH" api -i user 2>/dev/null | tr -d '\r' | sed -n 's/^[Xx]-[Oo][Aa]uth-[Ss]copes:[[:space:]]*//p' | head -n1 || true)
if [ "$kind" = fine-grained ]; then
  [ -z "$scopes" ] || { echo "ERROR: GH_TOKEN carries classic OAuth scopes ($scopes); use a fine-grained token limited to this repository."; exit 1; }
else
  [ "$(tr -d ' ' <<<"$scopes")" = repo ] || { echo "ERROR: the classic GH_TOKEN must have exactly the scope 'repo' (has: '${scopes:-none}'); no workflow, admin or other scopes."; exit 1; }
fi
while read -r fid flogin _; do
  fid="${fid%%#*}"; [ -n "$fid" ] || continue
  if [ "$fid" = "$id" ] || [ "${flogin,,}" = "${login,,}" ]; then
    echo "ERROR: the agents' GH_TOKEN belongs to founder '$login'. Create the agents' own account and token (see docs/runbooks/agent-network-lock.md) and put it in the AGENT_GH_TOKEN secret."
    exit 1
  fi
done < "$FOUNDERS"
echo "Agent token OK: $kind, runs as '$login' (not a founder)"
