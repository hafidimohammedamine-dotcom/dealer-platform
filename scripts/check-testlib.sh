#!/usr/bin/env bash
# Shared bookkeeping for every scripts/*.test.sh (founder-owned): sourced, never run. A test file counts its cases with
# `t PASS|FAIL <name>` (or `check <name> <command...>`, `assert_result`), and ends with `summary`, whose last line
# "<n> passed, <m> failed" is what scripts/check-coverage.sh reads (a test passes only with 0 failed and n > 0).
pass=0; failed=0
t() { if [ "$1" = PASS ]; then pass=$((pass+1)); else failed=$((failed+1)); fi; echo "$1  $2"; }
check() { # check <name> <command...>: passes when the command succeeds
  local name=$1; shift
  if "$@"; then t PASS "$name"; else t FAIL "$name"; fi; }
assert_result() { # assert_result <ok|fail> <rc> <name> <message> <output>: the exit code class and a message substring
  local got; got=$([ "$2" = 0 ] && echo ok || echo fail)
  if [ "$got" = "$1" ] && grep -qF -- "$4" <<<"$5"; then t PASS "$3"; else t FAIL "$3 ($got, rc=$2)"; echo "$5" | tail -n 8; fi; }
summary() { echo "$pass passed, $failed failed"; [ "$failed" = 0 ]; }
