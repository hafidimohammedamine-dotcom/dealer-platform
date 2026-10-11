#!/usr/bin/env bash
# Tests the coverage runner scripts/check-coverage.sh on a small tree of its own: argument check, the test list, failing
# and missing tests, the python3 shim, and the per-script minimum for bash and Python (with decimals).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
TMPROOT="${TMPDIR:-/tmp}"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-testlib.sh"
W=$(mktemp -d "$TMPROOT/ccs.XXXXXX") || exit 2; trap 'rm -rf "$W"' EXIT
bash "$HERE/check-python-deps.sh" "$W/venv" >/dev/null || { echo "ERROR: cannot set up coverage.py"; exit 2; }
tree() { # a fresh tree: scripts/check-a.sh (bash), scripts/check-b.py (Python), each with a test that runs both branches
  T=$(mktemp -d "$W/t.XXXXXX"); mkdir -p "$T/scripts" "$T/.github/actions/agent-egress-lock"
  # check-python-deps.sh stays out: the inner runner reuses this test's venv (COV_VENV), so it would never run there.
  cp "$HERE/check-coverage.sh" "$HERE/check-coverage.py" "$HERE/check-coverage.test.sh" "$HERE/check-python-requirements.txt" "$HERE/check-testlib.sh" "$T/scripts/"
  printf '#!/usr/bin/env bash\necho lock\n' > "$T/.github/actions/agent-egress-lock/lock.sh"
  printf '#!/usr/bin/env bash\nif [ "${1:-}" = x ]; then\n  echo x\nelse\n  echo y\nfi\n' > "$T/scripts/check-a.sh"
  printf 'import sys\nif len(sys.argv) > 1:\n    print("x")\nelse:\n    print("y")\n' > "$T/scripts/check-b.py"
  # check-a's test uses the shared test library (so check-testlib.sh is measured and covered in this tree too)
  printf '#!/usr/bin/env bash\nD=$(cd "$(dirname "$0")" && pwd)\n. "$D/check-testlib.sh"\ncheck "x" bash "$D/check-a.sh" x; check "y" bash "$D/check-a.sh"\nassert_result ok 0 "r" "" ""; assert_result fail 0 "r2" "" "" >/dev/null; failed=0\nS=$(mktemp -d); write_gh_stub "$S"; "$S/gh" api user --jq "\\(.id) \\(.login)" >/dev/null; "$S/gh" nothing >/dev/null 2>&1; STUB_GH_LOG="$S/log" "$S/gh" repos/owner/repo/commits/HEAD >/dev/null 2>&1; echo "case x in esac" > "$S/gh-extra"; STUB_COUNT="$S/c" "$S/gh" api "repos/owner/repo/actions/workflows/main-guard.yml/runs?head_sha=x" >/dev/null; STUB_RUNS_LATER=y STUB_COUNT="$S/c" "$S/gh" api "repos/owner/repo/actions/workflows/main-guard.yml/runs?head_sha=x" >/dev/null; "$S/gh" api repos/owner/repo/compare/a...b --jq .status >/dev/null; rep 2 x >/dev/null; echo t | mk_exec "$S/e.json"; handoff_text "ab" >/dev/null; write_gitleaks_stub "$S"; echo x > "$S/f"; GL_RC=0 "$S/gitleaks" --source="$S" >/dev/null; assert_no_token n "clean" tok; assert_no_token n "has tok" tok >/dev/null; failed=0; rm -rf "$S"\nbash "$D/../.github/actions/agent-egress-lock/lock.sh"\nsummary\n' > "$T/scripts/check-a.test.sh"
  printf '#!/usr/bin/env bash\nD=$(cd "$(dirname "$0")" && pwd)\npython3 -I "$D/check-b.py" x; python3 -I "$D/check-b.py"\necho "1 passed, 0 failed"\n' > "$T/scripts/check-b.test.sh"
}
run() { # run <ok|fail> <name> <message> [args...]   (COV_TESTS from the caller's environment)
  local want=$1 name=$2 msg=$3; shift 3
  out=$(env COV_INNER=1 COV_VENV="$W/venv" COV_TESTS="${TESTS-check-a check-b check-coverage}" bash "$T/scripts/check-coverage.sh" "$@" 2>&1); rc=$?
  assert_result "$want" "$rc" "$name" "$msg" "$out"; }
tree; run ok   "full coverage passes" "Coverage OK (every guard script at least 90%)"
tree; run fail "bad minimum" "bad minimum percent" ninety
tree; printf '#!/usr/bin/env bash\necho "0 passed, 1 failed"; exit 1\n' > "$T/scripts/check-c.test.sh"; TESTS= run fail "every test file runs (a new failing one is not skipped)" "ERROR: check-c tests failed"
tree; TESTS="check-a check-b check-coverage check-zz" run fail "a test in COV_TESTS that does not exist" "missing test"
tree; rm "$T"/scripts/*.test.sh; TESTS= run fail "no test files at all" "no scripts/*.test.sh found"
tree; printf '#!/usr/bin/env bash\necho "0 passed, 1 failed"; exit 1\n' > "$T/scripts/check-b.test.sh"; run fail "a failing test stops the run" "ERROR: check-b tests failed"
tree; sed -i 's/bash "$D\/check-a.sh" x; //' "$T/scripts/check-a.test.sh"; run fail "bash script below the minimum" "check-a.sh  <-- below minimum"
tree; sed -i 's/python3 -I "$D\/check-b.py" x; //' "$T/scripts/check-b.test.sh"; run fail "Python script below the minimum" "check-b.py line coverage 75.00% is below 90%"
tree; rm "$T/scripts/check-b.test.sh"; TESTS="check-a check-coverage" run fail "Python script no test runs counts as 0%" "check-b.py line coverage 0% is below 90%"
# 26 of 29 statements = 89.66%: an integer compare would show 90 and pass; the two-decimal compare must fail at 90.
pyfile() { { printf 'import sys\n'; for i in $(seq 1 24); do printf 'a%s = %s\n' "$i" "$i"; done
  printf 'if len(sys.argv) > 5:\n    x = 1\n    y = 2\n    print(x + y)\n'; } > "$T/scripts/check-b.py"; }
tree; pyfile; run fail "decimal compare: 89.66% is below 90" "check-b.py line coverage 89.66% is below 90%" 90
tree; pyfile; run ok   "decimal compare: 89.66% passes 89" "Coverage OK" 89
# A test passes only with a clean summary line: failures printed, no summary, or zero cases all fail the runner
BT='#!/usr/bin/env bash\nD=$(cd "$(dirname "$0")" && pwd)\npython3 -I "$D/check-b.py" x; python3 -I "$D/check-b.py"\n'
tree; printf "$BT"'echo "1 passed, 7 failed"\n' > "$T/scripts/check-b.test.sh"; run fail "a test that prints failures but exits 0" "ERROR: check-b tests failed"
tree; printf "$BT" > "$T/scripts/check-b.test.sh";                                    run fail "a test that prints no summary line" "ERROR: check-b tests failed"
tree; printf "$BT"'echo "0 passed, 0 failed"\n' > "$T/scripts/check-b.test.sh";       run fail "a test that ran zero cases" "ERROR: check-b tests failed"
# lock.sh stays in the measured set, and the coverage.py install stays hash-pinned
tree; sed -i '/agent-egress-lock\/lock.sh/d' "$T/scripts/check-a.test.sh";            run fail "lock.sh run by no test is below the minimum" "lock.sh  <-- below minimum"
if grep -q -- 'check-python-deps.sh' "$HERE/check-coverage.sh" && grep -q -- '--require-hashes' "$HERE/check-python-deps.sh" && ! grep -q -- '--system-site-packages' "$HERE/check-coverage.sh" "$HERE/check-python-deps.sh"; then
  t PASS "the runner installs through check-python-deps.sh (hash-pinned, no system site-packages)"
else t FAIL "coverage.py install is not hash-pinned through check-python-deps.sh"; fi
summary
