#!/usr/bin/env bash
# Reads .github/accounts.txt for the guard scripts (founder-owned). Sourced by check-founder-files.sh and
# check-agent-token.sh; scripts/check-workflows-lib.py reads the same format (read_accounts).
# Format: "<id> <login> <role>" per line, role founder or agent; '#' starts a comment; blank lines are skipped.

# accounts_rows <file>: prints "<id> <login> <role>" for every entry. Returns 1 (with a message) on a missing file, a bad
# line or a file without any founder, so a broken file never lets anyone through.
accounts_rows() {
  local file=$1 n=0 line id login role extra rows="" founders=0
  [ -f "$file" ] || { echo "ERROR: accounts file not found: $file"; return 1; }
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1)); line="${line%%#*}"
    read -r id login role extra <<<"$line" || true
    [ -n "${id:-}" ] || continue
    if ! [[ "$id" =~ ^[0-9]+$ && "${login:-}" =~ ^[A-Za-z0-9-]+$ && "${role:-}" =~ ^(founder|agent)$ && -z "${extra:-}" ]]; then
      echo "ERROR: bad line $n in $file (want '<id> <login> founder|agent'): $line"; return 1
    fi
    [ "$role" = founder ] && founders=$((founders + 1))
    rows+="$id $login $role"$'\n'
  done < "$file"
  [ "$founders" -gt 0 ] || { echo "ERROR: no founder listed in $file"; return 1; }
  printf '%s' "$rows"
}
