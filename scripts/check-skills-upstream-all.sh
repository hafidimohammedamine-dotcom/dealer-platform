#!/usr/bin/env bash
# Runs scripts/check-skill-upstream.sh for EVERY third-party skill in the manifest, against a fresh fetch of the
# exact upstream commit pinned in SKILLS-LOCK.md. Used by the guards workflow (base-branch script, PR's .claude/ as data).
# Lock rows are read with scripts/check-skills-lib.sh, the same way scripts/check-skills.sh reads them.
# Usage: scripts/check-skills-upstream-all.sh <repo-root-with-.claude> [work-dir]
#   UPSTREAM_BASE (default https://github.com/) is only overridden by the tests (file:// fixtures).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# No filters or hooks while an upstream's files are written (NOFILTER, scripts/check-git-lib.sh).
# shellcheck source=scripts/check-git-lib.sh
. "$HERE/check-git-lib.sh"
ROOT="${1:?repo root}"; WORK="${2:-$(mktemp -d "${TMPDIR:-/tmp}/up-all.XXXXXX")}"
# shellcheck source=scripts/check-skills-lib.sh
. "$HERE/check-skills-lib.sh"
BASE="${UPSTREAM_BASE:-https://github.com/}"
S="$ROOT/.claude/skills"
[ -f "$S/manifest.txt" ] || { echo "ERROR: missing $S/manifest.txt"; exit 1; }
fail=0; n=0
while read -r name kind _; do
  [ "$kind" = third-party ] || continue
  valid_skill_name "$name" || { echo "ERROR: bad skill name '$name'"; fail=1; continue; }
  rc=0; lock_row_one "$S/SKILLS-LOCK.md" "$name" || rc=$?
  [ "$rc" = 0 ] || { echo "ERROR: $(lock_row_error "$rc" "$name")"; fail=1; continue; }
  repo=$LOCK_REPO; path=$LOCK_PATH; sha=$LOCK_SHA
  d="$WORK/$name"; rm -rf "$d"; mkdir -p "$d"
  if ! ( cd "$d" && git init -q . && git remote add origin "$BASE$repo" \
         && git -c protocol.file.allow=always "${NOFILTER[@]}" fetch -q --depth 1 --filter=blob:none origin "$sha" \
         && git sparse-checkout set --no-cone "/$path/" && git -c advice.detachedHead=false "${NOFILTER[@]}" checkout -q FETCH_HEAD \
         && [ "$(git rev-parse HEAD)" = "$sha" ] ); then
    echo "ERROR: could not fetch $repo at $sha for '$name'"; fail=1; continue
  fi
  bash "$HERE/check-skill-upstream.sh" "$d/$path" "$name" "$ROOT" || fail=1
  n=$((n+1))
done < <(manifest_entries "$S/manifest.txt")
[ "$fail" = 0 ] || exit 1
echo "Upstream check OK for $n third-party skill(s)"
