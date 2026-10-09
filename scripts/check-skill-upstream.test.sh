#!/usr/bin/env bash
# Tests scripts/check-skill-upstream.sh with a small fixture skill.
set -uo pipefail
SCRIPT="$(cd "$(dirname "$0")" && pwd)/check-skill-upstream.sh"
TMPROOT="${TMPDIR:-/tmp}"
pass=0; failed=0
fresh() {
  W=$(mktemp -d "$TMPROOT/su.XXXXXX") || exit 2
  U="$W/up"; O="$W/repo/.claude/skills/demo"
  mkdir -p "$U/ref" "$O/ref"
  printf 'keep\nnpx bad\nkeep2\n' > "$U/SKILL.md"; echo plug > "$U/ref/PLUG.md"; printf 'r1\nr2\n' > "$U/ref/R.md"
  printf 'keep\nkeep2\n' > "$O/SKILL.md"; printf 'r1\nr2\n' > "$O/ref/R.md"
  echo notice > "$O/NOTICE.md"; echo mit > "$O/UPSTREAM-LICENSE"
  rec
}
rec() { # (re)write the record .claude/skills-patches/demo.diff the way a founder does
  mkdir -p "$W/repo/.claude/skills-patches"; R="$W/repo/.claude/skills-patches/demo.diff"
  ( cd "$W" && ln -sfn up upstream && ln -sfn repo/.claude/skills/demo ours &&
    diff -ru -x NOTICE.md -x UPSTREAM-LICENSE upstream/ ours/ | sed -E 's#^(---|\+\+\+) (upstream|ours)//#\1 \2/#' ; rm -f upstream ours ) > "$R" || true
}
expect() { # expect <ok|fail> <name> <message>
  out=$(bash "$SCRIPT" "$U" demo "$W/repo" 2>&1); rc=$?; got=$([ $rc = 0 ] && echo ok || echo fail)
  if [ "$got" = "$1" ] && grep -qF -- "$3" <<<"$out"; then pass=$((pass+1)); echo "PASS  $2"
  else failed=$((failed+1)); echo "FAIL  $2 ($got)"; echo "$out"; fi; rm -rf "$W"; }
fresh;                                                   expect ok   "deleted lines and a deleted file" "deletions only (1 upstream file(s) removed)"
fresh; cp "$U/SKILL.md" "$O/SKILL.md"; cp "$U/ref/PLUG.md" "$O/ref/"; : > "$R"; expect ok "identical to upstream (no deletions)" "(0 upstream file(s) removed)"
fresh; echo "npx evil" >> "$O/SKILL.md";                 expect fail "added line" "lines added or changed in SKILL.md"
fresh; printf 'keep\n++ hidden\nkeep2\n' > "$O/SKILL.md"; expect fail "added line that starts with ++" "lines added or changed"
fresh; printf 'keep2\nkeep\n' > "$O/SKILL.md";           expect fail "reordered lines" "lines added or changed"
fresh; printf 'keep\nnpx BAD\nkeep2\n' > "$O/SKILL.md";  expect fail "changed line" "lines added or changed"
fresh; echo new > "$O/ref/NEW.md";                       expect fail "added file" "file not in upstream: ref/NEW.md"
fresh; echo hidden > "$O/ref/NOTICE.md";                 expect fail "nested NOTICE.md is not exempt" "file not in upstream: ref/NOTICE.md"
fresh; echo changed > "$O/NOTICE.md";                    expect ok   "top-level NOTICE.md is ours" "deletions only"
fresh; ln -s /etc/hostname "$O/ref/link.md";             expect fail "symlink in our copy" "not a regular file or folder"
fresh; ln -s /etc/hostname "$U/ref/link.md";             expect fail "symlink in upstream" "not a regular file or folder"
fresh; rm -rf "$U";                                      expect fail "missing upstream dir" "upstream dir not found"
fresh; rm -rf "$O";                                      expect fail "missing skill folder" "no skill folder"
# Nested or extra "our" files are not exempt
fresh; mkdir "$O/UPSTREAM-LICENSE-x"; echo evil > "$O/UPSTREAM-LICENSE-x/evil.md"; expect fail "nested file under an UPSTREAM-LICENSE-* folder" "file not in upstream: UPSTREAM-LICENSE-x/evil.md"
fresh; echo 'npx evil' > "$O/UPSTREAM-LICENSE-other.md"; expect fail "top-level UPSTREAM-LICENSE-other.md with any content" "file not in upstream: UPSTREAM-LICENSE-other.md"
fresh; echo mit > "$O/UPSTREAM-LICENSE.md";              expect fail "two UPSTREAM-LICENSE files" "more than one UPSTREAM-LICENSE file"
# Line-level edge cases
fresh; printf 'r1\r\nr2\n' > "$O/ref/R.md";            expect fail "CRLF added to a line" "lines added or changed in ref/R.md"
fresh; printf 'r1 \nr2\n' > "$O/ref/R.md";              expect fail "whitespace-only change" "lines added or changed in ref/R.md"
fresh; printf 'a\0b\nc\n' > "$U/ref/B.bin"; printf 'a\0b\nX\0\nc\n' > "$O/ref/B.bin"; rec; expect fail "added line in a binary file" "lines added or changed in ref/B.bin"
fresh; : > "$O/ref/R.md"; rec;                           expect ok   "file emptied in ours (all lines deleted)" "deletions only"
fresh; rm "$O/ref/R.md"; mkdir "$O/ref/R.md"; echo x > "$O/ref/R.md/in.md"; expect fail "upstream file is a folder in ours" "file not in upstream: ref/R.md/in.md"
if [ "$(id -u)" != 0 ]; then
  fresh; chmod 000 "$U/ref/R.md";                        expect fail "unreadable upstream file (diff error)" "diff failed on ref/R.md"
else echo "SKIP  unreadable file (running as root; runs in CI)"; fi
# The record .claude/skills-patches/<name>.diff must be today's diff
fresh; rm "$R";                                          expect fail "missing record" "missing record .claude/skills-patches/demo.diff"
fresh; sed -i '/^-npx bad$/d' "$R";                      expect fail "stale record (hunk line removed)" "does not match diff -ru"
fresh; sed -i 's/^-npx bad$/-npx bad\n+npx bad/' "$R";   expect fail "record with an added line" "demo.diff has added lines"
fresh; cp "$U/SKILL.md" "$O/SKILL.md"; cp "$U/ref/PLUG.md" "$O/ref/"; expect fail "record kept after copy equals upstream" "records changes but our copy equals upstream"
fresh; sed -i '1s/^/diff -ru -x OTHER upstream ours\n/' "$R"; sed -i 's/^\(---\|+++\) \(.*\)$/\1 \2\t2026-01-01 00:00:00/' "$R"
                                                         expect ok   "record with timestamps and another diff command line" "demo.diff matches"
# Default repo root (no third argument) is the script's own repo
fresh; mkdir -p "$W/repo/scripts"; cp "$SCRIPT" "$W/repo/scripts/"; out=$(bash "$W/repo/scripts/check-skill-upstream.sh" "$U" demo 2>&1)
if [ $? = 0 ] && grep -q "deletions only" <<<"$out"; then pass=$((pass+1)); echo "PASS  default repo root"; else failed=$((failed+1)); echo "FAIL  default repo root"; echo "$out"; fi; rm -rf "$W"
W=$(mktemp -d "$TMPROOT/su.XXXXXX"); out=$(bash "$SCRIPT" 2>&1); [ $? != 0 ] && { pass=$((pass+1)); echo "PASS  missing arguments"; } || { failed=$((failed+1)); echo "FAIL  missing arguments"; }; rm -rf "$W"
fresh; out=$(bash "$SCRIPT" "$U" "../x" "$W/repo" 2>&1); [ $? != 0 ] && grep -q "bad skill name" <<<"$out" && { pass=$((pass+1)); echo "PASS  bad name rejected"; } || { failed=$((failed+1)); echo "FAIL  bad name"; }; rm -rf "$W"
echo "$pass passed, $failed failed"
[ "$failed" = 0 ]
