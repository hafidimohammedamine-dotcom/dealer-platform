#!/usr/bin/env bash
# The repository files the agent and guard workflows run are pinned by sha256 in .github/pins.txt, and that file's own
# sha256 is written into every workflow (env PINS_SHA256 of the step "The repository files this job runs are the reviewed
# ones ..."), which the agents' token cannot change (no `workflow` scope). So a push that changes a pinned file - the lock
# action, a guard script, the accounts list - without a founder's workflow change fails every job before any secret or sudo
# is used. Founder-owned file; checked by scripts/check-workflows.py (every job carries the step with the current hash) and
# scripts/check-pins.test.sh.
# Usage: scripts/check-pins.sh update [repo-root]   regenerate .github/pins.txt and write its hash into every workflow
# Which files are pinned is one rule, `pins_required` in scripts/check-workflows-policy.json (read here with the stdlib):
# the checker (scripts/check-workflows.py) verifies the same rule against the tree on every run, so there is no `check` mode.
set -euo pipefail
CMD="${1:-}"; ROOT="${2:-$(cd "$(dirname "$0")/.." && pwd)}"
HERE="$(cd "$(dirname "$0")" && pwd)"
PINS=.github/pins.txt
[ "$CMD" = update ] || { echo "usage: check-pins.sh update [repo-root]"; exit 2; }
cd "$ROOT"
[ -d .github/workflows ] || { echo "ERROR: no .github/workflows in $ROOT"; exit 1; }

pinned_files() {   # sorted, repo-relative, from pins_required in the policy
  python3 -I - "$HERE/check-workflows-policy.json" "$ROOT" <<'PY'
import glob, json, os, sys
req = json.load(open(sys.argv[1]))["pins_required"]; root = sys.argv[2]; out = set()
for d in req["dirs"]:
    for dp, _, fns in os.walk(os.path.join(root, d)):
        out.update(os.path.relpath(os.path.join(dp, f), root) for f in fns)
for g in req["globs"]:
    out.update(os.path.relpath(f, root) for f in glob.glob(os.path.join(root, g))
               if os.path.isfile(f) and not any(f.endswith(x) for x in req["exclude_suffixes"]))
out.update(f for f in req["files"] if os.path.isfile(os.path.join(root, f)))
print("\n".join(sorted(out)))
PY
}
want=$(pinned_files | while read -r f; do [ -f "$f" ] || { echo "ERROR: pinned file missing: $f" >&2; exit 1; }; sha256sum "$f"; done)
T=$(mktemp); trap 'rm -f "$T"' EXIT
printf '%s\n' "$want" > "$T"
hash_of() { sha256sum "$1" | cut -c1-64; }
wf_files=$(ls .github/workflows/*.yml)

cp "$T" "$PINS"
h=$(hash_of "$PINS"); n=0
for w in $wf_files; do
  if grep -q '^ *PINS_SHA256: "' "$w"; then sed -i -E "s/^( *PINS_SHA256: \")[0-9a-f]{64}(\")/\1$h\2/" "$w"; n=$((n+1)); fi
done
echo "Updated $PINS ($(wc -l < "$PINS") files) and PINS_SHA256 in $n workflow(s): $h"
