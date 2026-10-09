#!/usr/bin/env bash
# Tests scripts/check-review-prepare.sh against a local bare "remote" with a refs/pull/<n>/head ref.
set -uo pipefail
SCRIPT="$(cd "$(dirname "$0")" && pwd)/check-review-prepare.sh"
TMPROOT="${TMPDIR:-/tmp}"
pass=0; failed=0
ok()  { pass=$((pass+1)); echo "PASS  $1"; }
bad() { failed=$((failed+1)); echo "FAIL  $1"; [ -n "${2:-}" ] && echo "$2"; }
W=$(mktemp -d "$TMPROOT/rp.XXXXXX") || exit 2
trap 'rm -rf "$W"' EXIT
git init -q --bare "$W/remote.git"
git init -q -b main "$W/base" && cd "$W/base" && git config user.email t@t && git config user.name t
echo base > CLAUDE.md && mkdir -p .claude && echo a > .claude/a.md && echo code > a.ts
git add -A && git commit -qm base && git remote add origin "$W/remote.git" && git push -q origin main 2>/dev/null
git checkout -qb pr
mkdir -p "dir with space/.claude" apps/admin/.claude src
echo evil > CLAUDE.md; echo evil > "dir with space/CLAUDE.md"; echo evil > "dir with space/.claude/x.md"
echo evil > apps/admin/.claude/settings.json; echo evil > apps/CLAUDE.local.md; echo '{}' > src/.mcp.json; echo new > src/b.ts
git add -A && git commit -qm pr && git push -q origin "HEAD:refs/pull/7/head" 2>/dev/null
git checkout -q main && git fetch -q origin

out=$(bash "$SCRIPT" 7 "$W/pr" 2>&1); rc=$?
[ $rc = 0 ] && grep -qF "ready in $W/pr" <<<"$out" && ok "prepares PR #7" || bad "prepares PR #7" "$out"
left=$(find "$W/pr" -path "$W/pr/.git" -prune -o \( -name CLAUDE.md -o -name CLAUDE.local.md -o -name .mcp.json -o -name .claude \) -print)
[ -z "$left" ] && ok "all rule files removed (root, nested, folder with space, .claude dirs)" || bad "rule files removed" "$left"
[ -f "$W/pr/src/b.ts" ] && ok "normal PR files kept" || bad "normal PR files kept"
d=$(git -C "$W/pr" diff --name-only main...HEAD)
grep -qx "dir with space/CLAUDE.md" <<<"$d" && ok "rule-file changes still visible in git diff" || bad "diff shows rule files" "$d"
[ "$(git config --get-regexp 'http\..*extraheader' || true)" = "" ] && ok "no credentials stored in git config" || bad "no stored credentials"
out=$(bash "$SCRIPT" 7 "$W/pr" 2>&1); rc=$?
[ $rc != 0 ] && grep -qF "already exists" <<<"$out" && ok "refuses an existing destination" || bad "existing destination" "$out"
out=$(bash "$SCRIPT" "7;rm" "$W/pr2" 2>&1); rc=$?
[ $rc != 0 ] && grep -qF "bad PR number" <<<"$out" && ok "rejects a non-numeric PR number" || bad "non-numeric PR" "$out"
out=$(bash "$SCRIPT" 99 "$W/pr3" 2>&1); rc=$?
[ $rc != 0 ] && [ ! -d "$W/pr3" ] && ok "missing PR ref fails" || bad "missing PR ref" "$out"
echo "$pass passed, $failed failed"
[ "$failed" = 0 ]
