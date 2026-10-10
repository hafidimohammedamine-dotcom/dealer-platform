#!/usr/bin/env bash
# Unpacks a fetched PR ref (or a part of it) as DATA for the guards (founder-owned): `git archive` with the tree's own
# .gitattributes switched off (scripts/check-git-lib.sh: an `export-ignore` there would otherwise hide a file - a skill, a
# workflow - from the checks while the merge still brings it). Nothing of the tree runs.
# Usage: scripts/check-pr-archive.sh <ref> <dest-dir> [path]   e.g. refs/remotes/pr/head /tmp/pr-wf, or ... /tmp/pr-skills .claude
# With a path that the ref does not hold, the destination is created empty and the script says so (exit 0).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/check-git-lib.sh
. "$HERE/check-git-lib.sh"
REF="${1:?ref}"; DEST="${2:?destination}"; SUB="${3:-}"
[[ "$REF" =~ ^[A-Za-z0-9._/-]+$ ]] || { echo "ERROR: bad ref: $REF"; exit 1; }
[ -z "$SUB" ] || [[ "$SUB" =~ ^[A-Za-z0-9._-][A-Za-z0-9._/-]*$ && "$SUB" != *..* ]] || { echo "ERROR: bad path: $SUB"; exit 1; }
git rev-parse -q --verify "$REF^{commit}" >/dev/null || { echo "ERROR: ref not found: $REF"; exit 1; }
rm -rf "$DEST" && mkdir -p "$DEST"
git_no_attributes "$(git rev-parse --git-dir)"
if [ -n "$SUB" ] && ! git cat-file -e "$REF:$SUB" 2>/dev/null; then echo "PR tree has no $SUB; $DEST left empty"; exit 0; fi
if [ -n "$SUB" ]; then git archive "$REF" "$SUB" | tar -x -C "$DEST"; else git archive "$REF" | tar -x -C "$DEST"; fi
echo "PR tree${SUB:+ ($SUB)} unpacked as data into $DEST ($(find "$DEST" -type f | wc -l) files, attributes off)"
