#!/usr/bin/env bash
# Checks every file under .claude/skills against .claude/skills/checksums.sha256.
# Fails on: unknown skill folders, symlinks, added / removed / renamed files, changed content.
# --write regenerates the checksum file (founders only, in a skills PR).
# Usage: scripts/check-skills.sh [--write] [repo-root]
set -euo pipefail
MODE=check
if [ "${1:-}" = "--write" ]; then MODE=write; shift; fi
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT"
DIR=.claude/skills
SUMS="$DIR/checksums.sha256"

# Third-party skills, pinned to an upstream commit (see SKILLS-LOCK.md).
PINNED=(payload payload-accessibility frontend-design vercel-react-best-practices vercel-composition-patterns
  ui-ux-pro-max supabase-postgres-best-practices nx-workspace nx-run-tasks link-workspace-packages
  security-review agentic-actions-auditor property-based-testing tdd codebase-design playwright-cli
  typescript-best-practices principle-type-system-discipline principle-boundary-discipline
  nestjs-best-practices telnyx-messaging-javascript telnyx-10dlc-javascript resend email-best-practices)
# Our own skills (founder-owned). Also checksummed, so any change shows up in the checksum file.
FIRST_PARTY=(manager review-pr daily-report weekly-audit payload-dealer-overrides skill-overrides
  web-interface-rules writing-rules secure-coding scalability cost-reducer)
TOP_FILES=(checksums.sha256 SKILLS-LOCK.md)

fail=0
known=" ${PINNED[*]} ${FIRST_PARTY[*]} "
for entry in "$DIR"/* "$DIR"/.[!.]*; do
  [ -e "$entry" ] || [ -L "$entry" ] || continue
  name=$(basename "$entry")
  if [ -d "$entry" ] && [ ! -L "$entry" ]; then
    case "$known" in *" $name "*) ;; *) echo "Unknown skill folder: $name (add it to PINNED or FIRST_PARTY)"; fail=1;; esac
  else
    case " ${TOP_FILES[*]} " in *" $name "*) ;; *) echo "Unexpected file at $DIR/$name"; fail=1;; esac
  fi
done
for s in "${PINNED[@]}" "${FIRST_PARTY[@]}"; do
  [ -d "$DIR/$s" ] || { echo "Missing skill folder: $s"; fail=1; }
done
links=$(find "$DIR" -type l)
if [ -n "$links" ]; then echo "Symlinks are not allowed in $DIR:"; echo "$links"; fail=1; fi
special=$(find "$DIR" ! -type f ! -type d ! -type l)
if [ -n "$special" ]; then echo "Only regular files are allowed in $DIR:"; echo "$special"; fail=1; fi
[ "$fail" = 0 ] || exit 1

list() { find "$DIR" -mindepth 2 -type f | LC_ALL=C sort; }

if [ "$MODE" = write ]; then
  list | while IFS= read -r f; do sha256sum "$f"; done > "$SUMS"
  echo "Wrote $SUMS ($(wc -l < "$SUMS") files)"
  exit 0
fi

[ -f "$SUMS" ] || { echo "Missing $SUMS"; exit 1; }
expected=$(sed -E 's/^[0-9a-f]{64}  //' "$SUMS" | LC_ALL=C sort)
actual=$(list)
added=$(LC_ALL=C comm -13 <(echo "$expected") <(echo "$actual"))
removed=$(LC_ALL=C comm -23 <(echo "$expected") <(echo "$actual"))
if [ -n "$added" ]; then echo "Files added (not in checksums):"; echo "$added"; fail=1; fi
if [ -n "$removed" ]; then echo "Files removed or renamed:"; echo "$removed"; fail=1; fi
[ "$fail" = 0 ] || exit 1
if ! out=$(sha256sum --check --quiet "$SUMS" 2>&1); then echo "Changed files:"; echo "$out"; exit 1; fi
echo "Skills OK ($(wc -l < "$SUMS") files)"
