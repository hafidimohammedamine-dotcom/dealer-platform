#!/usr/bin/env bash
# Compares the PR's third-party skills with the base branch's (founder-owned). Run by `guards` (base script, PR's .claude/
# as data), so a PR cannot quietly turn a vendored skill into "ours" (skipping the upstream proof) or point it at a fork.
# Fails if a base third-party skill:
#   - is now listed as anything but third-party (for example `ours`) while its folder still exists, or
#   - keeps its name but its source repo (owner/repo) changes. A different source is a new skill name.
# Logs every other change for the founders: commit or path updates, removed skills, new third-party skills.
# Usage: scripts/check-skills-vs-base.sh <base-root> <pr-root>
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/check-skills-lib.sh
. "$HERE/check-skills-lib.sh"
BASE="${1:?base root}"; PR="${2:?pr root}"
BM="$BASE/.claude/skills/manifest.txt"; PM="$PR/.claude/skills/manifest.txt"
BL="$BASE/.claude/skills/SKILLS-LOCK.md"; PL="$PR/.claude/skills/SKILLS-LOCK.md"
fail=0
declare -A bkind=() pkind=()
[ -f "$BM" ] && while read -r n k _; do bkind["$n"]=$k; done < <(manifest_entries "$BM")
[ -f "$PM" ] && while read -r n k _; do pkind["$n"]=$k; done < <(manifest_entries "$PM")
src() { # src <lock file> <name>: "repo path sha" or "?" when missing or malformed
  local rows
  [ -f "$1" ] || { echo "?"; return; }
  rows=$(lock_rows "$1" "$2")
  if [ "$(grep -c . <<<"$rows" || true)" = 1 ] && lock_parse "$rows"; then echo "$LOCK_REPO $LOCK_PATH $LOCK_SHA"; else echo "?"; fi
}
for n in "${!bkind[@]}"; do
  [ "${bkind[$n]}" = third-party ] || continue
  old=$(src "$BL" "$n")
  if [ -z "${pkind[$n]:-}" ]; then
    if [ -e "$PR/.claude/skills/$n" ]; then echo "ERROR: third-party skill '$n' was removed from the manifest but its folder is still there"; fail=1
    else echo "REMOVED third-party skill '$n' (was: $old)"; fi
    continue
  fi
  if [ "${pkind[$n]}" != third-party ]; then
    echo "ERROR: third-party skill '$n' is now listed as '${pkind[$n]}'; vendored skills stay third-party (remove it and add a new one instead)"; fail=1
    continue
  fi
  new=$(src "$PL" "$n")
  if [ "$old" != "$new" ]; then
    if [ "$old" != "?" ] && [ "$new" != "?" ] && [ "${old%% *}" != "${new%% *}" ]; then
      echo "ERROR: third-party skill '$n' changed its source repo (${old%% *} -> ${new%% *}); a different source needs a new skill name"; fail=1
    else
      echo "CHANGED third-party skill '$n': $old -> $new"
    fi
  fi
done
for n in "${!pkind[@]}"; do
  [ "${pkind[$n]}" = third-party ] && [ "${bkind[$n]:-}" != third-party ] && echo "NEW third-party skill '$n': $(src "$PL" "$n")"
done
[ "$fail" = 0 ] || exit 1
echo "Third-party skills vs base OK"
