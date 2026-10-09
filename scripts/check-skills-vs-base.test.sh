#!/usr/bin/env bash
# Tests scripts/check-skills-vs-base.sh with a base and a PR fixture.
set -uo pipefail
SCRIPT="$(cd "$(dirname "$0")" && pwd)/check-skills-vs-base.sh"
TMPROOT="${TMPDIR:-/tmp}"
pass=0; failed=0
SHA=0123456789abcdef0123456789abcdef01234567
SHA2=fedcba9876543210fedcba9876543210fedcba98
side() { # side <root> <manifest text> <lock rows>
  mkdir -p "$1/.claude/skills/payload" "$1/.claude/skills/ovr"
  printf "$2" > "$1/.claude/skills/manifest.txt"
  printf '| Skill | Source | Commit |\n|---|---|---|\n'"$3" > "$1/.claude/skills/SKILLS-LOCK.md"
}
fresh() {
  W=$(mktemp -d "$TMPROOT/svb.XXXXXX") || exit 2; B="$W/base"; P="$W/pr"
  side "$B" '# skills\npayload third-party requires=ovr\novr ours\n' "| payload | payloadcms/payload \`skills/payload\`, tag v1 | $SHA |\n"
  side "$P" '# skills\npayload third-party requires=ovr\novr ours\n' "| payload | payloadcms/payload \`skills/payload\`, tag v1 | $SHA |\n"
}
expect() { out=$(bash "$SCRIPT" "$B" "$P" 2>&1); rc=$?; got=$([ $rc = 0 ] && echo ok || echo fail)
  if [ "$got" = "$1" ] && grep -qF -- "$3" <<<"$out"; then pass=$((pass+1)); echo "PASS  $2"; else failed=$((failed+1)); echo "FAIL  $2 ($got)"; echo "$out"; fi; rm -rf "$W"; }
fresh;                                                         expect ok   "unchanged" "Third-party skills vs base OK"
fresh; sed -i 's/^payload third-party requires=ovr$/payload ours/' "$P/.claude/skills/manifest.txt"; expect fail "third-party turned into ours" "is now listed as 'ours'"
fresh; sed -i "s/$SHA/$SHA2/" "$P/.claude/skills/SKILLS-LOCK.md";  expect ok   "commit update is logged" "CHANGED third-party skill 'payload': payloadcms/payload skills/payload $SHA -> payloadcms/payload skills/payload $SHA2"
fresh; sed -i 's#payloadcms/payload `#evil/payload `#' "$P/.claude/skills/SKILLS-LOCK.md"; expect fail "source repo moved to a fork" "changed its source repo (payloadcms/payload -> evil/payload)"
fresh; sed -i '/^payload/d' "$P/.claude/skills/manifest.txt"; rm -rf "$P/.claude/skills/payload"; expect ok "removed skill is logged" "REMOVED third-party skill 'payload'"
fresh; sed -i '/^payload/d' "$P/.claude/skills/manifest.txt";  expect fail "removed from the manifest, folder kept" "removed from the manifest but its folder is still there"
fresh; printf 'other third-party requires=ovr\n' >> "$P/.claude/skills/manifest.txt"; printf "| other | a/b \`x\` | $SHA2 |\n" >> "$P/.claude/skills/SKILLS-LOCK.md"; expect ok "new third-party skill is logged" "NEW third-party skill 'other': a/b x $SHA2"
fresh; rm "$P/.claude/skills/SKILLS-LOCK.md";                   expect ok   "missing PR lock is logged (check-skills fails it)" "CHANGED third-party skill 'payload': payloadcms/payload skills/payload $SHA -> ?"
fresh; rm -rf "$B/.claude";                                     expect ok   "no skills on the base" "NEW third-party skill 'payload'"
echo "$pass passed, $failed failed"
[ "$failed" = 0 ]
