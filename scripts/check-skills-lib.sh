#!/usr/bin/env bash
# Shared helpers for the skill guards (founder-owned). Sourced by check-skills.sh, check-skills-upstream-all.sh and
# check-skills-vs-base.sh so they read the manifest and SKILLS-LOCK.md rows the same way.
#
# SKILLS-LOCK.md row: | <name> | <owner>/<repo> `<path in repo>`[, anything] | <40-hex commit, lower case> | ...
#   - found by an exact match on the first cell;
#   - the commit is the third cell and nothing else.

# manifest_lines <manifest.txt>: prints "<name>\t<kind>\t<rest of the line>" for every entry; skips blank and # lines.
# The one place that splits manifest lines; check-skills.sh validates <rest>, manifest_entries reads requires= from it.
manifest_lines() {
  local name kind rest
  while read -r name kind rest; do
    [ -z "${name:-}" ] && continue
    case "$name" in \#*) continue;; esac
    printf '%s\t%s\t%s\n' "$name" "${kind:-}" "${rest:-}"
  done < "$1"
}

# manifest_entries <manifest.txt>: prints "<name> <kind> <requires-or-empty>" per entry (the first requires= wins;
# check-skills.sh rejects a second one).
manifest_entries() {
  local name kind rest opt req
  while IFS=$'\t' read -r name kind rest; do
    req=""
    for opt in $rest; do case "$opt" in requires=*) [ -n "$req" ] || req="${opt#requires=}";; esac; done
    printf '%s %s %s\n' "$name" "$kind" "$req"
  done < <(manifest_lines "$1")
}

# valid_skill_name <name>: true for a lower-case kebab name (the only names allowed for skill folders).
valid_skill_name() { [[ "$1" =~ ^[a-z0-9][a-z0-9-]*$ ]]; }

# lock_row_one <SKILLS-LOCK.md> <name>: finds exactly one row for <name> and parses it (sets LOCK_REPO, LOCK_PATH,
# LOCK_SHA). Returns 1 = missing file, 2 = no row, 3 = more than one row, 4 = row with the wrong shape.
lock_row_one() {
  local rows n
  [ -f "$1" ] || return 1
  rows=$(lock_rows "$1" "$2"); n=$(grep -c . <<<"$rows" || true)
  [ "$n" -ge 1 ] || return 2
  [ "$n" -eq 1 ] || return 3
  lock_parse "$rows" || return 4
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
