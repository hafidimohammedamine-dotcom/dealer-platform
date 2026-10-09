#!/usr/bin/env bash
# Tests scripts/check-claude-probe.py with small execution files.
set -uo pipefail
PY="$(cd "$(dirname "$0")" && pwd)/check-claude-probe.py"
TMPROOT="${TMPDIR:-/tmp}"
pass=0; failed=0
W=$(mktemp -d "$TMPROOT/cp.XXXXXX") || exit 2; trap 'rm -rf "$W"' EXIT
run() { # run <rc> <name> <mode> <json> <message>
  printf '%s' "$4" > "$W/e.json"
  out=$(python3 -I "$PY" "$3" "$W/e.json" 2>&1); rc=$?
  if [ "$rc" = "$1" ] && grep -qF -- "$5" <<<"$out"; then pass=$((pass+1)); echo "PASS  $2"; else failed=$((failed+1)); echo "FAIL  $2 (rc=$rc)"; echo "$out"; fi; }
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
echo "$pass passed, $failed failed"
[ "$failed" = 0 ]
