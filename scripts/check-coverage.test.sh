#!/usr/bin/env bash
# Tests scripts/check-coverage.py (how bash commands are split and scored) on small fixture scripts.
set -uo pipefail
PY="$(cd "$(dirname "$0")" && pwd)/check-coverage.py"
TMPROOT="${TMPDIR:-/tmp}"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-testlib.sh"
W=$(mktemp -d "$TMPROOT/cc.XXXXXX") || exit 2
trap 'rm -rf "$W"' EXIT
cat > "$W/env" <<'E2'
if [ -n "${COV_TRACE:-}" ]; then exec {__cov_fd}>>"$COV_TRACE"; BASH_XTRACEFD=$__cov_fd; PS4='+${BASH_SOURCE[0]:-?}:${LINENO}: '; set -x; fi
E2
score() { # score <name> <expected "ran/total"> <expected rc> <script text> [args for the script]
  local name=$1 want=$2 wrc=$3 text=$4; shift 4
  printf '%s\n' "$text" > "$W/s.sh"; : > "$W/trace"
  env -u COV_TRACE -u BASH_ENV COV_TRACE="$W/trace" BASH_ENV="$W/env" bash "$W/s.sh" "$@" >/dev/null 2>&1 || true
  out=$(env -u BASH_ENV python3 -I "$PY" "$W/trace" 90 "$W/s.sh" 2>&1); rc=$?
  if [ "$rc" = "$wrc" ] && grep -qE "^ *[0-9.]+% +${want%/*}/${want#*/} " <<<"$out"; then t PASS "$name"
  else t FAIL "$name (rc=$rc, want $want)"; echo "$out"; fi; }
score "every command run" 3/3 0 $'#!/usr/bin/env bash\n# comment\nx=1\n\necho "$x"\ntrue'
score "multi-line commands count once (pipe, quotes, \\, \$( ))" 4/4 0 $'x=$(echo a |\n  tr a b)\nawk \'\n{print}\n\' <<<"$x"\necho a \\\n  b\ny="$(echo "\n")"'
score "here-document bodies are not commands" 1/1 0 $'cat <<EOT >/dev/null\nnot a command\n  echo nope\nEOT'
score "structural lines are not counted" 3/3 0 $'f() {  # a comment\n  echo in\n}\nif true; then\n  f\nfi  # done'
score "a branch not taken is reported" 2/3 1 $'if false; then\n  echo never\nfi\necho end'
score "case patterns without commands are not counted" 2/3 1 $'case a in\n  a) echo A;;\n  b) ;;\n  *) echo other;;\nesac'
score "functions never called are reported" 1/2 1 $'f() { echo x; }\necho y'
printf 'echo a\necho b\n' > "$W/real.sh"; mkdir -p "$W/copy.x1"; cp "$W/real.sh" "$W/copy.x1/real.sh"; : > "$W/trace"
COV_TRACE="$W/trace" BASH_ENV="$W/env" bash "$W/copy.x1/real.sh" >/dev/null 2>&1
out=$(python3 -I "$PY" --alias ".*/copy\.[a-z0-9]+/real\.sh=$W/real.sh" "$W/trace" 90 "$W/real.sh" 2>&1); rc=$?
[ "$rc" = 0 ] && grep -qE "100.0% +2/2 " <<<"$out" && { t PASS "--alias counts a temp copy for the real script"; } || { t FAIL "--alias"; echo "$out"; }
out=$(python3 -I "$PY" "$W/trace" 90 "$W/real.sh" 2>&1); rc=$?
[ "$rc" = 1 ] && grep -qE "0.0% +0/2 " <<<"$out" && { t PASS "without --alias the copy does not count"; } || { t FAIL "no alias"; echo "$out"; }
out=$(python3 -I "$PY" "$W/trace" ninety "$W/real.sh" 2>&1); rc=$?
[ "$rc" = 2 ] && grep -q usage <<<"$out" && { t PASS "bad minimum is a usage error"; } || { t FAIL "bad minimum"; }
out=$(python3 -I "$PY" 2>&1); rc=$?
[ "$rc" = 2 ] && grep -q usage <<<"$out" && { t PASS "usage error"; } || { t FAIL "usage error"; }
summary
