#!/usr/bin/env bash
# Tests scripts/check-claude-probe.py with small execution files.
set -uo pipefail
PY="$(cd "$(dirname "$0")" && pwd)/check-claude-probe.py"
TMPROOT="${TMPDIR:-/tmp}"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-testlib.sh"
W=$(mktemp -d "$TMPROOT/cp.XXXXXX") || exit 2; trap 'rm -rf "$W"' EXIT
run() { # run <rc> <name> <mode> <json> <message>
  printf '%s' "$4" > "$W/e.json"
  out=$(python3 -I "$PY" "$3" "$W/e.json" 2>&1); rc=$?
  if [ "$rc" = "$1" ] && grep -qF -- "$5" <<<"$out"; then t PASS "$2"; else t FAIL "$2 (rc=$rc)"; echo "$out"; fi; }
DENY='{"tool_name":"Skill","tool_input":{"skill":"payload"}}'
run 0 "skill denied and Claude answered" skill-deny "[{\"type\":\"result\",\"result\":\"EGRESS-LOCK-OK SKILL-DENIED\",\"permission_denials\":[$DENY]}]" "result: EGRESS-LOCK-OK"
run 1 "no denial recorded" skill-deny '[{"type":"result","result":"EGRESS-LOCK-OK","permission_denials":[]}]' "denials: []"
run 1 "skill loaded" skill-deny "[{\"type\":\"result\",\"result\":\"EGRESS-LOCK-OK PROBE-LOADED\",\"permission_denials\":[$DENY]}]" "PROBE-LOADED"
run 1 "Claude did not answer" skill-deny "[{\"type\":\"result\",\"result\":\"\",\"permission_denials\":[$DENY]}]" "result:"
run 1 "denial of another skill" skill-deny '[{"type":"result","result":"EGRESS-LOCK-OK","permission_denials":[{"tool_name":"Skill","tool_input":{"skill":"other"}}]}]' "other"
run 1 "no result message" skill-deny '[{"type":"system"}]' "result: "
TR() { printf '[{"type":"user","message":{"content":[{"type":"tool_result","content":"%s"}]}}]' "$1"; }
run 0 "scrub probe saw no token" scrub "$(TR 'SCRUB-PROBE env-tokens=0 proc-tokens=0 pid=42')" "probe: SCRUB-PROBE env-tokens=0 proc-tokens=0 pid=42"
run 1 "token in the tool's environment" scrub "$(TR 'SCRUB-PROBE env-tokens=1 proc-tokens=0 pid=42')" "env-tokens=1"
run 1 "token in another process" scrub "$(TR 'SCRUB-PROBE env-tokens=0 proc-tokens=2 pid=42')" "proc-tokens=2"
run 1 "probe did not run" scrub '[{"type":"result","result":"SCRUB-PROBE env-tokens=0 proc-tokens=0 pid=1"}]' "probe: did not run"
run 2 "bad mode" other '[]' "usage:"
run 2 "unreadable file" scrub '{not json' "cannot read the execution file"
run 1 "not a list" scrub '{}' "did not run"

run 0 "several denials, one of them the payload skill" skill-deny "[{\"type\":\"result\",\"result\":\"EGRESS-LOCK-OK\",\"permission_denials\":[{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"}},$DENY]}]" "result: EGRESS-LOCK-OK"
run 1 "a non-Skill tool with skill=payload in its input is not the deny" skill-deny '[{"type":"result","result":"EGRESS-LOCK-OK","permission_denials":[{"tool_name":"Bash","tool_input":{"skill":"payload"}}]}]' "denials:"
run 1 "the last result message decides" skill-deny "[{\"type\":\"result\",\"result\":\"EGRESS-LOCK-OK\",\"permission_denials\":[$DENY]},{\"type\":\"result\",\"result\":\"EGRESS-LOCK-OK\",\"permission_denials\":[]}]" "denials: []"
# read-deny: every probe read outside the checkout denied, nothing token-shaped in the results
RD() { python3 -I - "$@" <<'EOF'
import json, sys
paths = sys.argv[1:]
den = [{"tool_name": t, "tool_input": {k: v}} for t, k, v in [
    ("Read", "file_path", paths[0]), ("Read", "file_path", "/dev/environ"), ("Read", "file_path", "/dev/stdin"),
    ("Read", "file_path", "/home/runner/runners/x"), ("Read", "file_path", "/etc/hostname"),
    ("Read", "file_path", "/home/runner/work/_temp/y"), ("Grep", "path", "/proc/self"), ("Glob", "path", "/proc/self")]]
print(json.dumps([{"type": "user", "message": {"content": [{"type": "tool_result", "content": paths[1]}]}},
                  {"type": "result", "result": "READ-PROBE-DONE", "permission_denials": den}]))
EOF
}
run 0 "read probe: all denied, nothing leaked" read-deny "$(RD /proc/self/environ 'File content (1 line): hello')" "token-shaped strings in tool results and the answer: 0"
run 1 "read probe: one read not denied" read-deny "$(RD /proc/self/status 'ok')" "NOT DENIED: Read /proc/self/environ"
run 1 "read probe: a token-shaped string in a tool result" read-deny "$(RD /proc/self/environ "T=sk-ant-oat01-$(printf 'Q%.0s' {1..30})")" "token-shaped strings in tool results and the answer: 1"
run 1 "read probe: Claude did not finish" read-deny '[{"type":"result","result":"stopped","permission_denials":[]}]' "NOT DENIED: Grep /proc/self"
run 1 "read probe: no result message" read-deny '[{"type":"system"}]' "denials: 0"
out=$(python3 -I "$PY" skill-deny "$W/missing.json" 2>&1); rc=$?
if [ $rc = 2 ] && grep -qF "cannot read the execution file" <<<"$out"; then t PASS "missing file (an empty \$EXEC_FILE)"; else t FAIL "missing file (rc=$rc)"; echo "$out"; fi
out=$(python3 -I "$PY" skill-deny "$W/e.json" extra 2>&1); rc=$?
if [ $rc = 2 ] && grep -qF "usage:" <<<"$out"; then t PASS "extra argument"; else t FAIL "extra argument (rc=$rc)"; fi
summary
