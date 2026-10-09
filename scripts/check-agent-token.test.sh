#!/usr/bin/env bash
# Tests scripts/check-agent-token.sh with a stubbed gh.
set -uo pipefail
SCRIPT="$(cd "$(dirname "$0")" && pwd)/check-agent-token.sh"
TMPROOT="${TMPDIR:-/tmp}"
pass=0; failed=0
T=$(mktemp -d "$TMPROOT/at.XXXXXX") || exit 2; trap 'rm -rf "$T"' EXIT
printf '# founders\nFounder-One\n  founder-two  # second\n' > "$T/founders"
printf '#!/usr/bin/env bash\n[ "$*" = "api user --jq .login" ] || exit 9\nprintf "%%s\\n" "$STUB_LOGIN"; exit "${STUB_RC:-0}"\n' > "$T/gh"; chmod +x "$T/gh"
expect() { # expect <ok|fail> <name> <message> [env...]
  local want=$1 name=$2 msg=$3; shift 3
  out=$(env GH_BIN="$T/gh" "$@" bash "$SCRIPT" "$T/founders" 2>&1); rc=$?; got=$([ $rc = 0 ] && echo ok || echo fail)
  if [ "$got" = "$want" ] && grep -qF -- "$msg" <<<"$out"; then pass=$((pass+1)); echo "PASS  $name"; else failed=$((failed+1)); echo "FAIL  $name ($got)"; echo "$out"; fi; }
expect ok   "agents' own account"            "Agent token OK: runs as 'agents-bot'" STUB_LOGIN=agents-bot
expect fail "a founder's token"              "belongs to founder 'founder-two'" STUB_LOGIN=founder-two
expect fail "a founder's token, other case"  "belongs to founder 'founder-one'" STUB_LOGIN=founder-one
expect fail "gh fails"                       "could not read the token's GitHub login" STUB_LOGIN= STUB_RC=1
expect fail "odd login text"                 "could not read the token's GitHub login" "STUB_LOGIN=x y"
out=$(GH_BIN="$T/gh" STUB_LOGIN=a bash "$SCRIPT" "$T/nope" 2>&1); [ $? != 0 ] && grep -q "founders file not found" <<<"$out" && { pass=$((pass+1)); echo "PASS  missing founders file"; } || { failed=$((failed+1)); echo "FAIL  missing founders file"; }
echo "$pass passed, $failed failed"
[ "$failed" = 0 ]
