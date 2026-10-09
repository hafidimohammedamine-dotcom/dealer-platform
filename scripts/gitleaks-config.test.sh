#!/usr/bin/env bash
# Proves .gitleaks.toml only allows AWS's documented fake key, and still catches a different AWS-style key.
# Usage: GITLEAKS="gitleaks" bash scripts/gitleaks-config.test.sh   (CI uses the pinned docker image)
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
GITLEAKS="${GITLEAKS:-gitleaks}"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cp "$REPO/.gitleaks.toml" "$T/.gitleaks.toml"
run() { $GITLEAKS detect --no-git --source="$T/case" --config="$T/.gitleaks.toml" --redact >/dev/null 2>&1; }
fails=0
mkdir -p "$T/case" && printf 'key = "AKIAIOSFODNN7EXAMPLE"\n' > "$T/case/a.md"
if run; then echo "PASS  documented example key is allowed"; else echo "FAIL  documented example key flagged"; fails=1; fi
printf 'key = "%s%s"\n' AKIA Z3QF7KLM2XWB9RTN > "$T/case/a.md"  # built at run time so this file isn't flagged
if run; then echo "FAIL  a different AWS-style key was NOT detected"; fails=1; else echo "PASS  a different AWS-style key is detected"; fi
exit $fails
