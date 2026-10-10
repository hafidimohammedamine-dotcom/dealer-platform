#!/usr/bin/env bash
# Tests scripts/check-main-head.sh with a stubbed gh (no network).
set -uo pipefail
SCRIPT="$(cd "$(dirname "$0")" && pwd)/check-main-head.sh"
TMPROOT="${TMPDIR:-/tmp}"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-testlib.sh"
T=$(mktemp -d "$TMPROOT/mh.XXXXXX") || exit 2; trap 'rm -rf "$T"' EXIT
H=$(printf 'c%.0s' {1..40}); F=$(printf 'f%.0s' {1..40})
cat > "$T/gh" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  'api repos/owner/repo/commits/HEAD --jq .sha') printf '%s\n' "${STUB_HEAD-cccccccccccccccccccccccccccccccccccccccc}"; exit "${STUB_HEAD_RC:-0}";;
  'api repos/owner/repo/actions/workflows/main-guard.yml/runs?head_sha='*) [ "${STUB_RUNS_RC:-0}" = 0 ] || exit 1; printf '%s\n' "${STUB_RUNS-completed/success}";;
  'api repos/owner/repo/compare/'*' --jq .status') printf '%s\n' "${STUB_REL:-behind}";;
  *) exit 9;;
esac
STUB
chmod +x "$T/gh"; mkdir -p "$T/path"; cp "$T/gh" "$T/path/gh"
expect() { # expect <ok|fail> <name> <message> [env...]
  local want=$1 name=$2 msg=$3; shift 3
  out=$(env -u GITHUB_ACTIONS -u GITHUB_REPOSITORY GH_BIN="$T/gh" GH_TOKEN=ghp_test_not_real GH_REPO=owner/repo MAIN_HEAD_WAIT=10 "$@" bash "$SCRIPT" 2>&1); rc=$?
  assert_result "$want" "$rc" "$name" "$msg" "$out"
  check "no token in the output of: $name" bash -c '! grep -q ghp_test_not_real <<<"$1"' _ "$out"; }
expect ok   "main's head passed the main guard"         "Main head OK: ok $H passed the main guard"
expect fail "main's head has no run (a skip-ci push)"   "has no successful main-guard run (missing $H (runs: none))" STUB_RUNS=
expect fail "main's head's run was cancelled"           "missing $H (runs: completed/cancelled)" STUB_RUNS=completed/cancelled
expect ok   "a head older than the floor"            "is on the default branch before the main guard existed" STUB_RUNS= STUB_REL=ahead
expect fail "a run still going after the wait"          "has not finished after 10s" STUB_RUNS=in_progress/
expect fail "the runs cannot be listed"                 "could not list the main-guard runs" STUB_RUNS_RC=1
expect fail "the head cannot be read"                   "could not read the default branch's head commit" STUB_HEAD_RC=1
expect fail "odd head text"                             "could not read the default branch's head commit" "STUB_HEAD=not a sha"
expect fail "no repository"                             "GH_REPO or GITHUB_REPOSITORY (owner/repo) is not set" GH_REPO=
expect ok   "in Actions: gh from PATH, repo from GITHUB_REPOSITORY, the wait fixed" "Main head OK" GITHUB_ACTIONS=true GITHUB_REPOSITORY=owner/repo GH_REPO=other/x "PATH=$T/path:$PATH" MAIN_HEAD_WAIT=0
summary
