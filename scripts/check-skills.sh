#!/usr/bin/env bash
# Checks .claude/skills against its manifest and checksums.
#   .claude/skills/manifest.txt     one skill folder per line: "<name> <ours|third-party>"
#   .claude/skills/checksums.sha256 sha256 of every file under the skill folders
# Fails on: folders not in the manifest, manifest entries with no folder, symlinks, special files, empty folders,
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

declare -A listed=()
while read -r name kind rest; do
  [ -z "${name:-}" ] && continue
  case "$name" in \#*) continue;; esac
  case "$kind" in ours|third-party) ;; *) err "manifest line for '$name' needs kind 'ours' or 'third-party'";; esac
  [[ "$name" =~ ^[a-z0-9][a-z0-9-]*$ ]] || err "bad skill name in manifest: '$name'"
  listed["$name"]=1
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
