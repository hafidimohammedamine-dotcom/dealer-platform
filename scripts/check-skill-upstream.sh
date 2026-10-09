#!/usr/bin/env bash
# Proves a vendored third-party skill equals its upstream copy plus our recorded patch.
# Usage: scripts/check-skill-upstream.sh <upstream-skill-dir> <skill-name> [repo-root]
#   <upstream-skill-dir>: the skill folder from a checkout of the pinned upstream commit (see SKILLS-LOCK.md).
#   Applies .claude/skills-patches/<skill-name>.diff (if any) to a copy, deletes files the patch marks "Only in upstream",
#   then compares with .claude/skills/<skill-name>. Only NOTICE.md and UPSTREAM-LICENSE* may differ.
set -euo pipefail
UP="${1:?upstream skill dir}"; NAME="${2:?skill name}"; ROOT="${3:-$(cd "$(dirname "$0")/.." && pwd)}"
[[ "$NAME" =~ ^[a-z0-9][a-z0-9-]*$ ]] || { echo "ERROR: bad skill name"; exit 1; }
[ -d "$UP" ] || { echo "ERROR: upstream dir not found: $UP"; exit 1; }
OURS="$ROOT/.claude/skills/$NAME"; PATCH="$ROOT/.claude/skills-patches/$NAME.diff"
[ -d "$OURS" ] || { echo "ERROR: no skill folder $OURS"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
cp -r "$UP" "$W/upstream"
if [ -f "$PATCH" ]; then
  (cd "$W" && cp -r upstream ours && patch -s -p1 -d ours < "$PATCH")
  while IFS= read -r f; do rm -f -- "$W/ours/$f"; done < <(sed -n 's#^Only in upstream/\{0,1\}\(.*\): \(.*\)$#\1/\2#p' "$PATCH" | sed 's#^/##')
else
  cp -r "$W/upstream" "$W/ours"
fi
if out=$(diff -r -x NOTICE.md -x 'UPSTREAM-LICENSE*' "$W/ours" "$OURS"); then
  echo "OK: .claude/skills/$NAME = upstream + $( [ -f "$PATCH" ] && echo "recorded patch" || echo "no patch")"
else
  echo "ERROR: .claude/skills/$NAME differs from upstream + patch:"; echo "$out"; exit 1
fi
