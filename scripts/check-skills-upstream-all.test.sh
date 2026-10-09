#!/usr/bin/env bash
# Tests scripts/check-skills-upstream-all.sh with a local file:// upstream repo (no network).
set -uo pipefail
SCRIPT="$(cd "$(dirname "$0")" && pwd)/check-skills-upstream-all.sh"
TMPROOT="${TMPDIR:-/tmp}"
pass=0; failed=0
fresh() {
  W=$(mktemp -d "$TMPROOT/sua.XXXXXX") || exit 2
  U="$W/hub/acme/tools"; mkdir -p "$U/skills/demo"
  ( cd "$U" && git init -q -b main . && git config user.email t@t && git config user.name t
    printf 'keep\nnpx bad\n' > skills/demo/SKILL.md; echo other > README.md; git add -A; git commit -qm up )
  SHA=$(git -C "$U" rev-parse HEAD)
  R="$W/repo"; S="$R/.claude/skills"; mkdir -p "$S/demo" "$R/.claude/skills-patches"
  printf 'keep\n' > "$S/demo/SKILL.md"; echo n > "$S/demo/NOTICE.md"; echo mit > "$S/demo/UPSTREAM-LICENSE"
  printf 'demo third-party requires=ovr\novr ours\n' > "$S/manifest.txt"
  printf '| Skill | Source | Commit |\n|---|---|---|\n| demo | acme/tools `skills/demo`, tag v1 | %s |\n' "$SHA" > "$S/SKILLS-LOCK.md"
  printf -- '--- upstream/SKILL.md\n+++ ours/SKILL.md\n@@ -1,2 +1 @@\n keep\n-npx bad\n' > "$R/.claude/skills-patches/demo.diff"
}
expect() { out=$(UPSTREAM_BASE="file://$W/hub/" bash "$SCRIPT" "$R" "$W/work" 2>&1); rc=$?; got=$([ $rc = 0 ] && echo ok || echo fail)
  if [ "$got" = "$1" ] && grep -qF -- "$3" <<<"$out"; then pass=$((pass+1)); echo "PASS  $2"; else failed=$((failed+1)); echo "FAIL  $2 ($got)"; echo "$out"; fi; rm -rf "$W"; }
fresh;                                                    expect ok   "pinned upstream, deletions only" "Upstream check OK for 1 third-party skill(s)"
fresh; echo 'npx evil' >> "$S/demo/SKILL.md";             expect fail "added line found against the real upstream" "lines added or changed in SKILL.md"
fresh; sed -i "s/$SHA/$(printf '%040d' 0)/" "$S/SKILLS-LOCK.md"; expect fail "commit that does not exist upstream" "could not fetch acme/tools"
fresh; sed -i 's/`skills\/demo`/`skills\/other`/' "$S/SKILLS-LOCK.md"; expect fail "wrong path in the lock row" "upstream dir not found"
fresh; sed -i 's/`skills\/demo`/`..\/x`/' "$S/SKILLS-LOCK.md"; expect fail "path with .. rejected" "must read"
fresh; sed -i 's/| demo |/| nodemo |/' "$S/SKILLS-LOCK.md"; expect fail "missing lock row" "needs exactly one SKILLS-LOCK.md row"
fresh; sed -i 's/acme\/tools `/acme `/' "$S/SKILLS-LOCK.md"; expect fail "malformed source cell" "must read"
fresh; printf 'ovr ours\n' > "$S/manifest.txt";           expect ok   "no third-party skills" "Upstream check OK for 0 third-party skill(s)"
fresh; rm "$S/manifest.txt";                              expect fail "missing manifest" "missing"
echo "$pass passed, $failed failed"
[ "$failed" = 0 ]
