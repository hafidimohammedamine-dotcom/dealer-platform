#!/usr/bin/env bash
# Probe for Claude Code's subprocess isolation (founder-owned). Run BY Claude as a Bash tool in
# .github/workflows/egress-lock-claude.yml: counts Claude tokens (sk-ant-<kind><nn>-...) visible to a tool - in its own
# environment, in every process environment it can read, and in every readable text file under the places the action and
# Claude Code write to (the home folder, /tmp, the runner's temp folder): a token on disk would get around the environment
# scrub. Prints counts only, never a token. Env (tests only): SCRUB_PROBE_DIRS overrides the folders scanned.
set -uo pipefail
TOKEN='sk-ant-[a-z]+[0-9]{2}-[A-Za-z0-9_-]{20,}'
env_tokens=$(env | grep -cE "$TOKEN" || true)
proc_tokens=0
for f in /proc/[0-9]*/environ; do
  [ -r "$f" ] || continue
  if { tr '\0' '\n' < "$f"; } 2>/dev/null | grep -qE "$TOKEN"; then proc_tokens=$((proc_tokens + 1)); fi
done
file_tokens=0
for d in ${SCRUB_PROBE_DIRS:-"$HOME" /tmp "${RUNNER_TEMP:-/home/runner/work/_temp}"}; do
  [ -d "$d" ] || continue
  n=$(grep -rIlE "$TOKEN" "$d" 2>/dev/null | wc -l); file_tokens=$((file_tokens + n))   # -I: text files only; never prints a match
done
echo "SCRUB-PROBE env-tokens=$env_tokens proc-tokens=$proc_tokens file-tokens=$file_tokens pid=$$"
