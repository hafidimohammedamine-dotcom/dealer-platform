#!/usr/bin/env bash
# Tests scripts/check-agent-token.sh with a stubbed gh (no network, no real token).
set -uo pipefail
SCRIPT="$(cd "$(dirname "$0")" && pwd)/check-agent-token.sh"
TMPROOT="${TMPDIR:-/tmp}"
pass=0; failed=0
T=$(mktemp -d "$TMPROOT/at.XXXXXX") || exit 2; trap 'rm -rf "$T"' EXIT
printf '# accounts\n111 Founder-One founder\n  222 founder-two founder  # second\n333 agents-bot agent\n' > "$T/accounts"
cat > "$T/gh" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  'api user --jq "\(.id) \(.login)"') printf '%s\n' "$STUB_WHO"; exit "${STUB_RC:-0}";;
  'api -i user') printf 'HTTP/2.0 200 OK\r\n'; [ -n "${STUB_SCOPES:-}" ] && printf '%s: %s\r\n' "${STUB_HDR:-X-Oauth-Scopes}" "$STUB_SCOPES"; printf '\r\n{}\n';;
  *) exit 9;;
esac
STUB
chmod +x "$T/gh"
FG=github_pat_test_not_a_real_token; CL=ghp_classic_test_not_real
expect() { # expect <ok|fail> <name> <message> [env...]
  local want=$1 name=$2 msg=$3; shift 3
  out=$(env GH_BIN="$T/gh" GH_TOKEN="$FG" ACC="$T/accounts" "$@" bash -c 'bash "$0" "$ACC"' "$SCRIPT" 2>&1); rc=$?; got=$([ $rc = 0 ] && echo ok || echo fail)
  if [ "$got" = "$want" ] && grep -qF -- "$msg" <<<"$out" && ! grep -qe "$FG" -e "$CL" -e gho_oauth_test <<<"$out"; then pass=$((pass+1)); echo "PASS  $name"
  else failed=$((failed+1)); echo "FAIL  $name ($got)"; echo "$out"; fi; }
expect ok   "agents' fine-grained token"       "Agent token OK: fine-grained, runs as agent account 'agents-bot'" "STUB_WHO=333 agents-bot"
expect ok   "agents' classic token, only repo" "Agent token OK: classic, runs as agent account 'agents-bot'" "STUB_WHO=333 agents-bot" GH_TOKEN=$CL STUB_SCOPES=repo
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
echo "$pass passed, $failed failed"
[ "$failed" = 0 ]
