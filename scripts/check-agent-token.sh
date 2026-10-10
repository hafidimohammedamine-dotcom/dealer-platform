#!/usr/bin/env bash
# Fails unless the GitHub token the agents run with (GH_TOKEN) belongs to the agents' own account and is limited
# (founder-owned). Run before Claude in every job that holds AGENT_GH_TOKEN_V2 (scripts/check-workflows.sh enforces that).
#  - The token's user ID must be an `agent` row of .github/accounts.txt (IDs, not logins: a login can be re-registered),
#    so a founder's token, or anyone else's, stops the job: with a founder's token an agent's pushes look like a founder's.
#  - The token must be fine-grained (github_pat_..., no classic scopes) or classic (ghp_...) with exactly the scope `repo`:
#    no `workflow` (it cannot change .github/workflows), no admin, gist or other scopes. Fine-grained tokens cannot cover
#    a personal account's repository for a collaborator, so the agents' account uses a classic `repo` token until the
#    repository moves to an organization.
#  - The guard workflows must be active and the default branch's head must have passed the main guard: the agents' token
#    (classic `repo` covers the Actions API) could disable `main-guard.yml` or cancel its run and then push to the default
#    branch; this check, run at the start and end of every shift, turns that into a stopped shift and a visible failure.
# Usage: scripts/check-agent-token.sh <accounts-file>     The token is never printed.
# Outside GitHub Actions (tests) the environment may override: GH_BIN (a stub gh), GH_REPO (owner/repo), GUARD_WORKFLOWS,
# AGENT_TOKEN_WAIT (seconds to wait for a main-guard run still in progress). Inside Actions (GITHUB_ACTIONS set) none of
# these is read - a Claude step that ran before could have written $GITHUB_ENV - and the repository is GITHUB_REPOSITORY
# (gh_context and the other helpers in scripts/check-accounts-lib.sh).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/check-accounts-lib.sh
. "$HERE/check-accounts-lib.sh"
ACCOUNTS="${1:?accounts file}"
GUARD_WFS="main-guard.yml pusher-ledger.yml guards.yml review.yml"
gh_context || exit 1
if [ -n "${GITHUB_ACTIONS:-}" ]; then WFS="$GUARD_WFS"; WAIT=120
else WFS="${GUARD_WORKFLOWS:-$GUARD_WFS}"; WAIT="${AGENT_TOKEN_WAIT:-120}"; fi
rows=$(accounts_rows "$ACCOUNTS") || { echo "$rows"; exit 1; }
case "${GH_TOKEN:-}" in
  github_pat_*) kind=fine-grained;;
  ghp_*) kind=classic;;
  *) echo "ERROR: GH_TOKEN is not a fine-grained (github_pat_...) or classic (ghp_...) token. Use the agents' own token (see docs/runbooks/agent-network-lock.md)."; exit 1;;
esac
token_account "$rows" || exit 1
id=$TOKEN_ID; login=$TOKEN_LOGIN; role=$TOKEN_ROLE
if [ "$role" = founder ]; then
  echo "ERROR: the agents' GH_TOKEN belongs to founder '$login'. Use the agents' own account's token (see docs/runbooks/agent-network-lock.md) in the AGENT_GH_TOKEN_V2 secret."
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
# The guard workflows are enabled, and the default branch's head passed the main guard (a non-founder push with the
# workflow disabled, its run cancelled or its head commit saying [skip ci] would otherwise go unnoticed until the next
# founder look).
for w in $WFS; do
  state=$("$GH" api "repos/$REPO/actions/workflows/$w" --jq .state 2>/dev/null) || { echo "ERROR: could not read the state of workflow $w."; exit 1; }
  [ "$state" = active ] || { echo "ERROR: workflow $w is '$state', not active. A founder checks who disabled it (the repository's audit log) and re-enables it; agents must not run until then."; exit 1; }
done
head=$("$GH" api "repos/$REPO/commits/HEAD" --jq .sha 2>/dev/null) || { echo "ERROR: could not read the default branch's head commit."; exit 1; }
[[ "$head" =~ ^[0-9a-f]{40}$ ]] || { echo "ERROR: could not read the default branch's head commit."; exit 1; }
if ! out=$(main_guard_passed "$head" "$WAIT"); then
  case "$out" in ERROR:*) echo "$out";; *) echo "ERROR: the default branch's head ($head) has no successful main-guard run ($out). A founder checks that push (was the run cancelled, the workflow disabled, or the commit message marked [skip ci]?) before any agent runs.";; esac
  exit 1
fi
echo "Agent token OK: $kind, runs as agent account '$login', owns no repositories; guard workflows active, main-guard passed on $head"
