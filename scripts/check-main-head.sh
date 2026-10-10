#!/usr/bin/env bash
# Before the network lock and the Claude step of every Claude job (founder-owned): the commit this job checked out must
# be the default branch's head as GitHub sees it, and that head must have passed the main guard. A push to the default
# branch whose head commit says [skip ci] starts no main-guard run, and a cancelled run passed nothing; this stops such a
# job before any secret is used (main_guard_passed, scripts/check-github-lib.sh). Needs gh with a token that can read
# Actions runs (the job token with actions: read, or the agents' token).
# Usage: scripts/check-main-head.sh      Env (tests only, outside Actions): GH_BIN, GH_REPO, MAIN_HEAD_WAIT (default 120).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/check-accounts-lib.sh
. "$HERE/check-accounts-lib.sh"
# shellcheck source=scripts/check-github-lib.sh
. "$HERE/check-github-lib.sh"
gh_context || exit 1
if [ -n "${GITHUB_ACTIONS:-}" ]; then WAIT=120; else WAIT="${MAIN_HEAD_WAIT:-120}"; fi
local_sha=$(git rev-parse HEAD 2>/dev/null) || { echo "ERROR: not in the checkout of the default branch (git rev-parse HEAD failed)"; exit 1; }
out=$(main_head_passed "$WAIT" "any Claude job runs" "$local_sha") || { echo "$out"; exit 1; }
echo "Main head OK: $out"
