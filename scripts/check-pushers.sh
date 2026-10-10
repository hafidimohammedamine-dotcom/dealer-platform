#!/usr/bin/env bash
# The pusher ledger (founder-owned): `guards/pusher` commit statuses, one per commit, recording who pushed it. GitHub keeps
# the pusher of a push only in a short-lived event feed, and a commit's author can be forged with any email, so
# pusher-ledger.yml writes the record itself from the push event's sender (trusted) on every push to a branch other than
# main, and guards.yml reads it back. Anyone with write access can post a status under the same context; only the HMAC
# makes a record valid: mac = HMAC-SHA256(GUARDS_LEDGER_KEY, "<sha> <id>"), and the key is a GitHub secret the agents'
# token cannot read, so a forged, copied or edited status never verifies and a deleted one is "no record".
#   record <push-event-json>   from a push event (pusher-ledger.yml, $GITHUB_EVENT_PATH): post a record, as the push's
#       sender, on every commit the event lists as `distinct` - GitHub's own durable judgement that the commit is new to
#       the repository with this push (measured 2026-10-10, runs 38033794584/38033796197/38033869617: a commit pushed
#       earlier is not listed again, not even on a new branch after the branch that held it was rewound away). So a commit
#       that reached GitHub without a ledger run (a head commit saying [skip ci], a cancelled run) is never credited to
#       whoever pushes it again; only brand-new commits (a rebase or a squash makes new ones, and then the founder who made
#       them answers for them) are. A deleted branch records nothing; a push with more commits than the event lists
#       (2048) is an error, so nothing is credited blindly
#   verify <base-ref> <head-ref> <accounts-file>   print "<sha> <id> <founder|agent|unknown>" for every commit, or
#       "<sha> - unknown" when no record has a valid mac, or when valid records name more than one pusher (a commit never
#       passes on a founder's record if another valid record names someone else); check-founder-files.sh then requires
#       every line to be a founder when founder-only files changed
# A GitHub API error is an error (exit 1), never "no record". Needs gh with GH_TOKEN (statuses: write for record) and
# GH_REPO. Rules: docs/runbooks/ci-guards.md.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/check-accounts-lib.sh
. "$HERE/check-accounts-lib.sh"
CMD="${1:-}"
usage() { echo "usage: check-pushers.sh record <push-event-json> | verify <base-ref> <head-ref> <accounts-file>"; exit 2; }
case "$CMD" in
  record) EVENT="${2:-}"; [ -n "$EVENT" ] && [ $# = 2 ] || usage;;
  verify) BASE="${2:-}"; HEAD="${3:-}"; ARG="${4:-}"; [ -n "$BASE" ] && [ -n "$HEAD" ] && [ -n "$ARG" ] || usage;;
  *) usage;;
esac
: "${GH_REPO:?GH_REPO (owner/repo)}"
[[ "$GH_REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "ERROR: bad GH_REPO '$GH_REPO'"; exit 2; }
CTX=guards/pusher

push_event_fields() { # push_event_fields <event.json>: ref, before, after, sender id, deleted, count (tab-separated), then one distinct commit id per line
  python3 -I - "$1" <<'PYEOF'
import json, sys
e = json.load(open(sys.argv[1]))
if not isinstance(e.get("commits"), list) or not isinstance(e.get("sender"), dict): raise SystemExit(1)
print("\t".join([str(e.get("ref", "")), str(e.get("before", "")), str(e.get("after", "")), str(e["sender"].get("id", "")), str(e.get("deleted", False)).lower(), str(len(e["commits"]))]))
print("\n".join(str(c.get("id", "")) for c in e["commits"] if isinstance(c, dict) and c.get("distinct") is True))
PYEOF
}
mac_of() { # mac_of <sha> <id>: HMAC-SHA256 with the ledger key, first 40 hex characters
  MSG="$1 $2" python3 -I -c 'import hashlib, hmac, os; print(hmac.new(os.environ["GUARDS_LEDGER_KEY"].encode(), os.environ["MSG"].encode(), hashlib.sha256).hexdigest()[:40])'
}
records_of() { # records_of <sha>: the descriptions of every guards/pusher status on the commit; fails on an API error
  gh api --paginate "repos/$GH_REPO/commits/$1/statuses" --jq ".[] | select(.context == \"$CTX\") | .description"
}
valid_id_of() { # valid_id_of <sha>: the one pusher id every valid record agrees on; nothing if none; "conflict" if the
  local d id mac recs ids=""     # valid records name different ids; exit 1 on an API error (never read as "no record")
  recs=$(records_of "$1") || { echo "ERROR: could not read the statuses of $1 (GitHub API error); re-run the job" >&2; exit 1; }
  while read -r d; do
    [[ "$d" =~ ^id=([0-9]+)\ mac=([0-9a-f]{40})$ ]] || continue
    id="${BASH_REMATCH[1]}"; mac="${BASH_REMATCH[2]}"
    [ "$(mac_of "$1" "$id")" = "$mac" ] || continue
    case " $ids " in *" $id "*) ;; *) ids+="$id ";; esac
  done <<<"$recs"
  set -- $ids
  if [ $# -gt 1 ]; then echo conflict; elif [ $# = 1 ]; then echo "$1"; fi
  return 0
}

case "$CMD" in
  record)
    [ -f "$EVENT" ] || { echo "ERROR: push event file not found: $EVENT"; exit 2; }
    ev=$(push_event_fields "$EVENT" 2>/dev/null) || { echo "ERROR: could not read the push event (not a push event, or malformed JSON)"; exit 2; }
    { IFS=$'\t' read -r REF BEFORE AFTER ARG DELETED COUNT; mapfile -t distinct; } <<<"$ev"
    [ "${#distinct[@]}" != 1 ] || [ -n "${distinct[0]}" ] || distinct=()   # no distinct commits: an empty line was read
    [[ "$ARG" =~ ^[0-9]+$ ]] || { echo "ERROR: pusher id must be numeric: '$ARG'"; exit 2; }
    [[ "$REF" =~ ^refs/heads/[A-Za-z0-9._/-]+$ ]] || { echo "ERROR: bad ref name '$REF'"; exit 2; }
    [[ "$BEFORE" =~ ^[0-9a-f]{40}$ ]] && [[ "$AFTER" =~ ^[0-9a-f]{40}$ ]] || { echo "ERROR: before/after must be 40-hex commit shas"; exit 2; }
    [ -n "${GUARDS_LEDGER_KEY:-}" ] && [ "${#GUARDS_LEDGER_KEY}" -ge 32 ] \
      || { echo "ERROR: GUARDS_LEDGER_KEY is missing or shorter than 32 characters: a founder sets this GitHub secret (any long random string)"; exit 1; }
    ZERO=0000000000000000000000000000000000000000
    if [ "$DELETED" = true ] || [ "$AFTER" = "$ZERO" ]; then echo "branch deleted; nothing to record"; exit 0; fi
    [ "$COUNT" -lt 2048 ] || { echo "ERROR: the push event lists $COUNT commits (GitHub's limit): too many to credit safely; push in smaller batches"; exit 1; }
    git cat-file -e "$AFTER^{commit}" 2>/dev/null || { echo "ERROR: the pushed commit $AFTER is not in this checkout"; exit 1; }
    echo "Recording the ${#distinct[@]} commit(s) GitHub lists as new to the repository with this push (${REF#refs/heads/}: $BEFORE..$AFTER, $COUNT listed)."
    n=0
    for sha in "${distinct[@]}"; do
      [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || { echo "ERROR: bad commit id in the event: '$sha'"; exit 2; }
      git merge-base --is-ancestor "$sha" "$AFTER" 2>/dev/null || { echo "ERROR: the event lists $sha, which is not on the pushed branch"; exit 1; }
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
    if ! commits=$(git rev-list "$BASE".."$HEAD" 2>/dev/null); then echo "ERROR: could not list commits $BASE..$HEAD"; exit 1; fi
    for sha in $commits; do
      id=$(valid_id_of "$sha") || exit 1
      if [ -z "$id" ]; then echo "$sha - unknown"; continue; fi
      if [ "$id" = conflict ]; then echo "$sha - unknown (valid records name more than one pusher)"; continue; fi
      role=$(account_field "$rows" "$id" 3); echo "$sha $id ${role:-unknown}"
    done
    ;;
esac
