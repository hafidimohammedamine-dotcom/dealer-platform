#!/usr/bin/env bash
# Checks the agent workflows (rules in scripts/check-workflows.py, which parses them as YAML and fails closed).
# Usage: scripts/check-workflows.sh [repo-root] [--accounts FILE] [--manifest FILE ...]
# This wrapper reads the two shared text formats with the same bash helpers every other guard uses (one parser each):
# the skill manifests (scripts/check-skills-lib.sh: third-party skill names to deny) and .github/accounts.txt
# (scripts/check-accounts-lib.sh: validated "<id> <login> role" rows), and hands them to Python through the environment.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/check-skills-lib.sh
. "$HERE/check-skills-lib.sh"
# shellcheck source=scripts/check-accounts-lib.sh
. "$HERE/check-accounts-lib.sh"
ROOT=""; ACCOUNTS=""; MANIFESTS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --manifest|--accounts) [ $# -ge 2 ] || { echo "ERROR: $1 needs a file"; exit 1; }
      if [ "$1" = --manifest ]; then MANIFESTS+=("$2"); else ACCOUNTS="$2"; fi; shift 2;;
    --*) echo "ERROR: bad argument '$1'"; exit 1;;
    *) [ -z "$ROOT" ] || { echo "ERROR: bad argument '$1'"; exit 1; }; ROOT="$1"; shift;;
  esac
done
[ -n "$ROOT" ] || ROOT="$(cd "$HERE/.." && pwd)"
for m in "${MANIFESTS[@]}"; do [ -f "$m" ] || { echo "ERROR: manifest not found: $m"; exit 1; }; done
[ -f "$ROOT/.claude/skills/manifest.txt" ] && MANIFESTS+=("$ROOT/.claude/skills/manifest.txt")
THIRD=""
for m in "${MANIFESTS[@]}"; do THIRD+="$(manifest_entries "$m" | awk '$2 == "third-party" {print $1}')"$'\n'; done
# The accounts list: guards passes the base branch's copy (--accounts), so a PR cannot list itself.
rows=$(accounts_rows "${ACCOUNTS:-$ROOT/.github/accounts.txt}") || { echo "$rows"; exit 1; }
CW_THIRD_PARTY="$(sort -u <<<"$THIRD" | sed '/^$/d' | paste -sd, -)" CW_ACCOUNT_ROWS="$rows" exec python3 -I "$HERE/check-workflows.py" "$ROOT"
