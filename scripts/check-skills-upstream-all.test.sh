#!/usr/bin/env bash
# Tests scripts/check-skills-upstream-all.sh with a local file:// upstream repo (no network).
set -uo pipefail
SCRIPT="$(cd "$(dirname "$0")" && pwd)/check-skills-upstream-all.sh"
TMPROOT="${TMPDIR:-/tmp}"
pass=0; failed=0
fresh() {
  W=$(mktemp -d "$TMPROOT/sua.XXXXXX") || exit 2
  U="$W/hub/acme/tools"; mkdir -p "$U/skills/demo"
  ( cd "$U" && git init -q -b main . && git config uploadpack.allowFilter true && git config user.email t@t && git config user.name t
    printf '# Demo\nkeep\n## Install\nnpx bad\n' > skills/demo/SKILL.md; echo other > README.md; git add -A; git commit -qm up )
  SHA=$(git -C "$U" rev-parse HEAD)
  R="$W/repo"; S="$R/.claude/skills"; mkdir -p "$S/demo" "$R/.claude/skills-patches"
  printf '# Demo\nkeep\n' > "$S/demo/SKILL.md"; echo n > "$S/demo/NOTICE.md"; echo mit > "$S/demo/UPSTREAM-LICENSE"
  printf 'demo third-party requires=ovr\novr ours\n' > "$S/manifest.txt"
  printf '| Skill | Source | Commit |\n|---|---|---|\n| demo | acme/tools `skills/demo`, tag v1 | %s |\n' "$SHA" > "$S/SKILLS-LOCK.md"
  printf -- '--- upstream/SKILL.md\n+++ ours/SKILL.md\n@@ -1,4 +1,2 @@\n # Demo\n keep\n-## Install\n-npx bad\n' > "$R/.claude/skills-patches/demo.diff"
}
expect() { out=$(UPSTREAM_BASE="file://$W/hub/" bash "$SCRIPT" "$R" "$W/work" 2>&1); rc=$?; got=$([ $rc = 0 ] && echo ok || echo fail)
  if [ "$got" = "$1" ] && grep -qF -- "$3" <<<"$out"; then pass=$((pass+1)); echo "PASS  $2"; else failed=$((failed+1)); echo "FAIL  $2 ($got)"; echo "$out"; fi; rm -rf "$W"; }
fresh;                                                    expect ok   "pinned upstream, deletions only" "Upstream check OK for 1 third-party skill(s)"
fresh; echo 'npx evil' >> "$S/demo/SKILL.md";             expect fail "added line found against the real upstream" "lines added or changed in SKILL.md"
fresh; sed -i "s/$SHA/$(printf '%040d' 0)/" "$S/SKILLS-LOCK.md"; expect fail "commit that does not exist upstream" "could not fetch acme/tools"
fresh; sed -i 's/`skills\/demo`/`skills\/other`/' "$S/SKILLS-LOCK.md"; expect fail "wrong path in the lock row" "upstream dir not found"
fresh; sed -i 's/`skills\/demo`/`..\/x`/' "$S/SKILLS-LOCK.md"; expect fail "path with .. rejected" "must read"
fresh; sed -i 's/| demo |/| nodemo |/' "$S/SKILLS-LOCK.md"; expect fail "missing lock row" "has no row in SKILLS-LOCK.md"
fresh; sed -i 's/acme\/tools `/acme `/' "$S/SKILLS-LOCK.md"; expect fail "malformed source cell" "must read"
fresh; printf 'ovr ours\n' > "$S/manifest.txt";           expect ok   "no third-party skills" "Upstream check OK for 0 third-party skill(s)"
fresh; rm "$S/manifest.txt";                              expect fail "missing manifest" "missing"
fresh; printf '# demo third-party is pinned below\n\n#old third-party\n' | cat - "$S/manifest.txt" > "$W/m" && mv "$W/m" "$S/manifest.txt"; expect ok "manifest comments and blank lines are skipped" "Upstream check OK for 1 third-party skill(s)"
fresh; echo 'Bad_Name third-party requires=ovr' >> "$S/manifest.txt"; expect fail "bad skill name in the manifest" "bad skill name 'Bad_Name'"
fresh; printf '| demo | acme/tools `skills/demo` | %s |\n' "$SHA" >> "$S/SKILLS-LOCK.md"; expect fail "two lock rows for one skill" "has more than one row in SKILLS-LOCK.md"
fresh; sed -i "s/$SHA/${SHA:0:12}/" "$S/SKILLS-LOCK.md";  expect fail "short commit" "must read"
fresh; sed -i "s/$SHA/$(printf 'z%.0s' {1..40})/" "$S/SKILLS-LOCK.md"; expect fail "non-hex commit" "must read"
fresh; sed -i "s/$SHA/$(tr 'a-f' 'A-F' <<<"$SHA")/" "$S/SKILLS-LOCK.md"; expect fail "upper-case commit (same rule as check-skills.sh)" "must read"
fresh; sed -i 's/`skills\/demo`/`\/skills\/demo`/' "$S/SKILLS-LOCK.md"; expect fail "absolute path rejected" "must read"
fresh; printf '| demo, x | acme/tools `skills/demo` | %s |\n' "$SHA" > "$S/SKILLS-LOCK.md"; expect fail "lock row is matched on the exact first cell" "has no row in SKILLS-LOCK.md"
fresh; sed -i '/^ keep$/d' "$R/.claude/skills-patches/demo.diff"; expect fail "stale .diff record, through the whole script" "demo.diff does not match"
fresh; rm "$S/SKILLS-LOCK.md";                            expect fail "third-party skill but no lock file" "(no SKILLS-LOCK.md file)"
fresh; rm "$S/SKILLS-LOCK.md"; printf 'ovr ours\n' > "$S/manifest.txt"; expect ok "no lock file needed without third-party skills" "OK for 0 third-party"
# Two third-party skills: one passes, one fails -> overall fail, and both are checked
fresh; mkdir -p "$S/demo2"; cp "$S/demo/"* "$S/demo2/"; echo 'npx evil' >> "$S/demo2/SKILL.md"; cp "$R/.claude/skills-patches/demo.diff" "$R/.claude/skills-patches/demo2.diff"
printf 'demo2 third-party requires=ovr\n' >> "$S/manifest.txt"; printf '| demo2 | acme/tools `skills/demo`, tag v1 | %s |\n' "$SHA" >> "$S/SKILLS-LOCK.md"
out=$(UPSTREAM_BASE="file://$W/hub/" bash "$SCRIPT" "$R" "$W/work" 2>&1); rc=$?
if [ $rc != 0 ] && grep -q "OK: .claude/skills/demo = upstream" <<<"$out" && grep -q "lines added or changed in SKILL.md" <<<"$out" && ! grep -q "Upstream check OK" <<<"$out"; then
  pass=$((pass+1)); echo "PASS  one of two skills fails -> overall fail, both checked"; else failed=$((failed+1)); echo "FAIL  two skills"; echo "$out"; fi; rm -rf "$W"
fresh; mkdir -p "$S/demo2"; cp "$S/demo/"* "$S/demo2/"; cp "$R/.claude/skills-patches/demo.diff" "$R/.claude/skills-patches/demo2.diff"
printf 'demo2 third-party requires=ovr\n' >> "$S/manifest.txt"; printf '| demo2 | acme/tools `skills/demo`, tag v1 | %s |\n' "$SHA" >> "$S/SKILLS-LOCK.md"
                                                          expect ok   "two passing skills are counted" "Upstream check OK for 2 third-party skill(s)"
echo "$pass passed, $failed failed"
[ "$failed" = 0 ]
