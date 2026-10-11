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
rep() { head -c "$1" /dev/zero | tr '\0' "$2"; }   # rep <n> <char>: n copies of one character (test filler)
# mk <exec.json>: a claude-code-action execution file whose last result is the text on stdin
mk() { python3 -c 'import json,sys; json.dump([{"type":"result","result":sys.stdin.read()}], open(sys.argv[1],"w"))' "$1"; }
# handoff_text <output of check-claude-answer.sh answer>: the handed answer (the lines between the delimiters)
handoff_text() { local d; d=$(sed -n '2s/^answer<<//p' <<<"$1"); printf '%s\n' "$1" | sed -n "3,/^$d\$/p" | sed '$d'; }
# write_gh_stub <dir>: a fake `gh` at <dir>/gh for tests of the GitHub helpers (scripts/check-github-lib.sh), driven by
# STUB_* variables: STUB_WHO/STUB_RC (`api user`), STUB_HEAD/STUB_HEAD_RC (main's head), STUB_REL/STUB_REL_RC (the compare
# status), STUB_RUNS/STUB_RUNS_RC/STUB_RUNS_LATER with STUB_COUNT (the main-guard runs of a head; LATER after the first
# call), STUB_LATEST/STUB_LATEST_RC (the newest successful push run's head; empty = none), STUB_NUMBERS/STUB_NUMBERS_RC (the
# run numbers of every retained main-guard run, each as "n 1 success"; STUB_RUN_ROWS adds raw "number attempt conclusion"
# lines), STUB_SCHED/STUB_SCHED_RC (the newest scheduled or dispatched runs as "status conclusion created_at [event]" lines; default: one
# success now), STUB_NEWEST_AT/STUB_NEWEST_RC (the newest run's time), STUB_MARKS/STUB_MARKS_RC (how
# many guards/main-guard statuses a commit carries), STUB_MARK_RC (posting one),
# STUB_GH_LOG (every call appended). A test adds its own cases in <dir>/gh-extra: a file holding one
# `case "$*" in ...;; esac` (or on "$1 $2") whose arms `exit`; unmatched calls fall through to the shared cases, then exit 9.
write_gh_stub() {
  cat > "$1/gh" <<'STUB'
#!/usr/bin/env bash
[ -z "${STUB_GH_LOG:-}" ] || echo "gh $*" >> "$STUB_GH_LOG"
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
[ ! -f "$here/gh-extra" ] || . "$here/gh-extra"
case "$*" in
  'api user --jq "\(.id) \(.login)"') printf '%s\n' "${STUB_WHO-333 agents-bot}"; exit "${STUB_RC:-0}";;
  'api repos/owner/repo/commits/HEAD --jq .sha') printf '%s\n' "${STUB_HEAD-cccccccccccccccccccccccccccccccccccccccc}"; exit "${STUB_HEAD_RC:-0}";;
  'api repos/owner/repo/compare/'*' --jq .status') [ "${STUB_REL_RC:-0}" = 0 ] || exit 1; printf '%s\n' "${STUB_REL:-behind}"; exit 0;;
  'api repos/owner/repo/commits/'*'/status --jq '*) [ "${STUB_MARKS_RC:-0}" = 0 ] || exit 1; printf '%s\n' "${STUB_MARKS-0}"; exit 0;;
  'api -X POST repos/owner/repo/statuses/'*' -f state=success -f context=guards/main-guard -f description='*) exit "${STUB_MARK_RC:-0}";;
  'api --paginate repos/owner/repo/actions/workflows/main-guard.yml/runs?per_page=100 --jq '*'.run_number'*)
    [ "${STUB_NUMBERS_RC:-0}" = 0 ] || exit 1; [ -z "${STUB_RUN_ROWS:-}" ] || printf '%s\n' "$STUB_RUN_ROWS"; for n in ${STUB_NUMBERS:-}; do echo "$n 1 success"; done; exit 0;;
  'api repos/owner/repo/actions/workflows/main-guard.yml/runs?per_page=30 --jq '*) [ "${STUB_SCHED_RC:-0}" = 0 ] || exit 1; printf '%s\n' "${STUB_SCHED-completed success $(date -u +%Y-%m-%dT%H:%M:%SZ)}"; exit 0;;
  'api repos/owner/repo/actions/workflows/main-guard.yml/runs?per_page=1 --jq '*) [ "${STUB_NEWEST_RC:-0}" = 0 ] || exit 1; printf '%s\n' "${STUB_NEWEST_AT-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"; exit 0;;
  'api repos/owner/repo/actions/workflows/main-guard.yml/runs?event=push&status=success&per_page=1 --jq '*) [ "${STUB_LATEST_RC:-0}" = 0 ] || exit 1; printf '%s\n' "${STUB_LATEST:-}"; exit 0;;
  'api repos/owner/repo/actions/workflows/main-guard.yml/runs?head_sha='*)
    [ "${STUB_RUNS_RC:-0}" = 0 ] || exit 1
    n=0; if [ -n "${STUB_COUNT:-}" ]; then n=$(cat "$STUB_COUNT" 2>/dev/null || echo 0); echo $((n+1)) > "$STUB_COUNT"; fi
    if [ -n "${STUB_RUNS_LATER:-}" ] && [ "$n" -ge 1 ]; then printf '%s\n' "$STUB_RUNS_LATER"; else printf '%s\n' "${STUB_RUNS-completed/success}"; fi; exit 0;;
esac
exit 9
STUB
  chmod +x "$1/gh"
}
assert_no_token() { # assert_no_token <name> <output> <token-text...>: none of the token texts appears in the output
  local name=$1 out=$2 tok; shift 2
  for tok in "$@"; do if grep -qF -- "$tok" <<<"$out"; then t FAIL "token printed by: $name"; return; fi; done
  t PASS "no token in the output of: $name"; }
