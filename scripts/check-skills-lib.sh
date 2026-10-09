#!/usr/bin/env bash
# Shared helpers for the skill guards (founder-owned). Sourced by check-skills.sh, check-skills-upstream-all.sh and
# check-skills-vs-base.sh so they read the manifest and SKILLS-LOCK.md rows the same way.
#
# SKILLS-LOCK.md row: | <name> | <owner>/<repo> `<path in repo>`[, anything] | <40-hex commit, lower case> | ...
#   - found by an exact match on the first cell;
#   - the commit is the third cell and nothing else.

# manifest_entries <manifest.txt>: prints "<name> <kind> <requires-or-empty>" per entry; skips blank and # lines.
manifest_entries() {
  local name kind rest opt req
  while read -r name kind rest; do
    [ -z "${name:-}" ] && continue
    case "$name" in \#*) continue;; esac
    req=""
    for opt in $rest; do case "$opt" in requires=*) req="${opt#requires=}";; esac; done
    printf '%s %s %s\n' "$name" "${kind:-}" "$req"
  done < "$1"
}

# lock_rows <SKILLS-LOCK.md> <name>: prints every row whose first cell is exactly <name>.
lock_rows() {
  awk -F'|' -v n="$2" 'NF>2 { c=$2; gsub(/[[:space:]]/,"",c); if (c==n) print }' "$1"
}

# lock_parse <row>: sets LOCK_REPO, LOCK_PATH, LOCK_SHA; returns 1 if the row does not have the required shape.
lock_parse() {
  local parsed
  LOCK_REPO=""; LOCK_PATH=""; LOCK_SHA=""
  parsed=$(awk -F'|' '{
      src=$3; sha=$4; gsub(/^[[:space:]]+|[[:space:]]+$/, "", sha)
      if (match(src, /^[[:space:]]*[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+[[:space:]]+`[^`]+`/)) {
        s=substr(src, RSTART, RLENGTH); gsub(/^[[:space:]]+/, "", s)
        split(s, a, /[[:space:]]+`/); p=a[2]; sub(/`$/, "", p)
        print a[1] "\t" p "\t" sha
      }
    }' <<<"$1")
  [ -n "$parsed" ] || return 1
  IFS=$'\t' read -r LOCK_REPO LOCK_PATH LOCK_SHA <<<"$parsed"
  [[ "$LOCK_SHA" =~ ^[0-9a-f]{40}$ ]] || return 1
  [[ "$LOCK_PATH" != /* && "$LOCK_PATH" != *..* ]] || return 1
  return 0
}
