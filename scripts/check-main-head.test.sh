#!/usr/bin/env bash
# Tests scripts/check-main-head.sh with a stubbed gh (no network).
set -uo pipefail
SCRIPT="$(cd "$(dirname "$0")" && pwd)/check-main-head.sh"
TMPROOT="${TMPDIR:-/tmp}"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-testlib.sh"
T=$(mktemp -d "$TMPROOT/mh.XXXXXX") || exit 2; trap 'rm -rf "$T"' EXIT
write_gh_stub "$T"; mkdir -p "$T/path"; cp "$T/gh" "$T/path/gh"
# The job's checkout: a throwaway repository whose HEAD the stub reports as main's head (unless a case says otherwise)
git init -q -b main "$T/r" && git -C "$T/r" -c user.email=t@t -c user.name=t commit -q --allow-empty -m main; H=$(git -C "$T/r" rev-parse HEAD)
expect() { # expect <ok|fail> <name> <message> [env...]
  local want=$1 name=$2 msg=$3; shift 3
  out=$(cd "$T/r" && env -u GITHUB_ACTIONS -u GITHUB_REPOSITORY GH_BIN="$T/gh" GH_TOKEN=ghp_test_not_real GH_REPO=owner/repo MAIN_HEAD_WAIT=10 STUB_HEAD="$H" "$@" bash "$SCRIPT" 2>&1); rc=$?
  assert_result "$want" "$rc" "$name" "$msg" "$out"
  assert_no_token "$name" "$out" ghp_test_not_real; }
expect ok   "main's head passed the main guard"         "Main head OK: ok $H passed the main guard"
expect fail "main's head has no run (a skip-ci push)"   "has no successful main-guard run (missing $H (runs: none))" STUB_RUNS=
expect fail "main's head's run was cancelled"           "missing $H (runs: completed/cancelled)" STUB_RUNS=completed/cancelled
expect ok   "a head older than the floor"            "is on the default branch before the main guard existed" STUB_RUNS= STUB_REL=ahead
expect fail "a run still going after the wait"          "has not finished after 10s" STUB_RUNS=in_progress/
expect fail "the runs cannot be listed"                 "could not list the main-guard runs" STUB_RUNS_RC=1
expect fail "the head cannot be read"                   "could not read the default branch's head commit" STUB_HEAD_RC=1
expect fail "odd head text"                             "could not read the default branch's head commit" "STUB_HEAD=not a sha"
expect fail "main moved since the checkout"            "this job checked out $H but the default branch's head is $(printf 'd%.0s' {1..40}) now; start a fresh run" "STUB_HEAD=$(printf 'd%.0s' {1..40})"
out=$(cd "$T" && env -u GITHUB_ACTIONS GH_BIN="$T/gh" GH_TOKEN=ghp_test_not_real GH_REPO=owner/repo bash "$SCRIPT" 2>&1); rc=$?
assert_result fail "$rc" "outside a git checkout it fails" "not in the checkout of the default branch" "$out"
expect fail "no repository"                             "GH_REPO or GITHUB_REPOSITORY (owner/repo) is not set" GH_REPO=
expect ok   "in Actions: gh from PATH, repo from GITHUB_REPOSITORY, the wait fixed" "Main head OK" GITHUB_ACTIONS=true GITHUB_REPOSITORY=owner/repo GH_REPO=other/x "PATH=$T/path:$PATH" MAIN_HEAD_WAIT=0
summary
