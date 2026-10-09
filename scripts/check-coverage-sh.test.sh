#!/usr/bin/env bash
# Tests the coverage runner scripts/check-coverage.sh on a small tree of its own: argument check, the TESTS list, failing
# and missing tests, the python3 shim, and the per-script minimum for bash and Python (with decimals).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
TMPROOT="${TMPDIR:-/tmp}"
pass=0; failed=0
W=$(mktemp -d "$TMPROOT/ccs.XXXXXX") || exit 2; trap 'rm -rf "$W"' EXIT
python3 -m venv --system-site-packages "$W/venv" >/dev/null && "$W/venv/bin/python" -m pip install -q --disable-pip-version-check \
  --require-hashes --no-deps -r "$HERE/check-coverage-requirements.txt" >/dev/null || { echo "ERROR: cannot set up coverage.py"; exit 2; }
tree() { # a fresh tree: scripts/check-a.sh (bash), scripts/check-b.py (Python), each with a test that runs both branches
  T=$(mktemp -d "$W/t.XXXXXX"); mkdir -p "$T/scripts" "$T/.github/actions/agent-egress-lock"
  cp "$HERE/check-coverage.sh" "$HERE/check-coverage.py" "$HERE/check-coverage.test.sh" "$HERE/check-coverage-requirements.txt" "$T/scripts/"
  printf '#!/usr/bin/env bash\necho lock\n' > "$T/.github/actions/agent-egress-lock/lock.sh"
  printf '#!/usr/bin/env bash\nif [ "${1:-}" = x ]; then\n  echo x\nelse\n  echo y\nfi\n' > "$T/scripts/check-a.sh"
  printf 'import sys\nif len(sys.argv) > 1:\n    print("x")\nelse:\n    print("y")\n' > "$T/scripts/check-b.py"
  printf '#!/usr/bin/env bash\nD=$(cd "$(dirname "$0")" && pwd)\nbash "$D/check-a.sh" x; bash "$D/check-a.sh"\nbash "$D/../.github/actions/agent-egress-lock/lock.sh"\necho "1 passed, 0 failed"\n' > "$T/scripts/check-a.test.sh"
  printf '#!/usr/bin/env bash\nD=$(cd "$(dirname "$0")" && pwd)\npython3 -I "$D/check-b.py" x; python3 -I "$D/check-b.py"\necho "1 passed, 0 failed"\n' > "$T/scripts/check-b.test.sh"
}
run() { # run <ok|fail> <name> <message> [args...]   (COV_TESTS from the caller's environment)
  local want=$1 name=$2 msg=$3; shift 3
  out=$(env COV_INNER=1 COV_VENV="$W/venv" COV_TESTS="${TESTS:-check-a check-b check-coverage}" bash "$T/scripts/check-coverage.sh" "$@" 2>&1); rc=$?
  got=$([ $rc = 0 ] && echo ok || echo fail)
  if [ "$got" = "$want" ] && grep -qF -- "$msg" <<<"$out"; then pass=$((pass+1)); echo "PASS  $name"; else failed=$((failed+1)); echo "FAIL  $name ($got)"; echo "$out" | tail -n 12; fi; }
tree; run ok   "full coverage passes" "Coverage OK (every guard script at least 90%)"
tree; run fail "bad minimum" "bad minimum percent" ninety
tree; printf 'echo hi\n' > "$T/scripts/check-c.test.sh"; run fail "a test file not in TESTS" "check-c.test.sh is not in TESTS"
tree; TESTS="check-a check-b check-coverage check-zz" run fail "a test in TESTS that does not exist" "missing test"
tree; printf '#!/usr/bin/env bash\necho "0 passed, 1 failed"; exit 1\n' > "$T/scripts/check-b.test.sh"; run fail "a failing test stops the run" "ERROR: check-b tests failed"
tree; sed -i 's/bash "$D\/check-a.sh" x; //' "$T/scripts/check-a.test.sh"; run fail "bash script below the minimum" "check-a.sh  <-- below minimum"
tree; sed -i 's/python3 -I "$D\/check-b.py" x; //' "$T/scripts/check-b.test.sh"; run fail "Python script below the minimum" "check-b.py line coverage 75.00% is below 90%"
tree; rm "$T/scripts/check-b.test.sh"; TESTS="check-a check-coverage" run fail "Python script no test runs counts as 0%" "check-b.py line coverage 0% is below 90%"
# 19 of 20 statements = 95.00%; with a minimum of 96 the decimal compare must fail (95 would round to 95, 95.5 to 96).
tree; { printf 'import sys\n'; for i in $(seq 1 17); do printf 'a%s = %s\n' "$i" "$i"; done; printf 'if len(sys.argv) > 5:\n    print("never")\n'; } > "$T/scripts/check-b.py"
run fail "decimal compare: 95.00%% is below 96" "check-b.py line coverage 95.00% is below 96%" 96
tree; { printf 'import sys\n'; for i in $(seq 1 17); do printf 'a%s = %s\n' "$i" "$i"; done; printf 'if len(sys.argv) > 5:\n    print("never")\n'; } > "$T/scripts/check-b.py"
run ok   "decimal compare: 95.00%% passes 95" "Coverage OK" 95
echo "$pass passed, $failed failed"
[ "$failed" = 0 ]
