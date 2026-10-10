#!/usr/bin/env bash
# Proves .gitleaks.toml allows only AWS's documented fake key and still catches other keys.
# Usage: GITLEAKS=/path/to/gitleaks bash scripts/gitleaks-config.test.sh
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
GITLEAKS="${GITLEAKS:-gitleaks}"
TMPROOT="${TMPDIR:-/tmp}"
"$GITLEAKS" version >/dev/null 2>&1 || { echo "ERROR: gitleaks not runnable: $GITLEAKS"; exit 2; }
T=$(mktemp -d "$TMPROOT/glt.XXXXXX") || exit 2
trap 'rm -rf "$T"' EXIT
cp "$REPO/.gitleaks.toml" "$T/.gitleaks.toml"; mkdir -p "$T/noignore"
OTHER="AKIA""Z3QF7KLM2XWB9RTN"   # built at run time so this file isn't flagged
OAT="sk-ant-""oat01-""$(printf 'A%.0s' {1..40})_x-y"; API="sk-ant-""api03-""$(printf 'b%.0s' {1..60})"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-testlib.sh"
scan() { # scan <found|clean> <name> <file> <content>
  rm -rf "$T/case"; mkdir -p "$T/case"; printf '%s\n' "$4" > "$T/case/$3"
  "$GITLEAKS" detect --no-git --source="$T/case" --config="$T/.gitleaks.toml" --gitleaks-ignore-path="$T/noignore" \
    --ignore-gitleaks-allow --exit-code 3 --redact >/dev/null 2>&1; rc=$?
  case $rc in 0) got=clean;; 3) got=found;; *) t FAIL "gitleaks exited $rc on case '$2'"; return;; esac
  if [ "$got" = "$1" ]; then t PASS "$2"; else t FAIL "$2 (expected $1, got $got)"; fi
}
scan clean "documented example key is allowed (.md)"            a.md   'key = "AKIAIOSFODNN7EXAMPLE"'
scan clean "documented example key is allowed (.ts)"            a.ts   'const k = "AKIAIOSFODNN7EXAMPLE";'
scan found "other AWS-style key is caught (.md)"                a.md   "key = \"$OTHER\""
scan found "other AWS-style key is caught (.json)"              a.json "{\"k\": \"$OTHER\"}"
scan found "real key on the same line as the example is caught" a.md   "AKIAIOSFODNN7EXAMPLE $OTHER"
scan found "near-copy of the example key is caught (exact match only)" a.md "key = \"AKIA""IOSFODNN7EXAMPLF\""
scan found "inline gitleaks:allow does not hide a key"          a.ts   "const k = \"$OTHER\"; // gitleaks:allow"
scan found "a Claude OAuth token is caught (.ts)"               a.ts   "const t = \"$OAT\";"
scan found "a Claude API key is caught (.md)"                   a.md   "key: $API"
scan found "a Claude token inside a review answer is caught"    a.txt  "The file says: $OAT and more"
scan clean "the token prefix alone is not a finding"            a.md   "look for sk-ant-oat01- shaped strings"
summary
