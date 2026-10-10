#!/usr/bin/env bash
# The repository files the agent and guard workflows run are pinned by sha256 in .github/pins.txt, and that file's own
# sha256 is written into every workflow (env PINS_SHA256 of the step "The repository files this job runs are the reviewed
# ones ..."), which the agents' token cannot change (no `workflow` scope). So a push that changes a pinned file - the lock
# action, a guard script, the accounts list - without a founder's workflow change fails every job before any secret or sudo
# is used. Founder-owned file; checked by scripts/check-workflows.py (every job carries the step with the current hash) and
# scripts/check-pins.test.sh.
# Usage: scripts/check-pins.sh update [repo-root]   regenerate .github/pins.txt and write its hash into every workflow
#        scripts/check-pins.sh check  [repo-root]   fail if pins.txt or any workflow's PINS_SHA256 is out of date
# Pinned: .github/actions/** , scripts/check-* (not the tests or test libraries), .gitleaks.toml, .github/accounts.txt.
set -euo pipefail
CMD="${1:-}"; ROOT="${2:-$(cd "$(dirname "$0")/.." && pwd)}"
PINS=.github/pins.txt
case "$CMD" in update|check) ;; *) echo "usage: check-pins.sh update|check [repo-root]"; exit 2;; esac
cd "$ROOT"
[ -d .github/workflows ] || { echo "ERROR: no .github/workflows in $ROOT"; exit 1; }

pinned_files() {   # sorted, repo-relative
  { find .github/actions -type f; ls scripts/check-* 2>/dev/null | grep -vE '\.test\.sh$|testlib\.sh$'; echo .gitleaks.toml; echo .github/accounts.txt; } \
    | sed 's#^\./##' | sort -u
}
want=$(pinned_files | while read -r f; do [ -f "$f" ] || { echo "ERROR: pinned file missing: $f" >&2; exit 1; }; sha256sum "$f"; done)
T=$(mktemp); trap 'rm -f "$T"' EXIT
printf '%s\n' "$want" > "$T"
hash_of() { sha256sum "$1" | cut -c1-64; }
wf_files=$(ls .github/workflows/*.yml)

if [ "$CMD" = update ]; then
  cp "$T" "$PINS"
  h=$(hash_of "$PINS"); n=0
  for w in $wf_files; do
    if grep -q '^ *PINS_SHA256: "' "$w"; then sed -i -E "s/^( *PINS_SHA256: \")[0-9a-f]{64}(\")/\1$h\2/" "$w"; n=$((n+1)); fi
  done
  echo "Updated $PINS ($(wc -l < "$PINS") files) and PINS_SHA256 in $n workflow(s): $h"
  exit 0
fi

fail=0
if [ ! -f "$PINS" ]; then echo "ERROR: $PINS is missing; run: bash scripts/check-pins.sh update"; exit 1; fi
if ! cmp -s "$T" "$PINS"; then
  echo "ERROR: $PINS is out of date (a pinned file changed, was added or removed); run: bash scripts/check-pins.sh update"
  diff "$PINS" "$T" | grep '^[<>]' | head -n 10; fail=1
fi
h=$(hash_of "$PINS"); n=0
for w in $wf_files; do
  grep -q '^ *PINS_SHA256: "' "$w" || continue
  n=$((n+1))
  got=$(sed -n -E 's/^ *PINS_SHA256: "([0-9a-f]{64})".*/\1/p' "$w" | head -n1)
  [ "$got" = "$h" ] || { echo "ERROR: $w pins $PINS at ${got:-nothing}, but it is $h; run: bash scripts/check-pins.sh update"; fail=1; }
done
[ "$n" -gt 0 ] || { echo "ERROR: no workflow carries PINS_SHA256"; fail=1; }
[ "$fail" = 0 ] || exit 1
echo "Pins OK: $PINS ($(wc -l < "$PINS") files) matches the files and $n workflow(s)"
