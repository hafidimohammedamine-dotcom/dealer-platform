#!/usr/bin/env bash
# The repository files the agent and guard workflows run are pinned by sha256 in .github/pins.txt, and that file's own
# sha256 is written into every workflow (env PINS_SHA256 of the step "The repository files this job runs are the reviewed
# ones ..."), which the agents' token cannot change (no `workflow` scope). So a push that changes a pinned file - the lock
# action, a guard script, the accounts list, an agent instruction file - without a founder's workflow change fails every
# job before any secret or sudo is used. Founder-owned file; checked by scripts/check-workflows.py (every job carries the
# step with the current hash) and scripts/check-pins.test.sh.
# Usage: scripts/check-pins.sh update [repo-root]   regenerate .github/pins.txt and write its hash into every workflow
#        scripts/check-pins.sh verify [repo-root]   the pin step's third line (after the two sha256sum lines proved this
#                                                   script and pins.txt): fails if the tree holds a pinned-kind file that
#                                                   pins.txt does not list (a new .claude/ file, a nested CLAUDE.md or
#                                                   .mcp.json ...), lists a file it should not, or a pin does not match.
# Which files are pinned is one rule, `pins_required` in scripts/check-workflows-policy.json, read by
# scripts/check-workflows-lib.py (stdlib only), which both modes run; the workflow checker applies the same rule on every run.
set -euo pipefail
CMD="${1:-}"; ROOT="${2:-$(cd "$(dirname "$0")/.." && pwd)}"
HERE="$(cd "$(dirname "$0")" && pwd)"
PINS=.github/pins.txt
case "$CMD" in update|verify) ;; *) echo "usage: check-pins.sh update|verify [repo-root]"; exit 2;; esac
cd "$ROOT"
[ -d .github/workflows ] || { echo "ERROR: no .github/workflows in $ROOT"; exit 1; }
if [ "$CMD" = verify ]; then
  problems=$(python3 -I "$HERE/check-workflows-lib.py" verify "$ROOT") && { echo "Pins OK ($(wc -l < "$PINS") files)"; exit 0; }
  echo "ERROR: the pinned files do not match $PINS (a pushed file is not the reviewed one, or a new agent-instruction file is not pinned):"
  echo "$problems"; exit 1
fi
want=$(python3 -I "$HERE/check-workflows-lib.py" paths "$ROOT" | while read -r f; do [ -f "$f" ] || { echo "ERROR: pinned file missing: $f" >&2; exit 1; }; sha256sum "$f"; done)
printf '%s\n' "$want" > "$PINS"
h=$(sha256sum "$PINS" | cut -c1-64); n=0
for w in .github/workflows/*.yml; do
  if grep -q '^ *PINS_SHA256: "' "$w"; then sed -i -E "s/^( *PINS_SHA256: \")[0-9a-f]{64}(\")/\1$h\2/" "$w"; n=$((n+1)); fi
done
echo "Updated $PINS ($(wc -l < "$PINS") files) and PINS_SHA256 in $n workflow(s): $h"
