#!/usr/bin/env bash
# Tests scripts/check-agent-token.sh with a stubbed gh (no network, no real token).
set -uo pipefail
SCRIPT="$(cd "$(dirname "$0")" && pwd)/check-agent-token.sh"
TMPROOT="${TMPDIR:-/tmp}"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-testlib.sh"
T=$(mktemp -d "$TMPROOT/at.XXXXXX") || exit 2; trap 'rm -rf "$T"' EXIT
printf '# accounts\n111 Founder-One founder\n  222 founder-two founder  # second\n333 agents-bot agent\n' > "$T/accounts"
write_gh_stub "$T"; cat > "$T/gh-extra" <<'EXTRA'
case "$*" in
  'api -i user') printf 'HTTP/2.0 200 OK\r\n'; [ -n "${STUB_SCOPES:-}" ] && printf '%s: %s\r\n' "${STUB_HDR:-X-Oauth-Scopes}" "$STUB_SCOPES"; printf '\r\n{}\n'; exit 0;;
  'api user/repos?type=owner&per_page=100 --jq [.[].full_name] | join(", ")') printf '%s\n' "${STUB_OWNED:-}"; exit "${STUB_OWNED_RC:-0}";;
  'api repos/owner/repo/actions/workflows/'*'.yml --jq .state')
    w=${2##*/}; [ "$w" = "${STUB_DISABLED:-}" ] && echo disabled_manually && exit 0; [ "${STUB_STATE_RC:-0}" = 0 ] && echo active; exit "${STUB_STATE_RC:-0}";;
esac
EXTRA
FG=github_pat_test_not_a_real_token; CL=ghp_classic_test_not_real
expect() { # expect <ok|fail> <name> <message> [env...]
  local want=$1 name=$2 msg=$3; shift 3
  echo 0 > "$T/count"
  out=$(env -u GITHUB_ACTIONS GH_BIN="$T/gh" GH_TOKEN="$FG" ACC="$T/accounts" GH_REPO=owner/repo STUB_COUNT="$T/count" AGENT_TOKEN_WAIT=10 "$@" bash -c 'bash "$0" "$ACC"' "$SCRIPT" 2>&1); rc=$?
  assert_result "$want" "$rc" "$name" "$msg" "$out"
  assert_no_token "$name" "$out" "$FG" "$CL" gho_oauth_test; }
expect ok   "agents' fine-grained token"       "Agent token OK: fine-grained, runs as agent account 'agents-bot', owns no repositories; guard workflows active, main head: ok cccc" "STUB_WHO=333 agents-bot"
expect ok   "agents' classic token, only repo" "Agent token OK: classic, runs as agent account 'agents-bot', owns no repositories" "STUB_WHO=333 agents-bot" GH_TOKEN=$CL STUB_SCOPES=repo
expect ok   "lower-case scopes header"         "Agent token OK: classic" "STUB_WHO=333 agents-bot" GH_TOKEN=$CL STUB_SCOPES=repo STUB_HDR=x-oauth-scopes
expect fail "a founder's token (by ID)"        "belongs to founder 'new-name'" "STUB_WHO=222 new-name"
expect fail "a founder's token, classic"       "belongs to founder 'founder-two'" "STUB_WHO=222 founder-two" GH_TOKEN=$CL STUB_SCOPES=repo
expect fail "a founder's login on another ID"  "belongs to 'founder-one' (ID 999), which is not an agent account" "STUB_WHO=999 founder-one"
expect fail "an unknown account"               "which is not an agent account" "STUB_WHO=444 someone"
expect fail "classic token with workflow"      "must have exactly the scope 'repo' (has: 'repo, workflow')" "STUB_WHO=333 agents-bot" GH_TOKEN=$CL "STUB_SCOPES=repo, workflow"
expect fail "classic token with no scopes"     "must have exactly the scope 'repo' (has: 'none')" "STUB_WHO=333 agents-bot" GH_TOKEN=$CL
expect fail "classic token with gist"          "has: 'repo, gist'" "STUB_WHO=333 agents-bot" GH_TOKEN=$CL "STUB_SCOPES=repo, gist"
expect fail "fine-grained token with scopes"   "carries classic OAuth scopes (repo)" "STUB_WHO=333 agents-bot" STUB_SCOPES=repo
expect fail "another token kind"               "is not a fine-grained (github_pat_...) or classic (ghp_...) token" "STUB_WHO=333 agents-bot" GH_TOKEN=gho_oauth_test
expect fail "no token"                         "is not a fine-grained" "STUB_WHO=333 agents-bot" GH_TOKEN=
expect fail "the agent account owns a repo"    "owns repositories (agents-bot/dealer-platform); it must own none" "STUB_WHO=333 agents-bot" GH_TOKEN=$CL STUB_SCOPES=repo STUB_OWNED=agents-bot/dealer-platform
# The guard workflows must be active and the default branch's head must have passed the main guard
OK="STUB_WHO=333 agents-bot"
expect fail "main-guard disabled"              "workflow main-guard.yml is 'disabled_manually', not active" "$OK" STUB_DISABLED=main-guard.yml
expect fail "pusher ledger disabled"           "workflow pusher-ledger.yml is 'disabled_manually', not active" "$OK" STUB_DISABLED=pusher-ledger.yml
expect fail "guards disabled"                  "workflow guards.yml is 'disabled_manually'" "$OK" STUB_DISABLED=guards.yml
expect fail "review disabled"                  "workflow review.yml is 'disabled_manually'" "$OK" STUB_DISABLED=review.yml
expect fail "workflow state unreadable"        "could not read the state of workflow main-guard.yml" "$OK" STUB_STATE_RC=1
expect fail "head unreadable"                  "could not read the default branch's head commit" "$OK" STUB_HEAD_RC=1
expect fail "odd head text"                    "could not read the default branch's head commit" "$OK" "STUB_HEAD=not a sha"
expect fail "main-guard runs unreadable"       "could not list the main-guard runs" "$OK" STUB_RUNS_RC=1
expect fail "main-guard run cancelled"         "has no successful main-guard run (missing cccccccccccccccccccccccccccccccccccccccc (runs: completed/cancelled))" "$OK" STUB_RUNS=completed/cancelled
expect fail "main-guard run failed"            "has no successful main-guard run (missing cccccccccccccccccccccccccccccccccccccccc (runs: completed/failure))" "$OK" STUB_RUNS=completed/failure
expect fail "no main-guard run at all"         "has no successful main-guard run (missing cccccccccccccccccccccccccccccccccccccccc (runs: none))" "$OK" STUB_RUNS=
expect ok   "a later success among older runs" "main head: ok" "$OK" "STUB_RUNS=completed/failure completed/success"
expect ok   "run in progress, then success"    "main head: ok" "$OK" STUB_RUNS=in_progress/ STUB_RUNS_LATER=completed/success
expect fail "run still queued after the wait"  "has not finished after 10s; re-run this job later" "$OK" STUB_RUNS=queued/
expect ok   "a head older than the main guard's floor passes (compare: ahead)" "main head: ok cccc" "$OK" STUB_RUNS= STUB_REL=ahead
expect ok   "the floor commit itself (compare: identical)" "main head: ok cccc" "$OK" STUB_RUNS= STUB_REL=identical
expect fail "a head after the floor with no run (a skip-ci push)" "has no successful main-guard run (missing cccccccccccccccccccccccccccccccccccccccc (runs: none))" "$OK" STUB_RUNS= STUB_REL=behind
expect fail "a head on another line of history (compare: diverged)" "missing cccc" "$OK" STUB_RUNS= STUB_REL=diverged
expect fail "the compare call fails"             "could not compare cccc" "$OK" STUB_RUNS= STUB_REL_RC=1
check "the compare is against the floor constant of check-github-lib.sh" bash -c 'grep -q "^MAIN_GUARD_FLOOR=596905e54f7ae8385c90f6d334db5f18a4427e28$" "$1"' _ "$(dirname "$SCRIPT")/check-github-lib.sh"
expect ok   "GITHUB_REPOSITORY as the fallback"  "main head: ok" "$OK" GH_REPO= GITHUB_REPOSITORY=owner/repo
expect fail "no repository name"               "GH_REPO or GITHUB_REPOSITORY (owner/repo) is not set" "$OK" GH_REPO= GITHUB_REPOSITORY=
expect fail "bad GH_REPO"                      "bad GH_REPO" "$OK" "GH_REPO=owner/re po"
# Inside GitHub Actions the environment overrides are ignored (a Claude step before could have written $GITHUB_ENV):
# gh comes from PATH, the repository from GITHUB_REPOSITORY, the workflow list and the wait are fixed.
mkdir -p "$T/path"; cp "$T/gh" "$T/gh-extra" "$T/path/"
expect ok   "in Actions: gh from PATH, repo from GITHUB_REPOSITORY" "main head: ok" "$OK" GITHUB_ACTIONS=true GITHUB_REPOSITORY=owner/repo GH_REPO=other/repo "PATH=$T/path:$PATH"
expect fail "in Actions: GH_BIN is ignored (a stub there does not count)" "could not read the token's GitHub login" "$OK" GITHUB_ACTIONS=true GITHUB_REPOSITORY=owner/repo "PATH=$T/nowhere:/usr/bin:/bin"
expect fail "in Actions: GUARD_WORKFLOWS cannot drop a workflow" "workflow main-guard.yml is 'disabled_manually'" "$OK" GITHUB_ACTIONS=true GITHUB_REPOSITORY=owner/repo "PATH=$T/path:$PATH" GUARD_WORKFLOWS=review.yml STUB_DISABLED=main-guard.yml
expect fail "in Actions: no GITHUB_REPOSITORY is an error even with GH_REPO" "GH_REPO or GITHUB_REPOSITORY (owner/repo) is not set" "$OK" GITHUB_ACTIONS=true GITHUB_REPOSITORY= "PATH=$T/path:$PATH"
expect fail "repo list unavailable"            "could not list the agent account's own repositories" "STUB_WHO=333 agents-bot" GH_TOKEN=$CL STUB_SCOPES=repo STUB_OWNED_RC=1
expect fail "gh fails"                         "could not read the token's GitHub login" STUB_WHO= STUB_RC=1
expect fail "odd login text"                   "could not read the token's GitHub login" "STUB_WHO=333 x;y"
expect fail "missing ID"                       "could not read the token's GitHub login" "STUB_WHO=abc agents-bot"
# A broken accounts file stops the job before anything else (fail closed)
printf '333 agents-bot agent\n' > "$T/bad"; expect fail "no founder listed" "no founder listed" "STUB_WHO=333 agents-bot" ACC="$T/bad"
printf '111 founder-one\n' > "$T/bad"; expect fail "a login-only line" "bad line 1" "STUB_WHO=111 founder-one" ACC="$T/bad"
printf '111 founder-one founder\n333 agents-bot agent' > "$T/bad"; expect fail "last line without a newline still read" "belongs to founder" "STUB_WHO=111 founder-one" ACC="$T/bad"
expect fail "missing accounts file" "accounts file not found" "STUB_WHO=333 agents-bot" ACC="$T/nope"
# The real file names the agents' account
REAL="$(cd "$(dirname "$SCRIPT")/.." && pwd)/.github/accounts.txt"
expect ok   "the real accounts file accepts the agents' account" "runs as agent account" "STUB_WHO=$(awk '$3=="agent"{print $1" "$2; exit}' "$REAL")" ACC="$REAL"
summary
