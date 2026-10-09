#!/usr/bin/env bash
# Checks .claude/skills against its manifest and checksums.
#   .claude/skills/manifest.txt     one skill folder per line: "<name> <ours|third-party>"
#   .claude/skills/checksums.sha256 sha256 of every file under the skill folders
# Fails on: third-party skills without NOTICE.md, a license file, or a SKILLS-LOCK.md row with the same commit;
# front matter names that don't match the folder; agents preloading unknown skills or a skill without its required override; folders not in the manifest, manifest entries with no folder, symlinks, special files, empty folders,
# file names with newline/backslash/control characters, added / removed / renamed / changed files.
# Usage: scripts/check-skills.sh [--write] [repo-root]     (--write: founders only, in a skills PR)
set -euo pipefail
MODE=check
if [ "${1:-}" = "--write" ]; then MODE=write; shift; fi
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT"
DIR=.claude/skills
MANIFEST="$DIR/manifest.txt"
SUMS="$DIR/checksums.sha256"
TOP_FILES=" manifest.txt checksums.sha256 SKILLS-LOCK.md "
fail=0
err() { echo "ERROR: $*"; fail=1; }

[ -d "$DIR" ] || { echo "ERROR: missing $DIR"; exit 1; }
[ -f "$MANIFEST" ] || { echo "ERROR: missing $MANIFEST"; exit 1; }

declare -A listed=() third=() requires=()
while read -r name kind rest; do
  [ -z "${name:-}" ] && continue
  case "$name" in \#*) continue;; esac
  case "$kind" in ours|third-party) ;; *) err "manifest line for '$name' needs kind 'ours' or 'third-party'";; esac
  [[ "$name" =~ ^[a-z0-9][a-z0-9-]*$ ]] || err "bad skill name in manifest: '$name'"
  listed["$name"]=1
  for opt in $rest; do
    case "$opt" in requires=*) requires["$name"]="${opt#requires=}";; *) err "unknown option '$opt' for '$name' in manifest";; esac
  done
  [ "$kind" = third-party ] && third["$name"]=1
done < "$MANIFEST"

# Every entry directly under .claude/skills (including dot-entries)
while IFS= read -r -d '' entry; do
  name=${entry#"$DIR/"}
  if [ -L "$entry" ]; then err "symlink not allowed: $entry"; continue; fi
  if [ -d "$entry" ]; then
    [ -n "${listed[$name]:-}" ] || err "skill folder not in manifest: $name"
  elif [ -f "$entry" ]; then
    case "$TOP_FILES" in *" $name "*) ;; *) err "unexpected file: $entry";; esac
  else err "special file not allowed: $entry"; fi
done < <(find "$DIR" -mindepth 1 -maxdepth 1 -print0)

for name in "${!listed[@]}"; do [ -d "$DIR/$name" ] || err "manifest lists '$name' but the folder is missing"; done
# Third-party skills need a NOTICE.md, a license file, and a row in SKILLS-LOCK.md whose commit matches NOTICE.md.
for name in "${!third[@]}"; do
  [ -d "$DIR/$name" ] || continue
  [ -f "$DIR/$name/NOTICE.md" ] || err "third-party skill '$name' has no NOTICE.md"
  lic=0
  for lf in "$DIR/$name"/*; do
    b=$(basename "$lf")
    if [[ "${b,,}" =~ ^(upstream-)?licen[cs]e(\.(md|txt))?$ ]] && [ -f "$lf" ] && [ ! -L "$lf" ] && [ -s "$lf" ]; then lic=1; fi
  done
  [ "$lic" = 1 ] || err "third-party skill '$name' has no license file (LICENSE, LICENSE.md/.txt or UPSTREAM-LICENSE*, non-empty, at the top of the folder)"
  row=""
  [ -f "$DIR/SKILLS-LOCK.md" ] && row=$(grep -E "^\| *([^|]*[ ,])?$name([ ,][^|]*)? *\|" "$DIR/SKILLS-LOCK.md" | head -n1 || true)
  if [ -z "$row" ]; then err "third-party skill '$name' has no row in SKILLS-LOCK.md"; continue; fi
  lock_sha=$(grep -oiE '\b[0-9a-f]{40}\b' <<<"$row" | head -n1 | tr 'A-F' 'a-f' || true)
  notice_sha=$( [ -f "$DIR/$name/NOTICE.md" ] && grep -oiE '\b[0-9a-f]{40}\b' "$DIR/$name/NOTICE.md" | head -n1 | tr 'A-F' 'a-f' || true)
  [ -n "$lock_sha" ] || err "SKILLS-LOCK.md row for '$name' has no full 40-character commit"
  [ -n "$notice_sha" ] || err "NOTICE.md for '$name' has no full 40-character commit"
  [ -z "$lock_sha" ] || [ -z "$notice_sha" ] || [ "$lock_sha" = "$notice_sha" ] || err "commit for '$name' differs between SKILLS-LOCK.md and NOTICE.md"
done
# Each skill's front matter name matches its folder.
for name in "${!listed[@]}"; do
  [ -f "$DIR/$name/SKILL.md" ] || { [ -d "$DIR/$name" ] && err "skill '$name' has no SKILL.md"; continue; }
  fm=$(awk 'NR==1 && $0!="---"{exit} NR>1 && $0=="---"{exit} NR>1 && /^name:/{sub(/^name:[ ]*/,""); gsub(/["'\'' ]/,""); print; exit}' "$DIR/$name/SKILL.md")
  [ "$fm" = "$name" ] || err "skill '$name': SKILL.md front matter name is '$fm'"
done
# A skill with requires=<other> needs <other> in the manifest.
for name in "${!requires[@]}"; do
  [ -n "${listed[${requires[$name]}]:-}" ] || err "skill '$name' requires '${requires[$name]}', which is not in the manifest"
done
# Agents may only preload skills from the manifest, and always together with what they require.
if [ ! -d .claude/agents ]; then
  err "missing .claude/agents (the agent skill preloads can't be checked)"
else
  shopt -s nullglob
  for agent in .claude/agents/*.md; do
    [ -f "$agent" ] || continue
    fmt=$(awk 'NR==1 && $0!="---"{exit} NR>1 && $0=="---"{exit} NR>1{print}' "$agent")
    n=$(grep -c '^skills:' <<<"$fmt" || true)
    [ "$n" -le 1 ] || { err "$(basename "$agent"): more than one 'skills:' line"; continue; }
    [ "$n" = 1 ] || continue
    line=$(grep -m1 '^skills:' <<<"$fmt" | sed 's/^skills:[[:space:]]*//; s/[[:space:]]*$//')
    if ! [[ "$line" =~ ^[a-z0-9][a-z0-9-]*([[:space:]]*,[[:space:]]*[a-z0-9][a-z0-9-]*)*$ ]]; then
      err "$(basename "$agent"): 'skills:' must be a one-line comma list (e.g. skills: a, b), got '$line'"; continue
    fi
    IFS=',' read -r -a sk <<< "$line"
    have=" "; for x in "${sk[@]}"; do x="${x//[[:space:]]/}"; have+="$x "; done
    for x in $have; do
      [ -n "${listed[$x]:-}" ] || err "$(basename "$agent"): skill '$x' is not in the manifest"
      r="${requires[$x]:-}"
      [ -z "$r" ] || [[ "$have" == *" $r "* ]] || err "$(basename "$agent"): '$x' must be loaded together with '$r'"
    done
  done
  shopt -u nullglob
fi

while IFS= read -r -d '' p; do err "symlink not allowed: $p"; done < <(find "$DIR" -mindepth 2 -type l -print0)
while IFS= read -r -d '' p; do err "special file not allowed: $p"; done < <(find "$DIR" -mindepth 2 ! -type f ! -type d ! -type l -print0)
while IFS= read -r -d '' p; do err "empty folder not allowed: $p"; done < <(find "$DIR" -mindepth 1 -type d -empty -print0)
while IFS= read -r -d '' p; do
  case "$p" in *$'\n'*|*\\*|*[[:cntrl:]]*) err "file name with newline, backslash or control character: $(printf '%q' "$p")";; esac
done < <(find "$DIR" -mindepth 2 -print0)
[ "$fail" = 0 ] || exit 1

list() { find "$DIR" -mindepth 2 -type f -print0 | LC_ALL=C sort -z | tr '\0' '\n'; }

if [ "$MODE" = write ]; then
  : > "$SUMS"
  while IFS= read -r f; do sha256sum -- "$f" >> "$SUMS"; done < <(list)
  echo "Wrote $SUMS ($(wc -l < "$SUMS") files)"
  exit 0
fi

[ -f "$SUMS" ] || { echo "ERROR: missing $SUMS"; exit 1; }
expected=$(cut -c67- "$SUMS" | LC_ALL=C sort)
actual=$(list)
added=$(LC_ALL=C comm -13 <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") | sed '/^$/d')
removed=$(LC_ALL=C comm -23 <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") | sed '/^$/d')
[ -z "$added" ] || { echo "ERROR: files added (not in checksums):"; echo "$added"; fail=1; }
[ -z "$removed" ] || { echo "ERROR: files removed or renamed:"; echo "$removed"; fail=1; }
[ "$fail" = 0 ] || exit 1
if ! out=$(sha256sum --check --quiet -- "$SUMS" 2>&1); then echo "ERROR: changed files:"; echo "$out"; exit 1; fi
echo "Skills OK ($(wc -l < "$SUMS") files)"
