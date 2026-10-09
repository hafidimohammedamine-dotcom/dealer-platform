#!/usr/bin/env bash
# Proves a vendored third-party skill is its pinned upstream copy with lines or files DELETED and nothing else changed.
# Usage: scripts/check-skill-upstream.sh <upstream-skill-dir> <skill-name> [repo-root]
#   <upstream-skill-dir>: the skill folder from a checkout of the pinned upstream commit (see SKILLS-LOCK.md).
# Checks, failing closed (any diff error fails):
#  1. No symlinks or special files on either side.
#  2. Every file in ours exists upstream and adds no line to it (deletions only). The only files ours may add are the
#     top-level names in EXTRA below (at most one UPSTREAM-LICENSE*).
#  3. Deletions must not turn a warning into advice: a removed line may not contain a warning word (WARN_RE), and a fenced
#     code block (``` ... ```) is either kept whole or removed whole. Whole files may be removed.
#  4. The record .claude/skills-patches/<skill-name>.diff equals today's `diff -ru` of upstream and ours (EXTRA files left
#     out; `diff` command lines and header timestamps ignored), so the record cannot drift.
set -euo pipefail
EXTRA=(NOTICE.md UPSTREAM-LICENSE UPSTREAM-LICENSE.md UPSTREAM-LICENSE.txt)
WARN_RE='❌|⚠|WRONG|SECURITY|BUG|[Nn]ever|NEVER|[Mm]ust|MUST|[Nn]ot\b|NOT\b|[Dd]on.t|[Aa]void|[Ww]arning|WARNING|[Dd]anger|[Bb]ypass|[Uu]nsafe|[Ii]nsecure'
UP="${1:?upstream skill dir}"; NAME="${2:?skill name}"; ROOT="${3:-$(cd "$(dirname "$0")/.." && pwd)}"
[[ "$NAME" =~ ^[a-z0-9][a-z0-9-]*$ ]] || { echo "ERROR: bad skill name"; exit 1; }
[ -d "$UP" ] || { echo "ERROR: upstream dir not found: $UP"; exit 1; }
OURS="$ROOT/.claude/skills/$NAME"
[ -d "$OURS" ] || { echo "ERROR: no skill folder $OURS"; exit 1; }
fail=0; err() { echo "ERROR: $*"; fail=1; }
is_extra() { local x; for x in "${EXTRA[@]}"; do [ "$1" = "$x" ] && return 0; done; return 1; }

for d in "$UP" "$OURS"; do
  while IFS= read -r -d '' p; do err "not a regular file or folder: $p"; done < <(find "$d" ! -type f ! -type d -print0)
done
[ "$fail" = 0 ] || exit 1

lic=0; for x in "${EXTRA[@]}"; do case "$x" in UPSTREAM-LICENSE*) [ -e "$OURS/$x" ] && [ ! -e "$UP/$x" ] && lic=$((lic+1));; esac; done
[ "$lic" -le 1 ] || err "more than one UPSTREAM-LICENSE file"

while IFS= read -r -d '' f; do
  rel=${f#"$OURS/"}
  if [[ "$rel" != */* ]] && is_extra "$rel" && [ ! -e "$UP/$rel" ]; then continue; fi   # our top-level additions
  if [ ! -f "$UP/$rel" ]; then err "file not in upstream: $rel"; continue; fi
  # Added lines (in ours, not upstream) must be none. -a: treat every file as text.
  rc=0; added=$(diff -a --unchanged-line-format= --old-line-format= --new-line-format='%L' "$UP/$rel" "$f") || rc=$?
  if [ "$rc" -gt 1 ]; then err "diff failed on $rel (exit $rc)"; continue; fi
  [ -z "$added" ] || { err "lines added or changed in $rel:"; printf '%s\n' "$added" | head -5; continue; }
  # Removed lines, as "<upstream line number> <text>".
  removed=$(diff -a --unchanged-line-format= --new-line-format= --old-line-format='%dn %L' "$UP/$rel" "$f" || true)
  [ -n "$removed" ] || continue
  if w=$(cut -d' ' -f2- <<<"$removed" | grep -E -m1 -- "$WARN_RE"); then err "removed a warning line in $rel: $w"; fi
  partial=$(awk 'NR==FNR { gone[$1]=1; next }
    /^[[:space:]]*```/ { if (!inb) { inb=1; s=FNR; all=1; any=0 } else { inb=0; if (gone[FNR]) any=1; else all=0;
                         if (gone[s]) any=1; else all=0; if (any && !all) print s; } next }
    inb { if (gone[FNR]) any=1; else all=0 }' <(printf '%s\n' "$removed") "$UP/$rel")
  [ -z "$partial" ] || err "part of a code block removed in $rel (block at upstream line $(head -n1 <<<"$partial")); keep it whole or remove it whole"
done < <(find "$OURS" -type f -print0)
deleted=0
while IFS= read -r -d '' f; do
  rel=${f#"$UP/"}; [ -f "$OURS/$rel" ] || deleted=$((deleted+1))
done < <(find "$UP" -type f -print0)
[ "$fail" = 0 ] || exit 1

# The recorded patch must be exactly today's diff (deletions only, so it has no added lines either).
PATCH="$ROOT/.claude/skills-patches/$NAME.diff"
S=$(mktemp -d "${TMPDIR:-/tmp}/su-rec.XXXXXX"); trap 'rm -rf "$S"' EXIT
cp -R "$UP" "$S/upstream"; cp -R "$OURS" "$S/ours"
xargs_=(); for x in "${EXTRA[@]}"; do xargs_+=(-x "$x"); done
norm() { sed -E -e '/^diff /d' -e 's/^((---|\+\+\+) [^	]*)	.*$/\1/'; }
rc=0; (cd "$S" && diff -ru -a "${xargs_[@]}" upstream ours) > "$S/now.diff" || rc=$?
[ "$rc" -le 1 ] || { echo "ERROR: diff of upstream and ours failed (exit $rc)"; exit 1; }
if [ ! -s "$S/now.diff" ]; then
  [ ! -s "$PATCH" ] || { echo "ERROR: $NAME.diff records changes but our copy equals upstream"; exit 1; }
else
  [ -s "$PATCH" ] || { echo "ERROR: missing or empty record .claude/skills-patches/$NAME.diff"; exit 1; }
  if grep -qE '^\+([^+]|$)|^\+\+[^+]|^\+\+$' "$PATCH"; then echo "ERROR: $NAME.diff has added lines"; exit 1; fi
  if ! cmp -s <(norm < "$S/now.diff") <(norm < "$PATCH"); then
    echo "ERROR: .claude/skills-patches/$NAME.diff does not match diff -ru of upstream and our copy"; exit 1
  fi
fi
echo "OK: .claude/skills/$NAME = upstream with deletions only ($deleted upstream file(s) removed) + top-level NOTICE.md/UPSTREAM-LICENSE; $NAME.diff matches"
