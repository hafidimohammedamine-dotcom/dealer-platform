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

# main_guard_runs <sha>: "status/conclusion" of every main-guard run started by a push whose head is that commit,
# space-separated (empty when none); returns 1 on an API error. Only push runs count: the hourly schedule run and a
# founder's workflow_dispatch run also carry the head's sha, and the schedule run would otherwise find itself (still in
# progress) when it checks main's head.
main_guard_runs() {
  "$GH" api "repos/$REPO/actions/workflows/main-guard.yml/runs?head_sha=$1&per_page=100" \
    --jq '[.workflow_runs[] | select(.event == "push") | "\(.status)/\(.conclusion)"] | join(" ")' 2>/dev/null
}

# The commit status that stands in for a main-guard run: context guards/main-guard, state success, created by
# github-actions[bot] (user ID 41898282, the identity of every workflow's job token). main-guard.yml posts it from its own
# token on the revert commit it pushes (a push made with a workflow's token starts no workflow, so that commit has no run of
# its own) and on a commit a founder accepts by hand (workflow_dispatch, after reading it). The agents' token cannot forge
# it: a status it posts has the agents' account as creator, and no job the agents' code runs in holds `statuses: write`
# (the workflow checker allows that scope only in main-guard.yml and pusher-ledger.yml, whose scripts are pinned).
MAIN_GUARD_STATUS=guards/main-guard
GITHUB_ACTIONS_BOT_ID=41898282

# main_guard_status <sha>: prints the number of guards/main-guard success statuses github-actions[bot] created on that
# commit (0 when none); returns 1 on an API error.
main_guard_status() {
  "$GH" api "repos/$REPO/commits/$1/status" \
    --jq "[.statuses[] | select(.context == \"$MAIN_GUARD_STATUS\" and .state == \"success\" and .creator.id == $GITHUB_ACTIONS_BOT_ID)] | length" 2>/dev/null
}

# mark_main_guard_passed <sha> <description>: posts that status on the commit (the caller's token must be a workflow's job
# token with statuses: write); returns 1 when the API call fails.
mark_main_guard_passed() {
  "$GH" api -X POST "repos/$REPO/statuses/$1" -f state=success -f "context=$MAIN_GUARD_STATUS" -f "description=$2" >/dev/null 2>&1
}

# main_guard_latest: the head sha of the newest successful main-guard push run (empty when there is none yet); returns 1 on
# an API error. The default branch must still descend from it: a force push back to an older, once-checked commit (with
# the workflow disabled or its run cancelled, so no run records the move) would otherwise pass every check, since that
# older commit keeps its old successful run.
main_guard_latest() {
  "$GH" api "repos/$REPO/actions/workflows/main-guard.yml/runs?event=push&status=success&per_page=1" \
    --jq '.workflow_runs[0].head_sha // empty' 2>/dev/null
}

# MAIN_GUARD_RUNS_FROM: the first main-guard run number the deletion check below covers (founder-owned constant, pinned
# with this file). 1 when the workflow is new. After a real deletion (or a founder's own mistake), the gap stays until
# retention removes it from the old end, so the recovery is a founder PR that raises this constant to the current run
# number (and runs `bash scripts/check-pins.sh update`); until then every hourly run keeps stopping the agents.
MAIN_GUARD_RUNS_FROM=1

# main_guard_runs_intact <this-run-number>: no main-guard run has been deleted, re-run or cancelled (the agents' classic
# `repo` token can do all three; deleting runs, or re-running and cancelling them, is how the newest checked head could be
# erased: with every run newer than an older commit's gone or no longer a success, main_guard_latest points at that
# commit). Run numbers are sequential and never reused, and GitHub's retention removes runs from the old end only, so the
# retained runs numbered from MAIN_GUARD_RUNS_FROM up to <this-run-number> - 1 must be one unbroken sequence ending at
# <this-run-number> - 1, none of them re-run (run_attempt > 1) or cancelled; none retained is fine only for run number
# MAIN_GUARD_RUNS_FROM itself. Runs numbered above this one (a push run started meanwhile; this run being a re-run of an
# older one) are left out: they cannot hide anything from this run. Founders never re-run, cancel or delete a main-guard
# run; after one, the recovery is a founder PR raising MAIN_GUARD_RUNS_FROM. Prints "ok ..." and returns 0, "deleted ..."
# or "tampered ..." and returns 1, or "ERROR: ..." on an API error.
main_guard_runs_intact() {
  local me=$1 rows n a c prev="" first="" from=$MAIN_GUARD_RUNS_FROM
  [[ "$me" =~ ^[0-9]+$ ]] || { echo "ERROR: bad run number: '$me'"; return 1; }
  rows=$("$GH" api --paginate "repos/$REPO/actions/workflows/main-guard.yml/runs?per_page=100" --jq '.workflow_runs[] | "\(.run_number) \(.run_attempt) \(.conclusion)"' 2>/dev/null) \
    || { echo "ERROR: could not list the main-guard runs."; return 1; }
  rows=$(grep -E '^[0-9]+ [0-9]+ ' <<<"$rows" | sort -n | uniq | awk -v me="$me" -v from="$from" '$1 >= from && $1 < me' || true)
  if [ -z "$rows" ]; then
    [ "$me" -le "$from" ] && { echo "ok no earlier main-guard run from #$from is retained (this is run #$me)"; return 0; }
    echo "deleted main-guard run(s) #$from..#$((me-1)): none is retained before this run #$me; someone deleted workflow runs"; return 1
  fi
  while read -r n a c; do
    [ -n "$first" ] || first=$n
    [ -z "$prev" ] || [ "$n" = $((prev+1)) ] || { echo "deleted main-guard run(s) between #$prev and #$n: someone deleted workflow runs"; return 1; }
    [ "$a" = 1 ] || { echo "tampered main-guard run #$n: re-run (attempt $a); a re-run can replace a passed run's result"; return 1; }
    [ "$c" != cancelled ] || { echo "tampered main-guard run #$n: cancelled; a cancelled run checked nothing"; return 1; }
    prev=$n
  done <<<"$rows"
  [ "$prev" = $((me-1)) ] || { echo "deleted main-guard run(s) between #$prev and this run #$me: someone deleted workflow runs"; return 1; }
  echo "ok main-guard runs #$first..#$prev are all retained, first attempts, none cancelled"
}

# MAIN_GUARD_HEARTBEAT: how old (seconds) the newest successful hourly main-guard run may be before every Claude job and
# shift refuses to start: the hourly run is what detects deleted, re-run or cancelled runs (main_guard_runs_intact), and
# the agents' token could cancel it every hour instead. 75 minutes: one hourly slot plus a margin.
MAIN_GUARD_HEARTBEAT=4500

# main_guard_heartbeat: a scheduled main-guard run completed with success within MAIN_GUARD_HEARTBEAT seconds (or none
# has been scheduled yet and the workflow's newest run is that young: the first hour after the merge). Prints "ok ..." and
# returns 0, "stale ..." and returns 1, or "ERROR: ..." on an API error.
main_guard_heartbeat() {
  local sched newest at now age
  now=$(date -u +%s)
  sched=$("$GH" api "repos/$REPO/actions/workflows/main-guard.yml/runs?event=schedule&per_page=10" --jq '.workflow_runs[] | "\(.status) \(.conclusion) \(.created_at)"' 2>/dev/null) \
    || { echo "ERROR: could not list the scheduled main-guard runs."; return 1; }
  if [ -z "$sched" ]; then
    newest=$("$GH" api "repos/$REPO/actions/workflows/main-guard.yml/runs?per_page=1" --jq '.workflow_runs[0].created_at // empty' 2>/dev/null) \
      || { echo "ERROR: could not list the main-guard runs."; return 1; }
    at=$(date -u -d "$newest" +%s 2>/dev/null) || { echo "ERROR: could not read the newest main-guard run's time."; return 1; }
    age=$((now-at))
    [ "$age" -le "$MAIN_GUARD_HEARTBEAT" ] && { echo "ok no hourly main-guard run yet; the workflow's newest run is ${age}s old"; return 0; }
    echo "stale: no hourly main-guard run exists although the workflow's newest run is ${age}s old (the schedule is not firing, or its runs were deleted)"; return 1
  fi
  at=$(awk '$1 == "completed" && $2 == "success" {print $3; exit}' <<<"$sched")
  [ -n "$at" ] || { echo "stale: none of the last scheduled main-guard runs completed with success ($(tr '\n' ';' <<<"$sched"))"; return 1; }
  at=$(date -u -d "$at" +%s 2>/dev/null) || { echo "ERROR: could not read the scheduled run's time."; return 1; }
  age=$((now-at))
  [ "$age" -le "$MAIN_GUARD_HEARTBEAT" ] && { echo "ok the last successful hourly main-guard run is ${age}s old"; return 0; }
  echo "stale: the last successful hourly main-guard run is ${age}s old (more than ${MAIN_GUARD_HEARTBEAT}s): the hourly run was cancelled or stopped"; return 1
}

# MAIN_GUARD_FLOOR: the head of the default branch when the main guard was written (founder-owned constant, pinned with
# this file; a workflow file cannot be changed by the agents' token either). Every commit that is an ancestor of it predates
# the guard and is accepted; every push after it must have its own passed run. A constant, because the runs list the API
# serves is capped (about 1000 runs) and a commit's dates are set by whoever made it.
MAIN_GUARD_FLOOR=596905e54f7ae8385c90f6d334db5f18a4427e28

# main_guard_passed <sha> <wait-seconds>: that commit, as the head of a push to the default branch, has a successful
# main-guard run (waits up to <wait-seconds> for one still going), carries the guards/main-guard status (main_guard_status:
# the guard's own revert commit, or a commit a founder accepted), or is an ancestor of MAIN_GUARD_FLOOR (GitHub's compare
# API: the floor is "ahead" of it or "identical"). Every push to the default branch must pass the main guard, and a push
# whose head commit message says [skip ci] (or a run someone cancelled) has no run at all; because each run checks the
# previous push's head (its `before`) with this, one unchecked push breaks the chain at the next run or the next shift, so
# no first-parent walk is needed: a push's inner commits are covered by the run on its head.
# The commit must also descend from the newest checked head (main_guard_latest): "rolled back <sha> (behind the last
# checked head <latest>, compare: behind|diverged)" otherwise.
# Prints "ok ..." and returns 0, or "missing <sha> (runs: ...)" / "rolled back ..." and returns 1; API errors print
# "ERROR: ..." and return 1. The checks that read the result never take an override from the environment: the floor is
# this file's constant.
main_guard_passed() {
  local sha=$1 wait_max=$2 out
  [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || { echo "ERROR: bad commit sha: '$sha'"; return 1; }
  out=$(main_guard_checked "$sha" "$wait_max") || { echo "$out"; return 1; }
  main_guard_lineage "$sha" || return 1
  echo "$out"
}

# main_guard_lineage <sha>: the commit is the newest checked head or descends from it (nothing to compare before the first
# successful push run). Prints "rolled back ..." and returns 1 otherwise; API errors print "ERROR: ..." and return 1.
main_guard_lineage() {
  local sha=$1 latest rel
  latest=$(main_guard_latest) || { echo "ERROR: could not read the newest main-guard run."; return 1; }
  [ -n "$latest" ] && [ "$latest" != "$sha" ] || return 0
  [[ "$latest" =~ ^[0-9a-f]{40}$ ]] || { echo "ERROR: could not read the newest main-guard run."; return 1; }
  rel=$("$GH" api "repos/$REPO/compare/$latest...$sha" --jq .status 2>/dev/null) || { echo "ERROR: could not compare $sha with the last checked head $latest."; return 1; }
  case "$rel" in ahead|identical) return 0;; esac
  echo "rolled back $sha (behind the last checked head $latest, compare: ${rel:-unknown}): the default branch was moved back to an older commit"; return 1
}

# main_guard_checked <sha> <wait-seconds>: the run, status and floor checks of main_guard_passed, without the lineage.
main_guard_checked() {
  local sha=$1 wait_max=$2 waited=0 runs rel marks floor=$MAIN_GUARD_FLOOR
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
  marks=$(main_guard_status "$sha") || { echo "ERROR: could not read the commit statuses of $sha."; return 1; }
  [[ "$marks" =~ ^[0-9]+$ ]] || { echo "ERROR: could not read the commit statuses of $sha."; return 1; }
  [ "$marks" = 0 ] || { echo "ok $sha carries the $MAIN_GUARD_STATUS status (the main guard's revert, or accepted by a founder)"; return 0; }
  rel=$("$GH" api "repos/$REPO/compare/$sha...$floor" --jq .status 2>/dev/null) || { echo "ERROR: could not compare $sha with the main guard's floor commit $floor."; return 1; }
  case "$rel" in
    ahead|identical) echo "ok $sha is on the default branch before the main guard existed (floor $floor)"; return 0;;
  esac
  echo "missing $sha (runs: ${runs:-none})"; return 1
}

# main_head_passed <wait-seconds> <who-is-stopped> [checked-out-sha]: the hourly main-guard run is alive
# (main_guard_heartbeat) and the default branch's head passed the main guard (main_guard_passed); with <checked-out-sha> (what this job checked out), that commit must also be the default branch's
# head as GitHub sees it, so the job judges exactly the tree it runs. Prints the reason and returns 1 otherwise, naming
# who must not run until a founder looked.
main_head_passed() {
  local wait_max=$1 who=$2 local_sha=${3:-} head out hb
  head=$("$GH" api "repos/$REPO/commits/HEAD" --jq .sha 2>/dev/null) || { echo "ERROR: could not read the default branch's head commit."; return 1; }
  [[ "$head" =~ ^[0-9a-f]{40}$ ]] || { echo "ERROR: could not read the default branch's head commit."; return 1; }
  if [ -n "$local_sha" ] && [ "$local_sha" != "$head" ]; then
    echo "ERROR: this job checked out $local_sha but the default branch's head is $head now; start a fresh run."; return 1
  fi
  if ! hb=$(main_guard_heartbeat); then
    case "$hb" in ERROR:*) echo "$hb";; *) echo "ERROR: the hourly main-guard run has not passed lately ($hb). A founder checks the main-guard runs (cancelled? the workflow disabled?) before $who.";; esac
    return 1
  fi
  if ! out=$(main_guard_passed "$head" "$wait_max"); then
    case "$out" in
      ERROR:*) echo "$out";;
      "rolled back"*) echo "ERROR: the default branch's head ($head) is behind the last checked head ($out). A founder checks who moved the default branch back (the repository's audit log; the workflow disabled or a run cancelled meanwhile?) before $who.";;
      *) echo "ERROR: the default branch's head ($head) has no successful main-guard run ($out). A founder checks that push (was the run cancelled, the workflow disabled, or the commit message marked [skip ci]?) before $who.";;
    esac
    return 1
  fi
  echo "$out"
}
