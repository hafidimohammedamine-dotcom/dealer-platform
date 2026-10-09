#!/usr/bin/env bash
# Tests scripts/check-skills.sh on a small fixture (not on the live skills), checking exit code and message.
set -uo pipefail
SCRIPT="$(cd "$(dirname "$0")" && pwd)/check-skills.sh"
TMPROOT="${TMPDIR:-/tmp}"
pass=0; failed=0
fresh() {
  T=$(mktemp -d "$TMPROOT/cs.XXXXXX") || { echo "mktemp failed"; exit 2; }
  S="$T/.claude/skills"; mkdir -p "$S/alpha/reference" "$S/beta"
  printf 'alpha third-party\nbeta ours\n' > "$S/manifest.txt"
  printf '| Skill | Source |\n|---|---|\n| alpha | example/repo |\n' > "$S/SKILLS-LOCK.md"
  echo a > "$S/alpha/SKILL.md"; echo r > "$S/alpha/reference/R.md"; echo n > "$S/alpha/NOTICE.md"; echo b > "$S/beta/SKILL.md"
  bash "$SCRIPT" --write "$T" >/dev/null || { echo "fixture --write failed"; exit 2; }
}
expect() { # expect <ok|fail> <name> <message-substring>
  out=$(bash "$SCRIPT" "$T" 2>&1); rc=$?
  got=$([ $rc = 0 ] && echo ok || echo fail)
  if [ "$got" = "$1" ] && grep -qF -- "$3" <<<"$out"; then pass=$((pass+1)); echo "PASS  $2"
  else failed=$((failed+1)); echo "FAIL  $2 (expected $1 with '$3', got $got)"; echo "$out"; fi
  rm -rf "$T"
}
fresh;                                                       expect ok   "clean fixture passes" "Skills OK (4 files)"
fresh; echo x >> "$S/alpha/SKILL.md";                        expect fail "changed file" "changed files"
fresh; echo x >> "$S/alpha/NOTICE.md";                       expect fail "changed NOTICE.md" "changed files"
fresh; echo x > "$S/alpha/reference/NOTICE.md";              expect fail "added NOTICE.md deeper" "files added"
fresh; echo x > "$S/alpha/.hidden";                          expect fail "added dotfile in a skill" "files added"
fresh; mv "$S/alpha/reference/R.md" "$S/alpha/reference/R2.md"; expect fail "renamed file" "files removed or renamed"
fresh; rm "$S/beta/SKILL.md"; rmdir "$S/beta";               expect fail "removed skill folder" "folder is missing"
fresh; mv "$S/beta" "$S/gamma";                              expect fail "renamed skill folder" "not in manifest: gamma"
fresh; mkdir "$S/evil"; echo x > "$S/evil/SKILL.md";         expect fail "unknown folder" "not in manifest: evil"
fresh; mkdir "$S/.hidden-skill"; echo x > "$S/.hidden-skill/a"; expect fail "top-level dot folder" "not in manifest: .hidden-skill"
fresh; mkdir "$S/alpha/empty";                               expect fail "empty folder" "empty folder"
fresh; ln -s /etc/hostname "$S/alpha/link.md";               expect fail "symlink" "symlink not allowed"
fresh; mkfifo "$S/alpha/pipe";                               expect fail "FIFO" "special file"
fresh; echo x > "$S/stray.md";                               expect fail "stray top-level file" "unexpected file"
fresh; echo x > "$S/alpha/we\\ird.md";                       expect fail "backslash in name" "backslash"
fresh; echo x > "$S/alpha/new
line.md";                                                    expect fail "newline in name" "newline"
fresh; rm "$S/checksums.sha256";                             expect fail "missing checksums" "missing"
fresh; rm "$S/manifest.txt";                                 expect fail "missing manifest" "missing"
fresh; echo "gamma maybe" >> "$S/manifest.txt"; mkdir "$S/gamma"; echo x > "$S/gamma/SKILL.md"; expect fail "bad kind" "needs kind"
fresh; echo x > "$S/alpha/with space.md"; bash "$SCRIPT" --write "$T" >/dev/null; expect ok "space in name after --write" "Skills OK (5 files)"
fresh; echo x >> "$S/alpha/SKILL.md"; bash "$SCRIPT" --write "$T" >/dev/null; expect ok "--write then check" "Skills OK"
fresh; rm "$S/alpha/NOTICE.md"; bash "$SCRIPT" --write "$T" >/dev/null; expect fail "third-party without NOTICE.md" "has no NOTICE.md"
fresh; printf '| Skill | Source |\n|---|---|\n| alphabet | x |\n' > "$S/SKILLS-LOCK.md"; expect fail "third-party without lock row (no prefix match)" "no row in SKILLS-LOCK.md"
fresh; rm "$S/SKILLS-LOCK.md"; expect fail "third-party with no SKILLS-LOCK.md" "no row in SKILLS-LOCK.md"
fresh; printf '| Skill | Source |\n|---|---|\n| gamma, alpha | x |\n' > "$S/SKILLS-LOCK.md"; expect ok "lock row listing several skills" "Skills OK"
echo "$pass passed, $failed failed"
[ "$failed" = 0 ]
