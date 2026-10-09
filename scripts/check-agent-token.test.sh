#!/usr/bin/env bash
# Tests scripts/check-agent-token.sh with a stubbed gh (no network, no real token).
set -uo pipefail
SCRIPT="$(cd "$(dirname "$0")" && pwd)/check-agent-token.sh"
TMPROOT="${TMPDIR:-/tmp}"
pass=0; failed=0
T=$(mktemp -d "$TMPROOT/at.XXXXXX") || exit 2; trap 'rm -rf "$T"' EXIT
printf '# founders\n111 Founder-One\n  222 founder-two  # second\n\n' > "$T/founders"
cat > "$T/gh" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  'api user --jq "\(.id) \(.login)"') printf '%s\n' "$STUB_WHO"; exit "${STUB_RC:-0}";;
  'api -i user') printf 'HTTP/2.0 200 OK\r\n'; [ -n "${STUB_SCOPES:-}" ] && printf 'X-Oauth-Scopes: %s\r\n' "$STUB_SCOPES"; printf '\r\n{}\n';;
  *) exit 9;;
esac
STUB
chmod +x "$T/gh"
FG=github_pat_test_not_a_real_token
expect() { # expect <ok|fail> <name> <message> [env...]
  local want=$1 name=$2 msg=$3; shift 3
  out=$(env GH_BIN="$T/gh" GH_TOKEN="$FG" "$@" bash "$SCRIPT" "$T/founders" 2>&1); rc=$?; got=$([ $rc = 0 ] && echo ok || echo fail)
  if [ "$got" = "$want" ] && grep -qF -- "$msg" <<<"$out" && ! grep -qe "$FG" -e ghp_classic_test -e gho_oauth_test <<<"$out"; then pass=$((pass+1)); echo "PASS  $name"
  else failed=$((failed+1)); echo "FAIL  $name ($got)"; echo "$out"; fi; }
expect ok   "agents' own fine-grained token"   "Agent token OK: fine-grained, runs as 'agents-bot'" "STUB_WHO=333 agents-bot"
expect fail "a founder's token (by login)"     "belongs to founder 'founder-two'" "STUB_WHO=999 founder-two"
expect fail "a founder's token, other case"    "belongs to founder 'founder-one'" "STUB_WHO=998 founder-one"
expect fail "a renamed founder (by ID)"        "belongs to founder 'new-name'" "STUB_WHO=222 new-name"
expect ok   "classic token with exactly repo"  "Agent token OK: classic, runs as 'agents-bot'" "STUB_WHO=333 agents-bot" GH_TOKEN=ghp_classic_test STUB_SCOPES=repo
expect fail "classic token with workflow"      "must have exactly the scope 'repo' (has: 'repo, workflow')" "STUB_WHO=333 agents-bot" GH_TOKEN=ghp_classic_test "STUB_SCOPES=repo, workflow"
expect fail "classic token with no scopes"     "must have exactly the scope 'repo' (has: 'none')" "STUB_WHO=333 agents-bot" GH_TOKEN=ghp_classic_test
expect fail "classic token with gist"          "has: 'repo, gist'" "STUB_WHO=333 agents-bot" GH_TOKEN=ghp_classic_test "STUB_SCOPES=repo, gist"
expect fail "a founder's classic token"        "belongs to founder 'founder-two'" "STUB_WHO=222 founder-two" GH_TOKEN=ghp_classic_test STUB_SCOPES=repo
expect fail "another token kind"               "is not a fine-grained (github_pat_...) or classic (ghp_...) token" "STUB_WHO=333 agents-bot" GH_TOKEN=gho_oauth_test
expect fail "no token"                         "is not a fine-grained" "STUB_WHO=333 agents-bot" GH_TOKEN=
expect fail "classic OAuth scopes"             "carries classic OAuth scopes (repo, workflow)" "STUB_WHO=333 agents-bot" "STUB_SCOPES=repo, workflow"
expect fail "gh fails"                         "could not read the token's GitHub login" STUB_WHO= STUB_RC=1
expect fail "odd login text"                   "could not read the token's GitHub login" "STUB_WHO=333 x;y"
expect fail "missing ID"                       "could not read the token's GitHub login" "STUB_WHO=abc agents-bot"
out=$(GH_BIN="$T/gh" GH_TOKEN="$FG" STUB_WHO="1 a" bash "$SCRIPT" "$T/nope" 2>&1); [ $? != 0 ] && grep -q "founders file not found" <<<"$out" && { pass=$((pass+1)); echo "PASS  missing founders file"; } || { failed=$((failed+1)); echo "FAIL  missing founders file"; }
echo "$pass passed, $failed failed"
[ "$failed" = 0 ]
