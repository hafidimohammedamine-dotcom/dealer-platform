#!/usr/bin/env bash
# Checks that pinned third-party skills match .claude/skills/checksums.sha256.
# --write regenerates the file (founders only, in a skill-update PR).
set -euo pipefail
cd "$(dirname "$0")/.."
PINNED=(payload)
SUMS=.claude/skills/checksums.sha256
list() { for s in "${PINNED[@]}"; do find ".claude/skills/$s" -type f ! -name NOTICE.md; done | LC_ALL=C sort; }
if [ "${1:-}" = "--write" ]; then
  list | xargs sha256sum > "$SUMS"
  echo "Wrote $SUMS"
  exit 0
fi
sha256sum --check --quiet "$SUMS"
expected=$(awk '{print $2}' "$SUMS" | LC_ALL=C sort)
actual=$(list)
if [ "$expected" != "$actual" ]; then
  echo "Pinned skill files were added or removed:"; diff <(echo "$expected") <(echo "$actual") || true
  exit 1
fi
echo "Pinned skills OK"
