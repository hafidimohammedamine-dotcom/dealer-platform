#!/usr/bin/env bash
# Writes the repository's recent history and today's date as plain files for the weekly auditors, who read them instead
# of running git (founder-owned; one pinned script so that no free-form command runs before the Claude step). The
# dependency audit (yarn, which runs repository code) comes from the workflow's separate `deps` job as a downloaded
# artifact, never from this job. Usage: scripts/check-audit-prepare.sh [dir=/tmp/audit-meta]
set -euo pipefail
DIR="${1:-/tmp/audit-meta}"
mkdir -p "$DIR"
git log --stat -n 300 > "$DIR/log.txt"
git ls-files > "$DIR/files.txt"
date -u +%Y-%m-%dT%H:%M:%SZ > "$DIR/date.txt"
[ -s "$DIR/npm-audit.json" ] || echo "no dependency audit was delivered (the deps job did not run or found no package.json)" > "$DIR/npm-audit.json"
echo "Audit data in $DIR: $(wc -l < "$DIR/log.txt") log lines, $(wc -l < "$DIR/files.txt") files, npm-audit.json $(wc -c < "$DIR/npm-audit.json") bytes"
