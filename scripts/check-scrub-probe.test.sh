#!/usr/bin/env bash
# Tests scripts/check-scrub-probe.sh: it counts a token-looking value in its environment and never prints it.
set -uo pipefail
COVENV=(); [ -n "${COV_TRACE:-}" ] && COVENV=(COV_TRACE="$COV_TRACE" BASH_ENV="$BASH_ENV")   # scripts/check-coverage.sh
SCRIPT="$(cd "$(dirname "$0")" && pwd)/check-scrub-probe.sh"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-testlib.sh"
D=$(mktemp -d "${TMPDIR:-/tmp}/sp.XXXXXX"); trap 'rm -rf "$D"' EXIT; mkdir -p "$D/empty"
out=$(env -i "${COVENV[@]}" PATH=/usr/bin:/bin SCRUB_PROBE_DIRS="$D/empty" bash "$SCRIPT"); grep -q 'SCRUB-PROBE env-tokens=0 proc-tokens=0 file-tokens=0 ' <<<"$out" && { t PASS "clean environment"; } || { t FAIL "clean env: $out"; }
out=$(env -i "${COVENV[@]}" PATH=/usr/bin:/bin FAKE=sk-ant-oat01-$(printf 'T%.0s' {1..30}) SCRUB_PROBE_DIRS="$D/empty" bash "$SCRIPT"); grep -q 'SCRUB-PROBE env-tokens=1 proc-tokens=[1-9]' <<<"$out" && { t PASS "token in its environment is counted (env and its own /proc)"; } || { t FAIL "token env: $out"; }
! grep -q 'TTTTTTTT' <<<"$out" && { t PASS "never prints the token"; } || { t FAIL "printed token"; }

# A token in ANOTHER process's environment is counted (the probe must look beyond itself)
env -i FAKE="sk-ant-oat01-$(printf 'O%.0s' {1..30})" sleep 30 & other=$!
out=$(env -i "${COVENV[@]}" PATH=/usr/bin:/bin SCRUB_PROBE_DIRS="$D/empty" bash "$SCRIPT"); kill "$other" 2>/dev/null; wait "$other" 2>/dev/null
grep -q 'SCRUB-PROBE env-tokens=0 proc-tokens=[1-9]' <<<"$out" && { t PASS "token in another process is counted"; } || { t FAIL "other process: $out"; }
# A token written to a file under the scanned folders is counted (text files only; the match is never printed)
mkdir -p "$D/home/.claude" "$D/tmp/x"; printf '{"t":"sk-ant-oat01-%s"}\n' "$(printf 'F%.0s' {1..30})" > "$D/home/.claude/creds.json"; echo plain > "$D/tmp/x/a.txt"
printf 'sk-ant-api03-%s\n' "$(printf 'G%.0s' {1..30})" > "$D/tmp/x/b.log"; head -c 64 /dev/urandom > "$D/tmp/x/bin.dat"
out=$(env -i "${COVENV[@]}" PATH=/usr/bin:/bin SCRUB_PROBE_DIRS="$D/home $D/tmp $D/missing" bash "$SCRIPT")
grep -q 'file-tokens=2 ' <<<"$out" && ! grep -q 'FFFFFFFF' <<<"$out" && { t PASS "tokens in files under the scanned folders are counted, not printed"; } || { t FAIL "file tokens: $out"; }
grep -q 'env-tokens=0 proc-tokens=0 ' <<<"$out" && { t PASS "file hits do not count as environment hits"; } || { t FAIL "file vs env: $out"; }
out=$(env -i "${COVENV[@]}" PATH=/usr/bin:/bin SCRUB_PROBE_DIRS="$D/tmp/x" bash "$SCRIPT" 2>&1)
grep -q 'file-tokens=1 ' <<<"$out" && { t PASS "a short prefix alone (sk-ant-test) is not a token" ; } || { t FAIL "prefix: $out"; }
summary
