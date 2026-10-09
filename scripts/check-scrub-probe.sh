#!/usr/bin/env bash
# Probe for Claude Code's subprocess isolation (founder-owned). Run BY Claude as a Bash tool in
# .github/workflows/egress-lock-claude.yml: counts Claude tokens (they start with sk-ant) visible to a tool, in its own
# environment and in every process environment it can read. Prints counts only, never a token.
set -uo pipefail
env_tokens=$(env | grep -c 'sk-ant' || true)
proc_tokens=0
for f in /proc/[0-9]*/environ; do
  [ -r "$f" ] || continue
  if { tr '\0' '\n' < "$f"; } 2>/dev/null | grep -q 'sk-ant'; then proc_tokens=$((proc_tokens + 1)); fi
done
echo "SCRUB-PROBE env-tokens=$env_tokens proc-tokens=$proc_tokens pid=$$"
