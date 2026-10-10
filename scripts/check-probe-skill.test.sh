#!/usr/bin/env bash
# Tests scripts/check-probe-skill.sh with a throwaway HOME.
set -uo pipefail
SCRIPT="$(cd "$(dirname "$0")" && pwd)/check-probe-skill.sh"
TMPROOT="${TMPDIR:-/tmp}"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-testlib.sh"
T=$(mktemp -d "$TMPROOT/ps.XXXXXX") || exit 2; trap 'rm -rf "$T"' EXIT
out=$(HOME="$T/home" bash "$SCRIPT" 2>&1); rc=$?
assert_result ok "$rc" "writes the probe skill under HOME" "Probe skill written to $T/home/.claude/skills/payload/SKILL.md" "$out"
check "the skill file has the frontmatter name payload and the probe line" bash -c 'grep -qx "name: payload" "$1" && grep -q "PROBE-LOADED" "$1"' _ "$T/home/.claude/skills/payload/SKILL.md"
check "nothing is written outside HOME" bash -c '[ "$(find "$1" -type f | wc -l)" = 1 ]' _ "$T"
out=$(HOME="$T/home" bash "$SCRIPT" 2>&1); rc=$?
assert_result ok "$rc" "running it twice is fine" "Probe skill written" "$out"
summary
