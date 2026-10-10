#!/usr/bin/env bash
# GitHub API helpers shared by the guards that run with a token (founder-owned): check-agent-token.sh,
# check-agent-events.sh, check-main-head.sh, check-main-push.sh and check-pushers.sh source this after
# check-accounts-lib.sh (token_account uses account_field). Nothing here prints a token. Pinned in .github/pins.txt: a change here needs
# `bash scripts/check-pins.sh update` in the same founder PR. Tests: scripts/check-github-lib.test.sh.

# gh_context: sets GH (the gh binary) and REPO (owner/repo). Inside GitHub Actions (GITHUB_ACTIONS set) gh comes from PATH
# and the repository from GITHUB_REPOSITORY, and no environment override is read (a Claude step that ran before could have
# written $GITHUB_ENV); outside (tests) GH_BIN and GH_REPO may override. Returns 1 with a message on a bad repository name.
gh_context() {
  if [ -n "${GITHUB_ACTIONS:-}" ]; then GH=gh; REPO="${GITHUB_REPOSITORY:-}"
  else GH="${GH_BIN:-gh}"; REPO="${GH_REPO:-${GITHUB_REPOSITORY:-}}"; fi
  [ -n "$REPO" ] || { echo "ERROR: GH_REPO or GITHUB_REPOSITORY (owner/repo) is not set"; return 1; }
  [[ "$REPO" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || { echo "ERROR: bad GH_REPO"; return 1; }
}

# token_account <rows>: the account GH_TOKEN belongs to, as TOKEN_ID, TOKEN_LOGIN and TOKEN_ROLE (founder, agent or empty)
# from the rows accounts_rows printed. Returns 1 with a message when the token's login cannot be read.
token_account() {
  local who
  who=$("$GH" api user --jq '"\(.id) \(.login)"' 2>/dev/null || true)
  read -r TOKEN_ID TOKEN_LOGIN <<<"$who" || true
  [[ "${TOKEN_ID:-}" =~ ^[0-9]+$ && "${TOKEN_LOGIN:-}" =~ ^[A-Za-z0-9-]+$ ]] \
    || { echo "ERROR: could not read the token's GitHub login (is GH_TOKEN set and valid?)"; return 1; }
  TOKEN_ROLE=$(account_field "$1" "$TOKEN_ID" 3)
}

# main_guard_runs <sha>: "status/conclusion" of every main-guard run whose head is that commit, space-separated (empty when
# none); returns 1 on an API error.
main_guard_runs() {
  "$GH" api "repos/$REPO/actions/workflows/main-guard.yml/runs?head_sha=$1&per_page=100" \
    --jq '[.workflow_runs[] | "\(.status)/\(.conclusion)"] | join(" ")' 2>/dev/null
}

# MAIN_GUARD_FLOOR: the head of the default branch when the main guard was written (founder-owned constant, pinned with
# this file; a workflow file cannot be changed by the agents' token either). Every commit that is an ancestor of it predates
# the guard and is accepted; every push after it must have its own passed run. A constant, because the runs list the API
# serves is capped (about 1000 runs) and a commit's dates are set by whoever made it.
MAIN_GUARD_FLOOR=596905e54f7ae8385c90f6d334db5f18a4427e28

# main_guard_passed <sha> <wait-seconds>: that commit, as the head of a push to the default branch, has a successful
# main-guard run (waits up to <wait-seconds> for one still going), or is an ancestor of MAIN_GUARD_FLOOR (GitHub's compare
# API: the floor is "ahead" of it or "identical"). Every push to the default branch must pass the main guard, and a push
# whose head commit message says [skip ci] (or a run someone cancelled) has no run at all; because each run checks the
# previous push's head (its `before`) with this, one unchecked push breaks the chain at the next run or the next shift, so
# no first-parent walk is needed: a push's inner commits are covered by the run on its head.
# Prints "ok ..." and returns 0, or "missing <sha> (runs: ...)" and returns 1; API errors print "ERROR: ..." and return 1.
main_guard_passed() {
  local sha=$1 wait_max=$2 waited=0 runs rel floor="${MAIN_GUARD_FLOOR_OVERRIDE:-$MAIN_GUARD_FLOOR}"
  [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || { echo "ERROR: bad commit sha: '$sha'"; return 1; }
  while :; do
    runs=$(main_guard_runs "$sha") || { echo "ERROR: could not list the main-guard runs of $sha."; return 1; }
    case " $runs " in
      *" completed/success "*) echo "ok $sha passed the main guard"; return 0;;
      *" in_progress/"*|*" queued/"*|*" waiting/"*|*" pending/"*|*" requested/"*)
        [ "$waited" -lt "$wait_max" ] || { echo "ERROR: the main-guard run for $sha has not finished after ${wait_max}s; re-run this job later."; return 1; }
        sleep 10; waited=$((waited+10)); continue;;
    esac
    break
  done
  rel=$("$GH" api "repos/$REPO/compare/$sha...$floor" --jq .status 2>/dev/null) || { echo "ERROR: could not compare $sha with the main guard's floor commit $floor."; return 1; }
  case "$rel" in
    ahead|identical) echo "ok $sha is on the default branch before the main guard existed (floor $floor)"; return 0;;
  esac
  echo "missing $sha (runs: ${runs:-none})"; return 1
}

# main_head_passed <wait-seconds> <who-is-stopped>: the default branch's head passed the main guard (main_guard_passed);
# prints the reason and returns 1 otherwise, naming who must not run until a founder looked.
main_head_passed() {
  local wait_max=$1 who=$2 head out
  head=$("$GH" api "repos/$REPO/commits/HEAD" --jq .sha 2>/dev/null) || { echo "ERROR: could not read the default branch's head commit."; return 1; }
  [[ "$head" =~ ^[0-9a-f]{40}$ ]] || { echo "ERROR: could not read the default branch's head commit."; return 1; }
  if ! out=$(main_guard_passed "$head" "$wait_max"); then
    case "$out" in ERROR:*) echo "$out";; *) echo "ERROR: the default branch's head ($head) has no successful main-guard run ($out). A founder checks that push (was the run cancelled, the workflow disabled, or the commit message marked [skip ci]?) before $who.";; esac
    return 1
  fi
  echo "$out"
}
