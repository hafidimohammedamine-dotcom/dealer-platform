#!/usr/bin/env bash
# Proves a vendored third-party skill equals its upstream copy plus our recorded DELETION-ONLY patch.
# Usage: scripts/check-skill-upstream.sh <upstream-skill-dir> <skill-name> [repo-root]
#   <upstream-skill-dir>: the skill folder from a checkout of the pinned upstream commit (see SKILLS-LOCK.md).
# Checks: the patch only removes lines or whole upstream files; upstream + patch + our top-level NOTICE.md and
# UPSTREAM-LICENSE* equals .claude/skills/<skill-name> exactly (no exclusions at any depth).
set -euo pipefail
UP="${1:?upstream skill dir}"; NAME="${2:?skill name}"; ROOT="${3:-$(cd "$(dirname "$0")/.." && pwd)}"
[[ "$NAME" =~ ^[a-z0-9][a-z0-9-]*$ ]] || { echo "ERROR: bad skill name"; exit 1; }
[ -d "$UP" ] || { echo "ERROR: upstream dir not found: $UP"; exit 1; }
OURS="$ROOT/.claude/skills/$NAME"; PATCH="$ROOT/.claude/skills-patches/$NAME.diff"
[ -d "$OURS" ] || { echo "ERROR: no skill folder $OURS"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
cp -r "$UP" "$W/ours"

# Our added files may only sit at the top of the skill folder.
deep=$(find "$OURS" -mindepth 2 \( -name NOTICE.md -o -name 'UPSTREAM-LICENSE*' \) -print)
[ -z "$deep" ] || { echo "ERROR: NOTICE.md / UPSTREAM-LICENSE* below the top of the folder:"; echo "$deep"; exit 1; }

if [ -f "$PATCH" ]; then
  added=$(grep -nE '^\+' "$PATCH" | grep -vE '^[0-9]+:\+\+\+ ' || true)
  [ -z "$added" ] || { echo "ERROR: the patch adds lines (it must only delete):"; echo "$added"; exit 1; }
  grep -qE '^Only in ours' "$PATCH" && { echo "ERROR: the patch adds files (it must only delete)"; exit 1; }
  (cd "$W" && patch -s -p1 -d ours < "$PATCH")
  while IFS= read -r rel; do
    case "/$rel/" in */../*|*/./*) echo "ERROR: unsafe path in patch: $rel"; exit 1;; esac
    [[ "$rel" != /* && -n "$rel" ]] || { echo "ERROR: unsafe path in patch: $rel"; exit 1; }
    target=$(realpath -m "$W/ours/$rel")
    [[ "$target" == "$W/ours/"* ]] || { echo "ERROR: path escapes the skill folder: $rel"; exit 1; }
    rm -f -- "$target"
  done < <(sed -n 's#^Only in upstream/\{0,1\}\(.*\): \(.*\)$#\1/\2#p' "$PATCH" | sed 's#^/##')
fi
cp "$OURS/NOTICE.md" "$W/ours/NOTICE.md" 2>/dev/null || true
for f in "$OURS"/UPSTREAM-LICENSE*; do [ -e "$f" ] && cp "$f" "$W/ours/"; done
if out=$(diff -r "$W/ours" "$OURS"); then
  echo "OK: .claude/skills/$NAME = upstream + $( [ -f "$PATCH" ] && echo "deletion-only patch" || echo "no patch") + top-level NOTICE/license"
else
  echo "ERROR: .claude/skills/$NAME differs from upstream + patch:"; echo "$out"; exit 1
fi
