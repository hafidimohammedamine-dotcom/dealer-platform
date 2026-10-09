#!/usr/bin/env bash
# Tests scripts/check-skill-upstream.sh with a small fixture skill.
set -uo pipefail
SCRIPT="$(cd "$(dirname "$0")" && pwd)/check-skill-upstream.sh"
TMPROOT="${TMPDIR:-/tmp}"
pass=0; failed=0
fresh() {
  W=$(mktemp -d "$TMPROOT/su.XXXXXX") || exit 2
  mkdir -p "$W/up/ref" "$W/repo/.claude/skills/demo/ref" "$W/repo/.claude/skills-patches"
  printf 'keep\nnpx bad\nkeep2\n' > "$W/up/SKILL.md"; echo plug > "$W/up/ref/PLUG.md"; echo r > "$W/up/ref/R.md"
  printf 'keep\nkeep2\n' > "$W/repo/.claude/skills/demo/SKILL.md"; echo r > "$W/repo/.claude/skills/demo/ref/R.md"
  echo notice > "$W/repo/.claude/skills/demo/NOTICE.md"; echo mit > "$W/repo/.claude/skills/demo/UPSTREAM-LICENSE"
  ( cd "$W" && mkdir -p a && cp -r up a/upstream && mkdir -p a/ours && cp -r repo/.claude/skills/demo/. a/ours/ && cd a && \
    diff -ru -x NOTICE.md -x 'UPSTREAM-LICENSE*' upstream ours > "$W/repo/.claude/skills-patches/demo.diff" ) || true
}
expect() { out=$(bash "$SCRIPT" "$W/up" demo "$W/repo" 2>&1); rc=$?; got=$([ $rc = 0 ] && echo ok || echo fail)
  if [ "$got" = "$1" ] && grep -qF -- "$3" <<<"$out"; then pass=$((pass+1)); echo "PASS  $2"; else failed=$((failed+1)); echo "FAIL  $2 ($got)"; echo "$out"; fi; rm -rf "$W"; }
fresh;                                                              expect ok   "upstream + patch matches" "deletion-only patch"
fresh; echo extra >> "$W/repo/.claude/skills/demo/SKILL.md";        expect fail "extra line not in the patch" "differs"
fresh; echo new > "$W/repo/.claude/skills/demo/ref/NEW.md";         expect fail "extra file not in the patch" "differs"
fresh; rm "$W/repo/.claude/skills/demo/ref/R.md";                   expect fail "missing upstream file" "differs"
fresh; rm "$W/repo/.claude/skills-patches/demo.diff";               expect fail "patch missing, copy changed" "differs"
fresh; echo changed > "$W/repo/.claude/skills/demo/NOTICE.md";      expect ok   "top-level NOTICE.md may differ" "deletion-only patch"
fresh; out=$(bash "$SCRIPT" "$W/up" "../x" "$W/repo" 2>&1); [ $? != 0 ] && { pass=$((pass+1)); echo "PASS  bad name rejected"; } || { failed=$((failed+1)); echo "FAIL bad name"; }; rm -rf "$W"
fresh; echo "hidden" > "$W/repo/.claude/skills/demo/ref/NOTICE.md";  expect fail "nested NOTICE.md is not exempt" "below the top of the folder"
fresh; printf '+npx evil\n' >> "$W/repo/.claude/skills-patches/demo.diff"; expect fail "patch that adds a line" "adds lines"
fresh; printf 'Only in ours/ref: X.md\n' >> "$W/repo/.claude/skills-patches/demo.diff"; expect fail "patch that adds a file" "adds files"
fresh; printf 'Only in upstream/../..: etc\n' >> "$W/repo/.claude/skills-patches/demo.diff"; expect fail "path with .. in the patch" "unsafe path"
echo "$pass passed, $failed failed"
[ "$failed" = 0 ]
