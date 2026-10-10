#!/usr/bin/env bash
# Installs the guard scripts' Python packages (scripts/check-python-requirements.txt, hash-pinned) into a private venv with
# no system site-packages, and prints the venv's bin folder (founder-owned). guards.yml and ci.yml add that folder to PATH
# before the checks, so `python3` there is the venv's; scripts/check-coverage.sh uses it for its venv.
# Usage: scripts/check-python-deps.sh [venv-dir]   (default ${TMPDIR:-/tmp}/guard-venv; a venv that is already set up is reused)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REQS="${CHECK_PY_REQS:-$HERE/check-python-requirements.txt}"
DIR="${1:-${TMPDIR:-/tmp}/guard-venv}"
[[ "$DIR" == /* ]] || { echo "ERROR: venv dir must be an absolute path: $DIR" >&2; exit 2; }
[ -f "$REQS" ] || { echo "ERROR: requirements file not found: $REQS" >&2; exit 1; }
if [ ! -f "$DIR/.guard-deps-ok" ] || ! cmp -s "$REQS" "$DIR/.guard-deps-ok"; then
  rm -rf "$DIR"
  python3 -m venv "$DIR" >/dev/null || { echo "ERROR: could not create the venv at $DIR" >&2; exit 1; }
  "$DIR/bin/python" -m pip install -q --disable-pip-version-check --require-hashes --no-deps -r "$REQS" >/dev/null \
    || { rm -rf "$DIR"; echo "ERROR: could not install the pinned Python packages from $REQS (hashes must match the pinned wheels)" >&2; exit 1; }
  cp "$REQS" "$DIR/.guard-deps-ok"
fi
echo "$DIR/bin"
