#!/usr/bin/env bash
# Tests scripts/check-skills.sh against a temporary copy of .claude/skills.
# Each case mutates the copy and asserts pass/fail. Run: bash scripts/check-skills.test.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
SCRIPT="$HERE/check-skills.sh"
pass=0; failed=0

fresh() {
  T=$(mktemp -d)
  mkdir -p "$T/.claude"
  cp -a "$REPO/.claude/skills" "$T/.claude/skills"
}
expect() { # expect <ok|fail> <name>
  if bash "$SCRIPT" "$T" >"$T.out" 2>&1; then got=ok; else got=fail; fi
  if [ "$got" = "$1" ]; then pass=$((pass+1)); echo "PASS  $2"
  else failed=$((failed+1)); echo "FAIL  $2 (expected $1, got $got)"; cat "$T.out"; fi
  rm -rf "$T" "$T.out"
}

fresh; expect ok   "clean copy passes"
fresh; echo "x" >> "$T/.claude/skills/payload/SKILL.md";                  expect fail "changed file in a pinned skill"
fresh; echo "x" >> "$T/.claude/skills/payload/NOTICE.md";                 expect fail "changed NOTICE.md"
fresh; echo "x" > "$T/.claude/skills/payload/reference/NOTICE.md";        expect fail "added NOTICE.md deeper down"
fresh; echo "x" >> "$T/.claude/skills/payload-dealer-overrides/SKILL.md"; expect fail "changed first-party override"
fresh; echo "x" > "$T/.claude/skills/payload/reference/NEW.md";           expect fail "added file"
fresh; rm "$T/.claude/skills/payload/reference/HOOKS.md";                 expect fail "removed file"
fresh; mv "$T/.claude/skills/payload/reference/HOOKS.md" "$T/.claude/skills/payload/reference/HOOKS2.md"; expect fail "renamed file"
fresh; rm -rf "$T/.claude/skills/tdd";                                     expect fail "removed skill folder"
fresh; mkdir "$T/.claude/skills/evil" && echo x > "$T/.claude/skills/evil/SKILL.md"; expect fail "unknown skill folder"
fresh; ln -s /etc/hostname "$T/.claude/skills/payload/reference/link.md";  expect fail "symlink inside a skill"
fresh; echo x > "$T/.claude/skills/stray.md";                              expect fail "stray top-level file"
fresh; rm "$T/.claude/skills/checksums.sha256";                            expect fail "missing checksum file"
fresh; echo "x" >> "$T/.claude/skills/payload/SKILL.md"; bash "$SCRIPT" --write "$T" >/dev/null; expect ok "--write accepts the new state"

echo "$pass passed, $failed failed"
[ "$failed" = 0 ]
