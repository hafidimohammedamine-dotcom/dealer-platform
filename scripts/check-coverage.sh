#!/usr/bin/env bash
# Runs every guard script test and measures line coverage of the guard scripts (founder-owned). Used by ci.yml.
# Usage: bash scripts/check-coverage.sh [min-percent]   (default 90; each script must reach it on its own)
#   - bash scripts: xtrace through a BASH_ENV hook into one trace file, scored by scripts/check-coverage.py;
#   - Python scripts: coverage.py (pinned with hashes in scripts/check-python-requirements.txt, installed by
#     scripts/check-python-deps.sh into a private venv without system site-packages), put in front of PATH as `python3`
#     only for the tests.
# A failing test fails this script before any coverage is reported. Rules and messages: docs/runbooks/ci-guards.md.
set -euo pipefail
MIN="${1:-90}"
[[ "$MIN" =~ ^[0-9]+$ ]] || { echo "ERROR: bad minimum percent"; exit 2; }
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
TESTS=(check-founder-files check-skills check-skill-upstream check-skill-deletions check-skills-upstream-all
       check-skills-vs-base check-skills-lib check-workflows check-egress-lock check-review-prepare check-pr-ci-status
       check-review-post check-agent-token check-scrub-probe check-claude-probe check-coverage check-coverage-sh
       check-workflows-people check-python-deps check-pushers check-main-push check-accounts-lib check-pins
       check-claude-answer
       gitleaks-config)
# COV_TESTS / COV_VENV: only for scripts/check-coverage-sh.test.sh (a small tree of its own, one shared venv).
[ -z "${COV_TESTS:-}" ] || read -r -a TESTS <<<"$COV_TESTS"
LOCK="$ROOT/.github/actions/agent-egress-lock/lock.sh"
BASH_SCRIPTS=("$LOCK")   # every guard script except the tests (this runner too: check-coverage-sh.test.sh runs copies of it)
for f in "$ROOT"/scripts/check-*.sh; do
  case "$f" in *.test.sh) ;; */check-coverage.sh) [ -n "${COV_INNER:-}" ] || BASH_SCRIPTS+=("$f");; *) BASH_SCRIPTS+=("$f");; esac
done   # a runner started by check-coverage-sh.test.sh (COV_INNER) is traced by the outer run, not by itself
PY_SCRIPTS=("$ROOT"/scripts/check-*.py)
for f in "$HERE"/*.test.sh; do   # every test file must be in TESTS, so none is silently skipped
  b=$(basename "$f" .test.sh); case " ${TESTS[*]} " in *" $b "*) ;; *) echo "ERROR: $f is not in TESTS in $0"; exit 1;; esac
done
W=$(mktemp -d "${TMPDIR:-/tmp}/cov.XXXXXX"); trap 'rm -rf "$W"' EXIT

# Python: a private venv with the pinned coverage.py and PyYAML (no system site-packages).
if [ -n "${COV_VENV:-}" ] && [ -x "$COV_VENV/bin/python" ]; then ln -s "$COV_VENV" "$W/venv"; else
  bash "$HERE/check-python-deps.sh" "$W/venv" >/dev/null
fi
# [paths]: tests that run copies of the scripts in temp folders (…/<temp>/scripts/) count for the real ones.
printf '[run]\ndata_file = %s/py.cov\nparallel = True\n[paths]\nsource =\n    %s/scripts/\n    */scripts/\n' "$W" "$ROOT" > "$W/rc"
mkdir -p "$W/bin"
cat > "$W/bin/python3" <<EOF
#!/usr/bin/env bash
# python3 for the tests: runs a .py script under coverage, anything else unchanged.
i=1; nosite=; for a in "\$@"; do case "\$a" in -S) nosite=1; i=\$((i+1));; -I|-B|-E|-s) i=\$((i+1));; *) break;; esac; done
t=\${!i:-}
if [[ "\$t" == *.py && -f "\$t" && -z "\$nosite" ]]; then   # -S (no site-packages) cannot load coverage
  exec "$W/venv/bin/python" "\${@:1:i-1}" -m coverage run --rcfile="$W/rc" "\${@:i}"; fi
exec "$W/venv/bin/python" "\$@"
EOF
chmod +x "$W/bin/python3"

# bash: every bash started by the tests traces into one file.
cat > "$W/bash-env" <<'EOF'
if [ -n "${COV_TRACE:-}" ]; then exec {__cov_fd}>>"$COV_TRACE"; BASH_XTRACEFD=$__cov_fd; PS4='+${BASH_SOURCE[0]:-?}:${LINENO}: '; set -x; fi
EOF
: > "$W/trace"

for t in "${TESTS[@]}"; do
  f="$HERE/$t.test.sh"
  [ -f "$f" ] || { echo "ERROR: missing test $f"; exit 1; }
  echo "== $t"
  # A test passes only if it exits 0 AND its last line says it ran cases and none failed.
  PATH="$W/bin:$PATH" COV_TRACE="$W/trace" BASH_ENV="$W/bash-env" COV_INNER=1 bash "$f" > "$W/out" 2>&1 && last=$(tail -n 1 "$W/out") \
    && [[ "$last" =~ ^([0-9]+)\ passed,\ 0\ failed$ && "${BASH_REMATCH[1]}" -gt 0 ]] \
    || { cat "$W/out"; echo "ERROR: $t tests failed"; exit 1; }
  echo "$last"
done

echo "== coverage (minimum $MIN% per script)"
rc=0
# Tests that run temp copies: check-egress-lock.test.sh (…/el.XXXXXX/action/lock.sh) and check-coverage-sh.test.sh
# (…/ccs.XXXXXX/t.XXXXXX/scripts/check-coverage.sh).
"$W/venv/bin/python" -I "$HERE/check-coverage.py" --alias ".*/el\.[A-Za-z0-9]+/action/lock\.sh=$LOCK" \
  --alias ".*/ccs\.[A-Za-z0-9]+/t\.[A-Za-z0-9]+/scripts/check-coverage\.sh=$HERE/check-coverage.sh" \
  "$W/trace" "$MIN" "${BASH_SCRIPTS[@]}" || rc=1
"$W/venv/bin/python" -m coverage combine --rcfile="$W/rc" -q
"$W/venv/bin/python" -m coverage report --rcfile="$W/rc" -m --include="$(IFS=,; echo "${PY_SCRIPTS[*]}")" > "$W/py.txt" || true
cat "$W/py.txt"
for p in "${PY_SCRIPTS[@]}"; do   # two decimals, so 89.6% is not rounded up to 90
  pct=$("$W/venv/bin/python" -m coverage report --rcfile="$W/rc" --include="$p" --format=total --precision=2 2>/dev/null) || pct=0
  [[ "$pct" =~ ^[0-9]+(\.[0-9]+)?$ ]] || pct=0   # "No data to report" counts as 0
  if ! awk -v p="${pct:-0}" -v m="$MIN" 'BEGIN { exit !(p + 0 >= m + 0) }'; then echo "ERROR: $p line coverage $pct% is below $MIN%"; rc=1; fi
done
[ "$rc" = 0 ] && echo "Coverage OK (every guard script at least $MIN%)"
exit "$rc"
