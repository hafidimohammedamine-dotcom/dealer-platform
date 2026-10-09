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
  printf '# Demo\nkeep\n## Install\nnpx bad\n## Use\nkeep2\n' > "$U/SKILL.md"; echo plug > "$U/ref/PLUG.md"; printf 'r1\nr2\n' > "$U/ref/R.md"
  printf '# Demo\nkeep\n## Use\nkeep2\n' > "$O/SKILL.md"; printf 'r1\nr2\n' > "$O/ref/R.md"
  echo notice > "$O/NOTICE.md"; echo mit > "$O/UPSTREAM-LICENSE"
  rec
}
rec() { # (re)write the record .claude/skills-patches/demo.diff the way a founder does
  mkdir -p "$W/repo/.claude/skills-patches"; R="$W/repo/.claude/skills-patches/demo.diff"
  ( cd "$W" && ln -sfn up upstream && ln -sfn repo/.claude/skills/demo ours &&
    diff -ru -a -x NOTICE.md -x UPSTREAM-LICENSE upstream ours ; rm -f upstream ours ) > "$R" || true
}
expect() { # expect <ok|fail> <name> <message>
  out=$(bash "$SCRIPT" "$U" demo "$W/repo" 2>&1); rc=$?; got=$([ $rc = 0 ] && echo ok || echo fail)
  if [ "$got" = "$1" ] && grep -qF -- "$3" <<<"$out"; then pass=$((pass+1)); echo "PASS  $2"
  else failed=$((failed+1)); echo "FAIL  $2 ($got)"; echo "$out"; fi; rm -rf "$W"; }
fresh;                                                   expect ok   "deleted lines and a deleted file" "deletions only (1 upstream file(s) removed)"
fresh; cp "$U/SKILL.md" "$O/SKILL.md"; cp "$U/ref/PLUG.md" "$O/ref/"; : > "$R"; expect ok "identical to upstream (no deletions)" "(0 upstream file(s) removed)"
fresh; echo "npx evil" >> "$O/SKILL.md";                 expect fail "added line" "lines added or changed in SKILL.md"
fresh; printf '# Demo\nkeep\n++ hidden\n## Use\nkeep2\n' > "$O/SKILL.md"; expect fail "added line that starts with ++" "lines added or changed"
fresh; printf '# Demo\n## Use\nkeep2\nkeep\n' > "$O/SKILL.md";           expect fail "reordered lines" "lines added or changed"
fresh; printf '# Demo\nkeep\n## Install\nnpx BAD\n## Use\nkeep2\n' > "$O/SKILL.md";  expect fail "changed line" "lines added or changed"
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
fresh; : > "$O/ref/R.md"; rec;                           expect fail "prose lines removed (file emptied)" "deletions in ref/R.md are not whole units"
fresh; rm "$O/ref/R.md"; mkdir "$O/ref/R.md"; echo x > "$O/ref/R.md/in.md"; expect fail "upstream file is a folder in ours" "file not in upstream: ref/R.md/in.md"
if [ "$(id -u)" != 0 ]; then
  fresh; chmod 000 "$U/ref/R.md";                        expect fail "unreadable upstream file (diff error)" "diff failed on ref/R.md"
else echo "SKIP  unreadable file (running as root; runs in CI)"; fi
# The record .claude/skills-patches/<name>.diff must be today's diff
fresh; rm "$R";                                          expect fail "missing record" "missing or empty record .claude/skills-patches/demo.diff"
fresh; : > "$R";                                         expect fail "zero-byte record while ours differs" "missing or empty record"
fresh; sed -i '/^-npx bad$/d' "$R";                      expect fail "stale record (hunk line removed)" "does not match diff -ru"
fresh; sed -i 's/^-npx bad$/-npx bad\n+npx bad/' "$R";   expect fail "record with an added line" "demo.diff has added lines"
fresh; cp "$U/SKILL.md" "$O/SKILL.md"; cp "$U/ref/PLUG.md" "$O/ref/"; expect fail "record kept after copy equals upstream" "records changes but our copy equals upstream"
fresh; sed -i '1s/^/diff -ru -x OTHER upstream ours\n/' "$R"; sed -i 's/^\(---\|+++\) \(.*\)$/\1 \2\t2026-01-01 00:00:00/' "$R"
                                                         expect ok   "record with timestamps and another diff command line" "demo.diff matches"
# Default repo root (no third argument) is the script's own repo
fresh; mkdir -p "$W/repo/scripts"; cp "$SCRIPT" "$(dirname "$SCRIPT")/check-skill-deletions.py" "$(dirname "$SCRIPT")/check-skills-lib.sh" "$W/repo/scripts/"; out=$(bash "$W/repo/scripts/check-skill-upstream.sh" "$U" demo 2>&1)
if [ $? = 0 ] && grep -q "deletions only" <<<"$out"; then pass=$((pass+1)); echo "PASS  default repo root"; else failed=$((failed+1)); echo "FAIL  default repo root"; echo "$out"; fi; rm -rf "$W"
W=$(mktemp -d "$TMPROOT/su.XXXXXX"); out=$(bash "$SCRIPT" 2>&1); [ $? != 0 ] && { pass=$((pass+1)); echo "PASS  missing arguments"; } || { failed=$((failed+1)); echo "FAIL  missing arguments"; }; rm -rf "$W"
fresh; out=$(bash "$SCRIPT" "$U" "../x" "$W/repo" 2>&1); [ $? != 0 ] && grep -q "bad skill name" <<<"$out" && { pass=$((pass+1)); echo "PASS  bad name rejected"; } || { failed=$((failed+1)); echo "FAIL  bad name"; }; rm -rf "$W"
# Upstream's own NOTICE.md / UPSTREAM-LICENSE are upstream files like any other
fresh; echo up-notice > "$U/NOTICE.md"; echo up-notice > "$O/NOTICE.md"; rec; expect ok "upstream NOTICE.md kept as is" "deletions only"
fresh; echo up-notice > "$U/NOTICE.md"; echo ours > "$O/NOTICE.md"; rec; expect fail "upstream NOTICE.md modified" "lines added or changed in NOTICE.md"
fresh; echo up-lic > "$U/UPSTREAM-LICENSE"; rec;         expect fail "upstream UPSTREAM-LICENSE modified" "lines added or changed in UPSTREAM-LICENSE"
# Deleted files and folders are counted
fresh; printf 'a\0b\n' > "$U/ref/B.bin"; mkdir -p "$U/sub/deep"; echo x > "$U/sub/deep/D.md"; rec; expect ok "deleted binary file and nested folder counted" "(3 upstream file(s) removed)"
# Deletions must not turn a warning into advice
fresh; printf 'keep\n// ❌ WRONG: bypasses access\ncode()\n' > "$U/ref/W.md"; printf 'keep\ncode()\n' > "$O/ref/W.md"; rec; expect fail "removed a warning line from prose" "deletions in ref/W.md are not whole units"
fresh; printf 'keep\nYou must never do this\n' > "$U/ref/W.md"; printf 'keep\n' > "$O/ref/W.md"; rec; expect fail "removed a 'must never' prose line" "not part of a whole section, code block, table row or list item"
fresh; printf 'intro\n```ts\nconst a = 1\nconst b = 2\n```\nend\n' > "$U/ref/C.md"; printf 'intro\n```ts\nconst a = 1\n```\nend\n' > "$O/ref/C.md"; rec; expect fail "part of a code block removed" "upstream line 4: removed line is part of a code block"
fresh; printf 'intro\n```ts\nconst a = 1\n```\nend\n' > "$U/ref/C.md"; printf 'intro\nend\n' > "$O/ref/C.md"; rec; expect ok "whole code block removed" "deletions only"
fresh; printf 'intro\n```ts\nconst a = 1\n```\nend\n' > "$U/ref/C.md"; printf 'intro\nconst a = 1\nend\n' > "$O/ref/C.md"; rec; expect fail "only the fences removed" "removed line is part of a code block"
fresh; rm "$U/ref/PLUG.md"; printf 'Never run this\n' > "$U/ref/PLUG.md"; rec; expect ok "whole file with warning words removed" "deletions only"
# Whole units only (scripts/check-skill-deletions.py)
u() { printf "$1" > "$U/ref/M.md"; printf "$2" > "$O/ref/M.md"; rec; }
fresh; u '# T\nintro\n## A\na1\n### A1\nsub\n## B\nb\n' '# T\nintro\n### A1\nsub\n## B\nb\n'; expect ok "a heading's own body removed, subsection kept" "deletions only"
fresh; u '# T\n## A\na1\na2\n## B\nb\n' '# T\n## A\na1\n## B\nb\n';         expect fail "part of a section removed" "not part of a whole section"
fresh; u '# T\n## A\na1\n## B\nb\n' '# T\na1\n## B\nb\n';                     expect fail "heading removed, body kept" "upstream line 2"
fresh; u 'intro\n- one\n- two\n' 'intro\n- one\n';                            expect ok   "plain list item removed" "deletions only"
fresh; u 'intro\n- Never use overrideAccess\n- two\n' 'intro\n- two\n';       expect fail "list item with a rule word" "table row or list item with a warning or rule word"
fresh; u '| a | b |\n|---|---|\n| x | plain row |\n| y | other |\n' '| a | b |\n|---|---|\n| y | other |\n'; expect ok "plain table row removed" "deletions only"
fresh; u '| a | b |\n|---|---|\n| x | ❌ do not |\n' '| a | b |\n|---|---|\n'; expect fail "table row with a warning mark" "warning or rule word"
fresh; u 'intro\n~~~ts\nconst a = 1\nconst b = 2\n~~~\nend\n' 'intro\n~~~ts\nconst a = 1\n~~~\nend\n'; expect fail "part of a ~~~ block" "part of a code block"
fresh; u 'intro\n````md\n```\ninner\n```\nmore\n````\nend\n' 'intro\n````md\n```\ninner\n```\n````\nend\n'; expect fail "part of a four-backtick block (inner fences do not close it)" "part of a code block"
fresh; u 'intro\n```ts\nconst a = 1\nconst b = 2\n' 'intro\n```ts\nconst a = 1\n'; expect fail "part of an unclosed block" "part of a code block"
fresh; u 'intro\n```ts\nconst a = 1\n' 'intro\n';                            expect ok   "whole unclosed block removed" "deletions only"
fresh; u 'intro\n\n    indented code\n    more\n' 'intro\n\n    indented code\n'; expect fail "indented code line removed" "not part of a whole section"
fresh; u '# T\n```bash\n# not a heading\nrm -rf x\n```\nend\n' '# T\n```bash\n# not a heading\n```\nend\n'; expect fail "a # comment inside code is not a heading" "part of a code block"
fresh; u 'a\n\n\nb\n' 'a\nb\n';                                               expect ok   "blank lines removed" "deletions only"
# Founder-reviewed deletions of sections or blocks with warning words (.claude/skills-patches/<name>.reviewed)
fresh; u '# T\n## Security\nnever do x\n## B\nb\n' '# T\n## B\nb\n'; expect fail "section with a warning word, no reviewed list" "not in the reviewed list (add 'ref/M.md:2'"
fresh; u '# T\n## Security\nnever do x\n## B\nb\n' '# T\n## B\nb\n'; printf 'ref/M.md:2 # links only\n' > "$W/repo/.claude/skills-patches/demo.reviewed"; expect ok "reviewed section is allowed and logged" "REVIEWED ref/M.md:2"
fresh; printf 'ref/M.md:9\n' > "$W/repo/.claude/skills-patches/demo.reviewed"; expect fail "stale reviewed entry" "stale entry in demo.reviewed (no matching deletion): ref/M.md:9"
# A failing diff in the record step fails closed (diff shim fails only for diff -ru)
fresh; mkdir "$W/bin"; printf '#!/bin/sh\n[ "$1" = -ru ] && exit 2\nexec /usr/bin/diff "$@"\n' > "$W/bin/diff"; chmod +x "$W/bin/diff"
out=$(PATH="$W/bin:$PATH" bash "$SCRIPT" "$U" demo "$W/repo" 2>&1); rc=$?
if [ $rc != 0 ] && grep -q "diff of upstream and ours failed (exit 2)" <<<"$out"; then pass=$((pass+1)); echo "PASS  record diff error fails"; else failed=$((failed+1)); echo "FAIL  record diff error"; echo "$out"; fi; rm -rf "$W"
echo "$pass passed, $failed failed"
[ "$failed" = 0 ]
