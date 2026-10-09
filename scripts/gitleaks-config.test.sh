#!/usr/bin/env bash
# Proves .gitleaks.toml only allows AWS's documented fake key and still catches other AWS-style keys.
# Usage: GITLEAKS="gitleaks" bash scripts/gitleaks-config.test.sh
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
GITLEAKS="${GITLEAKS:-gitleaks}"
TMPROOT="${TMPDIR:-/tmp}"
T=$(mktemp -d "$TMPROOT/glt.XXXXXX") || exit 2
trap 'rm -rf "$T"' EXIT
cp "$REPO/.gitleaks.toml" "$T/.gitleaks.toml"
OTHER="AKIA""Z3QF7KLM2XWB9RTN"   # built at run time so this file isn't flagged
pass=0; failed=0
check() { # check <found|clean> <name> <file> <content>
  rm -rf "$T/case"; mkdir -p "$T/case"; printf '%s\n' "$4" > "$T/case/$3"
  if $GITLEAKS detect --no-git --source="$T/case" --config="$T/.gitleaks.toml" --redact >/dev/null 2>&1; then got=clean; else got=found; fi
  if [ "$got" = "$1" ]; then pass=$((pass+1)); echo "PASS  $2"; else failed=$((failed+1)); echo "FAIL  $2 (expected $1, got $got)"; fi
}
check clean "documented example key is allowed (.md)" a.md 'key = "AKIAIOSFODNN7EXAMPLE"'
check clean "documented example key is allowed (.ts)" a.ts 'const k = "AKIAIOSFODNN7EXAMPLE";'
check found "other AWS-style key is caught (.md)"     a.md "key = \"$OTHER\""
check found "other AWS-style key is caught (.json)"   a.json "{\"k\": \"$OTHER\"}"
check found "real key on the same line as the example is caught" a.md "AKIAIOSFODNN7EXAMPLE $OTHER"
echo "$pass passed, $failed failed"
[ "$failed" = 0 ]
