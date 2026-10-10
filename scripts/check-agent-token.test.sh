#!/usr/bin/env bash
# Tests scripts/check-agent-token.sh with a stubbed gh (no network, no real token).
set -uo pipefail
SCRIPT="$(cd "$(dirname "$0")" && pwd)/check-agent-token.sh"
TMPROOT="${TMPDIR:-/tmp}"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-testlib.sh"
T=$(mktemp -d "$TMPROOT/at.XXXXXX") || exit 2; trap 'rm -rf "$T"' EXIT
printf '# accounts\n111 Founder-One founder\n  222 founder-two founder  # second\n333 agents-bot agent\n' > "$T/accounts"
cat > "$T/gh" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  'api user --jq "\(.id) \(.login)"') printf '%s\n' "$STUB_WHO"; exit "${STUB_RC:-0}";;
  'api -i user') printf 'HTTP/2.0 200 OK\r\n'; [ -n "${STUB_SCOPES:-}" ] && printf '%s: %s\r\n' "${STUB_HDR:-X-Oauth-Scopes}" "$STUB_SCOPES"; printf '\r\n{}\n';;
  'api user/repos?type=owner&per_page=100 --jq [.[].full_name] | join(", ")') printf '%s\n' "${STUB_OWNED:-}"; exit "${STUB_OWNED_RC:-0}";;
  'api repos/owner/repo/actions/workflows/'*'.yml --jq .state')
    w=${2##*/}; [ "$w" = "${STUB_DISABLED:-}" ] && echo disabled_manually && exit 0; [ "${STUB_STATE_RC:-0}" = 0 ] && echo active; exit "${STUB_STATE_RC:-0}";;
  'api repos/owner/repo/commits/HEAD --jq .sha') printf '%s\n' "${STUB_HEAD:-$(printf 'c%.0s' {1..40})}"; exit "${STUB_HEAD_RC:-0}";;
  'api repos/owner/repo/actions/workflows/main-guard.yml/runs?head_sha='*)
    [ "${STUB_RUNS_RC:-0}" = 0 ] || exit 1; n=$(cat "$STUB_COUNT" 2>/dev/null || echo 0); echo $((n+1)) > "$STUB_COUNT"
    if [ -n "${STUB_RUNS_LATER:-}" ] && [ "$n" -ge 1 ]; then printf '%s\n' "$STUB_RUNS_LATER"; else printf '%s\n' "${STUB_RUNS-completed/success}"; fi;;
  *) exit 9;;
esac
STUB
chmod +x "$T/gh"
FG=github_pat_test_not_a_real_token; CL=ghp_classic_test_not_real
expect() { # expect <ok|fail> <name> <message> [env...]
  local want=$1 name=$2 msg=$3; shift 3
  echo 0 > "$T/count"
  out=$(env GH_BIN="$T/gh" GH_TOKEN="$FG" ACC="$T/accounts" GH_REPO=owner/repo STUB_COUNT="$T/count" AGENT_TOKEN_WAIT=10 "$@" bash -c 'bash "$0" "$ACC"' "$SCRIPT" 2>&1); rc=$?
  assert_result "$want" "$rc" "$name" "$msg" "$out"
  check "no token in the output of: $name" bash -c '! grep -qe "$1" -e "$2" -e gho_oauth_test <<<"$3"' _ "$FG" "$CL" "$out"; }
expect ok   "agents' fine-grained token"       "Agent token OK: fine-grained, runs as agent account 'agents-bot', owns no repositories; guard workflows active, main-guard passed on cccc" "STUB_WHO=333 agents-bot"
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
expect fail "main-guard run cancelled"         "has no successful main-guard run (runs: completed/cancelled)" "$OK" STUB_RUNS=completed/cancelled
expect fail "main-guard run failed"            "has no successful main-guard run (runs: completed/failure)" "$OK" STUB_RUNS=completed/failure
expect fail "no main-guard run at all"         "has no successful main-guard run (runs: none)" "$OK" STUB_RUNS=
expect ok   "a later success among older runs" "main-guard passed" "$OK" "STUB_RUNS=completed/failure completed/success"
expect ok   "run in progress, then success"    "main-guard passed" "$OK" STUB_RUNS=in_progress/ STUB_RUNS_LATER=completed/success
expect fail "run still queued after the wait"  "has not finished after 10s; re-run this job later" "$OK" STUB_RUNS=queued/
expect ok   "GITHUB_REPOSITORY as the fallback"  "main-guard passed" "$OK" GH_REPO= GITHUB_REPOSITORY=owner/repo
expect fail "no repository name"               "GH_REPO or GITHUB_REPOSITORY (owner/repo) is not set" "$OK" GH_REPO= GITHUB_REPOSITORY=
expect fail "bad GH_REPO"                      "bad GH_REPO" "$OK" "GH_REPO=owner/re po"
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
