#!/usr/bin/env bash
# Fails unless the GitHub token the agents run with (GH_TOKEN) belongs to the agents' own account and is limited
# (founder-owned). Run before Claude in every job that holds AGENT_GH_TOKEN (scripts/check-workflows.sh enforces that).
#  - The token's user ID must be an `agent` row of .github/accounts.txt (IDs, not logins: a login can be re-registered),
#    so a founder's token, or anyone else's, stops the job: with a founder's token an agent's pushes look like a founder's.
#  - The token must be fine-grained (github_pat_..., no classic scopes) or classic (ghp_...) with exactly the scope `repo`:
#    no `workflow` (it cannot change .github/workflows), no admin, gist or other scopes. Fine-grained tokens cannot cover
#    a personal account's repository for a collaborator, so the agents' account uses a classic `repo` token until the
#    repository moves to an organization.
# Usage: scripts/check-agent-token.sh <accounts-file>     GH_BIN may point to a stub (tests). The token is never printed.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/check-accounts-lib.sh
. "$HERE/check-accounts-lib.sh"
ACCOUNTS="${1:?accounts file}"; GH="${GH_BIN:-gh}"
rows=$(accounts_rows "$ACCOUNTS") || { echo "$rows"; exit 1; }
case "${GH_TOKEN:-}" in
  github_pat_*) kind=fine-grained;;
  ghp_*) kind=classic;;
  *) echo "ERROR: GH_TOKEN is not a fine-grained (github_pat_...) or classic (ghp_...) token. Use the agents' own token (see docs/runbooks/agent-network-lock.md)."; exit 1;;
esac
who=$("$GH" api user --jq '"\(.id) \(.login)"' 2>/dev/null || true)
read -r id login <<<"$who" || true
[[ "${id:-}" =~ ^[0-9]+$ && "${login:-}" =~ ^[A-Za-z0-9-]+$ ]] || { echo "ERROR: could not read the token's GitHub login (is GH_TOKEN set and valid?)"; exit 1; }
role=$(account_field "$rows" "$id" 3)
if [ "$role" = founder ]; then
  echo "ERROR: the agents' GH_TOKEN belongs to founder '$login'. Use the agents' own account's token (see docs/runbooks/agent-network-lock.md) in the AGENT_GH_TOKEN secret."
  exit 1
fi
[ "$role" = agent ] || { echo "ERROR: the agents' GH_TOKEN belongs to '$login' (ID $id), which is not an agent account in $ACCOUNTS."; exit 1; }
scopes=$("$GH" api -i user 2>/dev/null | tr -d '\r' | sed -n 's/^[Xx]-[Oo][Aa][Uu][Tt][Hh]-[Ss][Cc][Oo][Pp][Ee][Ss]:[[:space:]]*//p' | head -n1 || true)
if [ "$kind" = fine-grained ]; then
  [ -z "$scopes" ] || { echo "ERROR: GH_TOKEN carries classic OAuth scopes ($scopes); use a fine-grained token limited to this repository."; exit 1; }
else
  [ "$(tr -d ' ' <<<"$scopes")" = repo ] || { echo "ERROR: the classic GH_TOKEN must have exactly the scope 'repo' (has: '${scopes:-none}'); no workflow, admin or other scopes."; exit 1; }
fi
# The agents' account must own nothing: a repository of its own (a fork included) would be a place to push code or data out.
owned=$("$GH" api 'user/repos?type=owner&per_page=100' --jq '[.[].full_name] | join(", ")' 2>/dev/null) || { echo "ERROR: could not list the agent account's own repositories."; exit 1; }
[ -z "$owned" ] || { echo "ERROR: the agents' account '$login' owns repositories ($owned); it must own none. A founder checks what was pushed there, deletes them and revokes the token if anything of ours left the repository."; exit 1; }
echo "Agent token OK: $kind, runs as agent account '$login', owns no repositories"
