#!/usr/bin/env bash
# The pusher ledger (founder-owned): `guards/pusher` commit statuses, one per commit, recording who pushed it. GitHub keeps
# the pusher of a push only in a short-lived event feed, and a commit's author can be forged with any email, so
# pusher-ledger.yml writes the record itself from the push event's sender (trusted) on every push to a branch other than
# main, and guards.yml reads it back. Anyone with write access can post a status under the same context; only the HMAC
# makes a record valid: mac = HMAC-SHA256(GUARDS_LEDGER_KEY, "<sha> <id>"), and the key is a GitHub secret the agents'
# token cannot read, so a forged, copied or edited status never verifies and a deleted one is "no record".
#   record <base-ref> <head-ref> <pusher-id>   post a record on every commit of base..head that has no valid record yet
#   verify <base-ref> <head-ref> <accounts-file>   print "<sha> <id> <founder|agent|unknown>" for every commit, or
#       "<sha> - unknown" when no record has a valid mac; check-founder-files.sh then requires every line to be a founder
#       when founder-only files changed
# A GitHub API error is an error (exit 1), never "no record". Needs gh with GH_TOKEN (statuses: write for record) and
# GH_REPO. Rules: docs/runbooks/ci-guards.md.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/check-accounts-lib.sh
. "$HERE/check-accounts-lib.sh"
CMD="${1:-}"; BASE="${2:-}"; HEAD="${3:-}"; ARG="${4:-}"
[ -n "$CMD" ] && [ -n "$BASE" ] && [ -n "$HEAD" ] && [ -n "$ARG" ] || { echo "usage: check-pushers.sh record|verify <base-ref> <head-ref> <pusher-id|accounts-file>"; exit 2; }
: "${GH_REPO:?GH_REPO (owner/repo)}"
[[ "$GH_REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "ERROR: bad GH_REPO '$GH_REPO'"; exit 2; }
CTX=guards/pusher

mac_of() { # mac_of <sha> <id>: HMAC-SHA256 with the ledger key, first 40 hex characters
  MSG="$1 $2" python3 -I -c 'import hashlib, hmac, os; print(hmac.new(os.environ["GUARDS_LEDGER_KEY"].encode(), os.environ["MSG"].encode(), hashlib.sha256).hexdigest()[:40])'
}
records_of() { # records_of <sha>: the descriptions of every guards/pusher status on the commit; fails on an API error
  gh api --paginate "repos/$GH_REPO/commits/$1/statuses" --jq ".[] | select(.context == \"$CTX\") | .description"
}
valid_id_of() { # valid_id_of <sha>: the pusher id of the first record whose mac verifies, nothing if none; exit 1 on an API
  local d id mac recs            # error (a network problem must never read as "no record")
  recs=$(records_of "$1") || { echo "ERROR: could not read the statuses of $1 (GitHub API error); re-run the job" >&2; exit 1; }
  while read -r d; do
    [[ "$d" =~ ^id=([0-9]+)\ mac=([0-9a-f]{40})$ ]] || continue
    id="${BASH_REMATCH[1]}"; mac="${BASH_REMATCH[2]}"
    if [ "$(mac_of "$1" "$id")" = "$mac" ]; then echo "$id"; return 0; fi
  done <<<"$recs"
  return 0
}
if ! commits=$(git rev-list "$BASE".."$HEAD" 2>/dev/null); then echo "ERROR: could not list commits $BASE..$HEAD"; exit 1; fi

case "$CMD" in
  record)
    [[ "$ARG" =~ ^[0-9]+$ ]] || { echo "ERROR: pusher id must be numeric: '$ARG'"; exit 2; }
    [ -n "${GUARDS_LEDGER_KEY:-}" ] && [ "${#GUARDS_LEDGER_KEY}" -ge 32 ] \
      || { echo "ERROR: GUARDS_LEDGER_KEY is missing or shorter than 32 characters: a founder sets this GitHub secret (any long random string)"; exit 1; }
    n=0
    for sha in $commits; do
      id=$(valid_id_of "$sha") || exit 1
      [ -z "$id" ] || continue
      gh api -X POST "repos/$GH_REPO/statuses/$sha" -f state=success -f context="$CTX" -f description="id=$ARG mac=$(mac_of "$sha" "$ARG")" >/dev/null \
        || { echo "ERROR: could not record the pusher of $sha"; exit 1; }
      n=$((n+1))
    done
    echo "Recorded $n new commit(s) as pushed by user ID $ARG."
    ;;
  verify)
    [ -n "${GUARDS_LEDGER_KEY:-}" ] || { echo "ERROR: GUARDS_LEDGER_KEY is missing: a founder sets this GitHub secret"; exit 1; }
    rows=$(accounts_rows "$ARG") || { echo "$rows"; exit 1; }
    for sha in $commits; do
      id=$(valid_id_of "$sha") || exit 1
      if [ -z "$id" ]; then echo "$sha - unknown"; continue; fi
      role=$(account_field "$rows" "$id" 3); echo "$sha $id ${role:-unknown}"
    done
    ;;
  *) echo "usage: check-pushers.sh record|verify <base-ref> <head-ref> <pusher-id|accounts-file>"; exit 2;;
esac
