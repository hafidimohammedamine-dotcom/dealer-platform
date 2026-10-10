#!/usr/bin/env bash
# Reads .github/accounts.txt for the guard scripts (founder-owned): the one parser of that file. Sourced by
# check-founder-files.sh, check-agent-token.sh, check-pushers.sh, check-main-push.sh and check-workflows.sh (which hands the
# rows to Python). Format: "<id> <login> <role>" per line, role founder or agent; '#' starts a comment; blank lines skipped.
# Pinned in .github/pins.txt: a change here needs `bash scripts/check-pins.sh update` in the same founder PR.

# accounts_rows <file>: prints "<id> <login> <role>" for every entry. Returns 1 (with a message) on a missing file, a bad
# line, a user ID listed twice or a file without any founder, so a broken file never lets anyone through.
accounts_rows() {
  local file=$1 n=0 line id login role extra rows="" founders=0 ids=""
  [ -f "$file" ] || { echo "ERROR: accounts file not found: $file"; return 1; }
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1)); line="${line%%#*}"
    read -r id login role extra <<<"$line" || true
    [ -n "${id:-}" ] || continue
    if ! [[ "$id" =~ ^[0-9]+$ && "${login:-}" =~ ^[A-Za-z0-9-]+$ && "${role:-}" =~ ^(founder|agent)$ && -z "${extra:-}" ]]; then
      echo "ERROR: bad line $n in $file (want '<id> <login> founder|agent'): $line"; return 1
    fi
    case " $ids " in *" $id "*) echo "ERROR: user ID $id is listed twice in $file (line $n)"; return 1;; esac
    ids+=" $id"
    [ "$role" = founder ] && founders=$((founders + 1))
    rows+="$id $login $role"$'\n'
  done < "$file"
  [ "$founders" -gt 0 ] || { echo "ERROR: no founder listed in $file"; return 1; }
  printf '%s' "$rows"
}

# account_field <rows> <id> <2|3>: the login (2) or role (3) of a user ID in the rows accounts_rows printed; empty if absent.
account_field() { awk -v i="$2" -v f="$3" '$1 == i {print $f; exit}' <<<"$1"; }

# --- GitHub helpers shared by the guards that run with a token (check-agent-token.sh, check-agent-events.sh,
# check-main-push.sh). Nothing here prints a token.

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

# main_guard_passed <sha> <wait-seconds>: that commit, as the head of a push to the default branch, has a successful
# main-guard run (waits up to <wait-seconds> for one still going), or was committed before the main-guard workflow existed.
# Every push to the default branch must pass the main guard, and a push whose head commit message says [skip ci] (or a
# run someone cancelled) has no run at all; because each run checks the previous push's head (its `before`) with this,
# one unchecked push breaks the chain at the next run or the next shift, so no first-parent walk is needed: a push's
# inner commits are covered by the run on its head. Prints "ok ..." and returns 0, or "missing <sha> (runs: ...)" and
# returns 1; API errors print "ERROR: ..." and return 1.
main_guard_passed() {
  local sha=$1 wait_max=$2 waited=0 runs floor date
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
  floor=$("$GH" api "repos/$REPO/actions/workflows/main-guard.yml" --jq .created_at 2>/dev/null) \
    || { echo "ERROR: could not read when the main-guard workflow was created."; return 1; }
  date=$("$GH" api "repos/$REPO/commits/$sha" --jq .commit.committer.date 2>/dev/null) || { echo "ERROR: could not read commit $sha."; return 1; }
  [[ "$date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]] || { echo "ERROR: could not read commit $sha."; return 1; }
  if [[ "$date" < "$floor" ]]; then echo "ok $sha was committed before the main guard existed ($date < $floor)"; return 0; fi   # ISO-8601 UTC sorts as time
  echo "missing $sha (runs: ${runs:-none})"; return 1
}
