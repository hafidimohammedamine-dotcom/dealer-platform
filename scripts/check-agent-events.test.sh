#!/usr/bin/env bash
# Tests scripts/check-agent-events.sh with a stubbed gh (no network, no real token).
set -uo pipefail
SCRIPT="$(cd "$(dirname "$0")" && pwd)/check-agent-events.sh"
TMPROOT="${TMPDIR:-/tmp}"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-testlib.sh"
T=$(mktemp -d "$TMPROOT/ae.XXXXXX") || exit 2; trap 'rm -rf "$T"' EXIT
printf '111 founder-one founder\n333 agents-bot agent\n' > "$T/accounts"
cat > "$T/gh" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  'api user --jq "\(.id) \(.login)"') printf '%s\n' "${STUB_WHO-333 agents-bot}"; exit "${STUB_RC:-0}";;
  'api --paginate users/agents-bot/events?per_page=100 --jq '*) [ "${STUB_EVENTS_RC:-0}" = 0 ] || exit 1; printf '%b' "${STUB_EVENTS:-}";;
  *) exit 9;;
esac
STUB
chmod +x "$T/gh"
expect() { # expect <ok|fail> <name> <message> [env...]
  local want=$1 name=$2 msg=$3; shift 3
  out=$(env -u GITHUB_ACTIONS GH_BIN="$T/gh" GH_TOKEN=ghp_test_not_real GH_REPO=owner/repo ACC="$T/accounts" "$@" bash -c 'bash "$0" "$ACC" "${SINCE:-2026-10-10T05:00:00Z}"' "$SCRIPT" 2>&1); rc=$?
  assert_result "$want" "$rc" "$name" "$msg" "$out"
  check "no token in the output of: $name" bash -c '! grep -q ghp_test_not_real <<<"$1"' _ "$out"; }
IN='2026-10-10T05:30:00Z PushEvent owner/repo\n2026-10-10T06:10:00Z IssueCommentEvent owner/repo\n'
expect ok   "events only in this repository"           "Agent events OK: 2 event(s) by 'agents-bot' since 2026-10-10T05:00:00Z, all in owner/repo" "STUB_EVENTS=$IN"
expect ok   "no events at all"                          "Agent events OK: 0 event(s)" STUB_EVENTS=
expect ok   "older events are not counted"              "Agent events OK: 1 event(s)" "STUB_EVENTS=2026-10-10T04:59:59Z IssueCommentEvent other/repo\n2026-10-10T05:30:00Z PushEvent owner/repo\n"
expect ok   "an event exactly at 'since' counts"        "Agent events OK: 1 event(s)" "STUB_EVENTS=2026-10-10T05:00:00Z PushEvent owner/repo\n"
expect fail "a comment in another repository"           "acted outside owner/repo since 2026-10-10T05:00:00Z:" "STUB_EVENTS=${IN}2026-10-10T06:20:00Z IssueCommentEvent attacker/inbox\n"
expect fail "the offending event is listed"             "2026-10-10T06:20:00Z IssueCommentEvent attacker/inbox" "STUB_EVENTS=${IN}2026-10-10T06:20:00Z IssueCommentEvent attacker/inbox\n"
expect fail "an issue opened elsewhere"                 "rotates AGENT_GH_TOKEN_V2" "STUB_EVENTS=2026-10-10T06:20:00Z IssuesEvent someone/else\n"
expect fail "a fork or push elsewhere"                  "acted outside" "STUB_EVENTS=2026-10-10T06:20:00Z ForkEvent agents-bot/dealer-platform\n"
expect fail "events unreadable is an error"             "could not read the events of 'agents-bot'" STUB_EVENTS_RC=1
expect fail "a founder's token"                         "belongs to 'founder-one' (ID 111), which is not an agent account" "STUB_WHO=111 founder-one"
expect fail "gh fails"                                  "could not read the token's GitHub login" STUB_RC=1 STUB_WHO=
expect fail "bad since"                                 "since must be an ISO-8601 UTC time" SINCE=yesterday
expect fail "bad repository name"                       "bad GH_REPO" "GH_REPO=owner/re po"
expect fail "missing accounts file"                     "accounts file not found" ACC="$T/nope"
mkdir -p "$T/path"; cp "$T/gh" "$T/path/gh"
expect ok   "in Actions: gh from PATH, repo from GITHUB_REPOSITORY" "all in owner/repo" GITHUB_ACTIONS=true GITHUB_REPOSITORY=owner/repo GH_REPO=other/repo "PATH=$T/path:$PATH" "STUB_EVENTS=$IN"
expect fail "in Actions: GH_BIN is ignored"             "could not read the token's GitHub login" GITHUB_ACTIONS=true GITHUB_REPOSITORY=owner/repo "PATH=$T/nowhere:/usr/bin:/bin"
out=$(bash "$SCRIPT" "$T/accounts" 2>&1); rc=$?; [ $rc != 0 ] && grep -q "since" <<<"$out" && t PASS "usage without since" || t FAIL "usage ($rc)"
summary
