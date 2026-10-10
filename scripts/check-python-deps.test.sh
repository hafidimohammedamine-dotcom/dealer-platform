#!/usr/bin/env bash
# Tests scripts/check-python-deps.sh: a hash-pinned venv is created once and reused, and every failure is reported.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; SCRIPT="$HERE/check-python-deps.sh"
TMPROOT="${TMPDIR:-/tmp}"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-testlib.sh"
W=$(mktemp -d "$TMPROOT/pd.XXXXXX") || exit 2; trap 'rm -rf "$W"' EXIT
out=$(bash "$SCRIPT" "$W/v" 2>&1); rc=$?
[ $rc = 0 ] && [ "$out" = "$W/v/bin" ] && "$W/v/bin/python" -c 'import yaml, coverage' 2>/dev/null && t PASS "venv created with PyYAML and coverage.py, bin path printed" || { t FAIL "venv created ($rc)"; echo "$out"; }
"$W/v/bin/python" -c 'import sys; sys.exit(0 if not any("site-packages" in p and "/v/" not in p for p in sys.path) else 1)' && t PASS "no system site-packages in the venv" || t FAIL "system site-packages leaked in"
m1=$(stat -c %Y "$W/v/.guard-deps-ok"); sleep 1
out=$(bash "$SCRIPT" "$W/v" 2>&1); rc=$?
[ $rc = 0 ] && [ "$out" = "$W/v/bin" ] && [ "$(stat -c %Y "$W/v/.guard-deps-ok")" = "$m1" ] && t PASS "a set-up venv is reused, not rebuilt" || t FAIL "reuse"
printf 'coverage==7.16.2 --hash=sha256:%s\n' "$(printf 'a%.0s' {1..64})" > "$W/bad.txt"
out=$(CHECK_PY_REQS="$W/bad.txt" bash "$SCRIPT" "$W/v2" 2>&1); rc=$?
[ $rc = 1 ] && grep -q "could not install the pinned Python packages" <<<"$out" && [ ! -f "$W/v2/.guard-deps-ok" ] && t PASS "a wrong hash fails the install and leaves no marker" || { t FAIL "wrong hash ($rc)"; echo "$out"; }
out=$(CHECK_PY_REQS="$W/bad.txt" bash "$SCRIPT" "$W/v" 2>&1); rc=$?
[ $rc = 1 ] && [ ! -d "$W/v" ] && t PASS "changed requirements rebuild the venv (and a failed rebuild leaves none)" || t FAIL "rebuild on change ($rc)"
out=$(CHECK_PY_REQS="$W/none.txt" bash "$SCRIPT" "$W/v3" 2>&1); rc=$?
[ $rc = 1 ] && grep -q "requirements file not found" <<<"$out" && t PASS "missing requirements file" || t FAIL "missing requirements ($rc)"
out=$(bash "$SCRIPT" relative/dir 2>&1); rc=$?
[ $rc = 2 ] && grep -q "must be an absolute path" <<<"$out" && t PASS "relative venv dir rejected" || t FAIL "relative dir ($rc)"
out=$(PATH="$W/nopy:$PATH" bash -c 'mkdir -p "$0"; printf "#!/bin/sh\nexit 1\n" > "$0/python3"; chmod +x "$0/python3"; bash "$1" "$2"' "$W/nopy" "$SCRIPT" "$W/v4" 2>&1); rc=$?
[ $rc = 1 ] && grep -q "could not create the venv" <<<"$out" && t PASS "venv creation failure reported" || { t FAIL "venv failure ($rc)"; echo "$out"; }
grep -vE '^(#|[[:space:]]*$|[[:space:]]+--hash=|[a-z0-9_.-]+==[0-9.]+ \\$)' "$HERE/check-python-requirements.txt" | grep -q . && t FAIL "every requirement carries hashes" || t PASS "every requirement line is pinned with hashes"
summary
