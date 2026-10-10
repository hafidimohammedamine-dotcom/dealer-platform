#!/usr/bin/env bash
# Before the network lock and the Claude step of every Claude job (founder-owned): the default branch's head, which this
# job just checked out and is about to run next to a Claude token, must have passed the main guard. A push to the default
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
head=$("$GH" api "repos/$REPO/commits/HEAD" --jq .sha 2>/dev/null) || { echo "ERROR: could not read the default branch's head commit."; exit 1; }
[[ "$head" =~ ^[0-9a-f]{40}$ ]] || { echo "ERROR: could not read the default branch's head commit."; exit 1; }
if ! out=$(main_guard_passed "$head" "$WAIT"); then
  case "$out" in ERROR:*) echo "$out";; *) echo "ERROR: the default branch's head ($head) has no successful main-guard run ($out). A founder checks that push (was the run cancelled, the workflow disabled, or the commit message marked [skip ci]?) before any Claude job runs.";; esac
  exit 1
fi
echo "Main head OK: $out"
