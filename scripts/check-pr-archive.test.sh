#!/usr/bin/env bash
# Tests scripts/check-pr-archive.sh: a PR tree unpacked as data with its own .gitattributes switched off.
set -uo pipefail
SCRIPT="$(cd "$(dirname "$0")" && pwd)/check-pr-archive.sh"
TMPROOT="${TMPDIR:-/tmp}"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-testlib.sh"
W=$(mktemp -d "$TMPROOT/pa.XXXXXX") || exit 2; trap 'rm -rf "$W"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
git init -q -b main "$W/r" && cd "$W/r" && git config user.email t@t && git config user.name t
mkdir -p .claude/skills/evil .github/workflows src
printf '.claude/skills/evil/** export-ignore\n*.yml export-subst\n*.ts ident\n' > .gitattributes
printf 'name: evil\n' > .claude/skills/evil/SKILL.md; printf 'run: $Format:%%H$\n' > .github/workflows/x.yml; printf '$Id$\n' > src/a.ts
git add -A && git commit -qm pr && git update-ref refs/remotes/pr/head HEAD
run() { out=$(cd "$W/r" && bash "$SCRIPT" "$@" 2>&1); rc=$?; }
run refs/remotes/pr/head "$W/all"; assert_result ok "$rc" "unpacks the whole tree" "unpacked as data into $W/all (4 files, attributes off)" "$out"
check "an export-ignored skill is still unpacked (the merge would bring it)" test -f "$W/all/.claude/skills/evil/SKILL.md"
check "export-subst did not expand the workflow" bash -c '[ "$(cat "$1")" = "run: \$Format:%H\$" ]' _ "$W/all/.github/workflows/x.yml"
check "ident did not expand the source file" bash -c '[ "$(cat "$1")" = "\$Id\$" ]' _ "$W/all/src/a.ts"
check "the .gitattributes file itself is unpacked too (the founder-only check sees it)" test -f "$W/all/.gitattributes"
run refs/remotes/pr/head "$W/skills" .claude; assert_result ok "$rc" "unpacks one path" "(.claude) unpacked as data into $W/skills (1 files" "$out"
check "only that path" bash -c '[ -f "$1/.claude/skills/evil/SKILL.md" ] && [ ! -e "$1/src" ]' _ "$W/skills"
run refs/remotes/pr/head "$W/none" nothere; assert_result ok "$rc" "a path the tree lacks leaves the destination empty" "PR tree has no nothere; $W/none left empty" "$out"
check "the empty destination exists" bash -c '[ -d "$1" ] && [ -z "$(ls -A "$1")" ]' _ "$W/none"
mkdir -p "$W/stale" && echo old > "$W/stale/old.txt"; run refs/remotes/pr/head "$W/stale" .claude; assert_result ok "$rc" "a stale destination is replaced" "unpacked" "$out"
check "stale files are gone" test ! -e "$W/stale/old.txt"
run refs/remotes/pr/head "$W/x" ../etc; assert_result fail "$rc" "a path with .. is rejected" "bad path" "$out"
run 'refs/remotes/pr/head;rm' "$W/x"; assert_result fail "$rc" "a bad ref is rejected" "bad ref" "$out"
run refs/remotes/pr/nope "$W/x"; assert_result fail "$rc" "a missing ref fails" "ref not found" "$out"
summary
