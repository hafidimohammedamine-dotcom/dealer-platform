#!/usr/bin/env bash
# Reads .github/accounts.txt for the guard scripts (founder-owned): the one parser of that file. Sourced by
# check-founder-files.sh, check-agent-token.sh, check-pushers.sh, check-main-push.sh and check-workflows.sh (which hands the
# rows to Python). Format: "<id> <login> <role>" per line, role founder or agent; '#' starts a comment; blank lines skipped.
# main-guard.yml pins this file by sha256: a change here updates the pin there (scripts/check-main-push.test.sh checks).

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
