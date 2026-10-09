#!/usr/bin/env bash
# Proves a vendored third-party skill is its pinned upstream copy with lines or files DELETED and nothing else changed.
# Usage: scripts/check-skill-upstream.sh <upstream-skill-dir> <skill-name> [repo-root]
#   <upstream-skill-dir>: the skill folder from a checkout of the pinned upstream commit (see SKILLS-LOCK.md).
# It does not apply any patch. For every file it checks directly that ours adds no line to upstream's version
# (deletions only). Files only in ours: just NOTICE.md and UPSTREAM-LICENSE* at the top. No symlinks anywhere.
# The human-readable record of what was removed is .claude/skills-patches/<skill-name>.diff.
set -euo pipefail
UP="${1:?upstream skill dir}"; NAME="${2:?skill name}"; ROOT="${3:-$(cd "$(dirname "$0")/.." && pwd)}"
[[ "$NAME" =~ ^[a-z0-9][a-z0-9-]*$ ]] || { echo "ERROR: bad skill name"; exit 1; }
[ -d "$UP" ] || { echo "ERROR: upstream dir not found: $UP"; exit 1; }
OURS="$ROOT/.claude/skills/$NAME"
[ -d "$OURS" ] || { echo "ERROR: no skill folder $OURS"; exit 1; }
fail=0; err() { echo "ERROR: $*"; fail=1; }

for d in "$UP" "$OURS"; do
  while IFS= read -r -d '' p; do err "not a regular file or folder: $p"; done < <(find "$d" ! -type f ! -type d -print0)
done
[ "$fail" = 0 ] || exit 1

deleted=0
while IFS= read -r -d '' f; do
  rel=${f#"$OURS/"}
  case "$rel" in
    NOTICE.md|UPSTREAM-LICENSE*) [ -f "$UP/$rel" ] || continue;;   # our top-level additions
  esac
  if [ ! -f "$UP/$rel" ]; then err "file not in upstream: $rel"; continue; fi
  # Lines that are in ours but not in upstream (diff prints only added lines). Must be empty.
  added=$(diff --unchanged-line-format= --old-line-format= --new-line-format='%L' "$UP/$rel" "$f" || true)
  [ -z "$added" ] || { err "lines added or changed in $rel:"; printf '%s\n' "$added" | head -5; }
done < <(find "$OURS" -type f -print0)
while IFS= read -r -d '' f; do
  rel=${f#"$UP/"}; [ -f "$OURS/$rel" ] || deleted=$((deleted+1))
done < <(find "$UP" -type f -print0)
[ "$fail" = 0 ] || exit 1
echo "OK: .claude/skills/$NAME = upstream with deletions only ($deleted upstream file(s) removed) + top-level NOTICE.md/UPSTREAM-LICENSE*"
