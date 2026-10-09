#!/usr/bin/env bash
# Proves a vendored third-party skill is its pinned upstream copy with lines or files DELETED and nothing else changed.
# Usage: scripts/check-skill-upstream.sh <upstream-skill-dir> <skill-name> [repo-root]
#   <upstream-skill-dir>: the skill folder from a checkout of the pinned upstream commit (see SKILLS-LOCK.md).
# It does not apply any patch. For every file it checks directly that ours adds no line to upstream's version
# (deletions only). Files only in ours: just NOTICE.md and one of UPSTREAM-LICENSE, UPSTREAM-LICENSE.md, UPSTREAM-LICENSE.txt, at the top. No symlinks anywhere.
# The record of what was removed, .claude/skills-patches/<skill-name>.diff, must equal `diff -ru` of upstream and ours
# (those top-level files left out; `diff` command lines and header timestamps ignored), so the record cannot drift.
# Any diff error (unreadable file, exit status above 1) fails the check.
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
lic=0; for n in UPSTREAM-LICENSE UPSTREAM-LICENSE.md UPSTREAM-LICENSE.txt; do [ -e "$OURS/$n" ] && [ ! -e "$UP/$n" ] && lic=$((lic+1)); done
[ "$lic" -le 1 ] || err "more than one UPSTREAM-LICENSE file"
while IFS= read -r -d '' f; do
  rel=${f#"$OURS/"}
  if [[ "$rel" != */* ]]; then                      # our additions: top-level names only
    case "$rel" in NOTICE.md|UPSTREAM-LICENSE|UPSTREAM-LICENSE.md|UPSTREAM-LICENSE.txt) [ -e "$UP/$rel" ] || continue;; esac
  fi
  if [ ! -f "$UP/$rel" ]; then err "file not in upstream: $rel"; continue; fi
  # Lines that are in ours but not in upstream (diff prints only added lines). Must be empty. -a: treat every file as text.
  rc=0; added=$(diff -a --unchanged-line-format= --old-line-format= --new-line-format='%L' "$UP/$rel" "$f") || rc=$?
  if [ "$rc" -gt 1 ]; then err "diff failed on $rel (exit $rc)"; continue; fi
  [ -z "$added" ] || { err "lines added or changed in $rel:"; printf '%s\n' "$added" | head -5; }
done < <(find "$OURS" -type f -print0)
while IFS= read -r -d '' f; do
  rel=${f#"$UP/"}; [ -f "$OURS/$rel" ] || deleted=$((deleted+1))
done < <(find "$UP" -type f -print0)
[ "$fail" = 0 ] || exit 1

# The recorded patch must be exactly today's diff (deletions only, so it has no added lines either).
PATCH="$ROOT/.claude/skills-patches/$NAME.diff"
S=$(mktemp -d "${TMPDIR:-/tmp}/su-rec.XXXXXX"); trap 'rm -rf "$S"' EXIT
cp -R "$UP" "$S/upstream"; cp -R "$OURS" "$S/ours"
norm() { sed -E -e '/^diff /d' -e 's/^((---|\+\+\+) [^	]*)	.*$/\1/'; }
rc=0; (cd "$S" && diff -ru -a -x NOTICE.md -x UPSTREAM-LICENSE -x UPSTREAM-LICENSE.md -x UPSTREAM-LICENSE.txt upstream ours) > "$S/now.diff" || rc=$?
[ "$rc" -le 1 ] || { echo "ERROR: diff of upstream and ours failed (exit $rc)"; exit 1; }
if [ ! -s "$S/now.diff" ]; then
  [ ! -s "$PATCH" ] || { echo "ERROR: $NAME.diff records changes but our copy equals upstream"; exit 1; }
else
  [ -f "$PATCH" ] || { echo "ERROR: missing record .claude/skills-patches/$NAME.diff"; exit 1; }
  if grep -qE '^\+([^+]|$)|^\+\+[^+]|^\+\+$' "$PATCH"; then echo "ERROR: $NAME.diff has added lines"; exit 1; fi
  if ! cmp -s <(norm < "$S/now.diff") <(norm < "$PATCH"); then
    echo "ERROR: .claude/skills-patches/$NAME.diff does not match diff -ru of upstream and our copy"; exit 1
  fi
fi
echo "OK: .claude/skills/$NAME = upstream with deletions only ($deleted upstream file(s) removed) + top-level NOTICE.md/UPSTREAM-LICENSE; $NAME.diff matches"
