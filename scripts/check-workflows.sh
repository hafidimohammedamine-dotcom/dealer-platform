#!/usr/bin/env bash
# Checks the agent workflows keep their deny entries. Fails closed, step by step (full-line comments ignored):
#  - EVERY step that uses an anthropics/claude-code* action has exactly one `--disallowedTools "..."` line whose comma list
#    contains the exact item Skill(payload), so the upstream Payload skill is only ever loaded together with its override
#    (as an agent preload).
#  - Those steps set tools only through `--allowedTools "..."` / `--disallowedTools "..."` lines: any other route
#    (allowed_tools:, disallowed_tools:, settings:, --settings, --allowed-tools, --allowedTools=, --mcp-config, ...) fails.
#  - Claude runs nowhere else: no other step may run the claude CLI or @anthropic-ai/claude-code, or see a Claude/Anthropic
#    credential (secrets.*CLAUDE*/*ANTHROPIC*, ANTHROPIC_API_KEY, CLAUDE_CODE_OAUTH_TOKEN), and no reusable workflow or local
#    action is used except those in LOCAL_ACTIONS.
#  - The manager's single claude step keeps every command deny in MANAGER_DENIES.
# Usage: scripts/check-workflows.sh [repo-root]
set -euo pipefail
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
DIR="$ROOT/.github/workflows"
[ -d "$DIR" ] || { echo "ERROR: no workflows folder $DIR"; exit 1; }

MANAGER_DENIES='Skill(payload),Bash(npx:*),Bash(npm:*),Bash(yarn dlx:*),Bash(yarn create:*),Bash(node -e:*),Bash(node --eval:*),Bash(node -p:*),Bash(node --print:*),Bash(curl:*),Bash(wget:*),Bash(sudo:*),Bash(env:*),Bash(printenv:*),Bash(git push --force:*),Bash(git push -f:*),Bash(gh pr merge:*),Bash(gh api -X DELETE:*),Bash(gh secret:*),Bash(gh auth:*),Read(//proc/**),Read(//sys/**),Read(//home/runner/work/_temp/**),Read(//home/runner/.*/**),Read(//etc/**)'
LOCAL_ACTIONS=' ./.github/actions/install-gitleaks '

fail=0
shopt -s nullglob
files=("$DIR"/*.yml "$DIR"/*.yaml)
[ "${#files[@]}" -gt 0 ] || { echo "ERROR: no workflow files in $DIR"; exit 1; }
manager_seen=0
for f in "${files[@]}"; do
  name=$(basename "$f")
  out=$(awk -v file="$name" -v mdenies="$MANAGER_DENIES" -v local_ok="$LOCAL_ACTIONS" '
    function other(   n, i, line, u) {   # a chunk that is not a claude-code step
      n = split(step, L, "\n")
      for (i = 1; i <= n; i++) {
        line = L[i]; sub(/[[:space:]]#.*$/, "", line)   # trailing comments do not count
        if (line ~ /(^|[[:space:];&|(`$"'"'"'])claude([[:space:]]|$)|@anthropic-ai\/claude-code|claude-code/)
          print "ERROR: " file " line " (start + i - 1) ": runs Claude outside an anthropics/claude-code-action step"
        if (line ~ /secrets\.[A-Za-z0-9_]*([Cc][Ll][Aa][Uu][Dd][Ee]|[Aa][Nn][Tt][Hh][Rr][Oo][Pp][Ii][Cc])|ANTHROPIC_API_KEY|CLAUDE_CODE_OAUTH_TOKEN/)
          print "ERROR: " file " line " (start + i - 1) ": Claude/Anthropic credential outside an anthropics/claude-code-action step"
        if (match(line, /uses:[[:space:]]*[^[:space:]#]+/)) {
          u = substr(line, RSTART, RLENGTH); sub(/uses:[[:space:]]*/, "", u)
          if (u ~ /^\.\// && index(local_ok, " " u " ") == 0) print "ERROR: " file " line " (start + i - 1) ": local action not on the allow-list: " u
          if (u ~ /\/\.github\/workflows\//) print "ERROR: " file " line " (start + i - 1) ": reusable workflow not allowed: " u
        }
      }
    }
    function check(   n, i, k, line, list, items, have, m, d, nd, bad) {
      if (step !~ /anthropics\/claude-code/) { other(); return }
      steps++
      n = split(step, L, "\n"); k = 0; list = ""; bad = ""
      for (i = 1; i <= n; i++) {
        line = L[i]
        if (line ~ /allowed_tools|disallowed_tools|--allowed-tools|--disallowed-tools|[Aa]llowedTools=|(^|[^-[:alnum:]_])settings:|--settings|--permission-prompt-tool|--mcp-config/) bad = bad " [" line "]"
        if (line ~ /--disallowedTools/) {
          k++
          if (match(line, /--disallowedTools "[^"]*"/)) { list = substr(line, RSTART + 19, RLENGTH - 20) }
          else bad = bad " [unquoted or split --disallowedTools: " line "]"
        }
      }
      if (bad != "") { print "ERROR: " file " claude step " steps ": tools set outside --allowedTools/--disallowedTools lines:" bad; return }
      if (k != 1) { print "ERROR: " file " claude step " steps ": needs exactly one --disallowedTools line (found " k ")"; return }
      delete have; m = split(list, items, ",")
      for (i = 1; i <= m; i++) { gsub(/^ +| +$/, "", items[i]); have[items[i]] = 1 }
      if (!("Skill(payload)" in have)) print "ERROR: " file " claude step " steps ": --disallowedTools does not deny Skill(payload)"
      if (file == "agent-manager.yml") {
        print "MANAGER_STEP"
        nd = split(mdenies, d, ",")
        for (i = 1; i <= nd; i++) if (!(d[i] in have)) print "ERROR: agent-manager.yml: missing deny " d[i]
      }
    }
    BEGIN { start = 1 }
    /^[ \t]*#/ { step = step "\n"; next }        # full-line comments do not count (kept as blank lines for numbering)
    /^[ \t]*- / { check(); step = ""; start = NR } # a new list item starts a new chunk (splitting more is fail-closed)
    { step = step $0 "\n" }
    END { check() }
  ' "$f")
  if grep -q '^MANAGER_STEP$' <<<"$out"; then manager_seen=$((manager_seen + $(grep -c '^MANAGER_STEP$' <<<"$out"))); fi
  errs=$(grep -v '^MANAGER_STEP$' <<<"$out" || true)
  if [ -n "$errs" ]; then echo "$errs"; fail=1; fi
done
[ "$manager_seen" = 1 ] || { echo "ERROR: expected exactly one claude step in agent-manager.yml (found $manager_seen)"; fail=1; }
[ "$fail" = 0 ] && echo "Workflow denies OK"
exit "$fail"
