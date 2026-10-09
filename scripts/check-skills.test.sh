#!/usr/bin/env bash
# Tests scripts/check-skills.sh on a small fixture (not on the live skills), checking exit code and message.
set -uo pipefail
SCRIPT="$(cd "$(dirname "$0")" && pwd)/check-skills.sh"
TMPROOT="${TMPDIR:-/tmp}"
pass=0; failed=0
fresh() {
  T=$(mktemp -d "$TMPROOT/cs.XXXXXX") || { echo "mktemp failed"; exit 2; }
  S="$T/.claude/skills"; A="$T/.claude/agents"; mkdir -p "$S/alpha/reference" "$S/beta" "$A"
  SHA=0123456789abcdef0123456789abcdef01234567
  printf 'alpha third-party requires=beta\nbeta ours\n' > "$S/manifest.txt"
  printf '| Skill | Source | Commit |\n|---|---|---|\n| alpha | example/repo | %s |\n' "$SHA" > "$S/SKILLS-LOCK.md"
  printf -- '---\nname: alpha\n---\na\n' > "$S/alpha/SKILL.md"; echo r > "$S/alpha/reference/R.md"
  printf 'Upstream commit: %s\n' "$SHA" > "$S/alpha/NOTICE.md"; echo MIT > "$S/alpha/UPSTREAM-LICENSE"
  printf -- '---\nname: "beta"\n---\nb\n' > "$S/beta/SKILL.md"
  printf -- '---\nname: builder\nskills: alpha, beta\n---\nx\n' > "$A/builder.md"
  printf -- '---\nname: other\n---\nno skills\n' > "$A/other.md"
  bash "$SCRIPT" --write "$T" >/dev/null || { echo "fixture --write failed"; bash "$SCRIPT" --write "$T"; exit 2; }
}
expect() { # expect <ok|fail> <name> <message-substring>
  out=$(bash "$SCRIPT" "$T" 2>&1); rc=$?
  got=$([ $rc = 0 ] && echo ok || echo fail)
  if [ "$got" = "$1" ] && grep -qF -- "$3" <<<"$out"; then pass=$((pass+1)); echo "PASS  $2"
  else failed=$((failed+1)); echo "FAIL  $2 (expected $1 with '$3', got $got)"; echo "$out"; fi
  rm -rf "$T"
}
fresh;                                                       expect ok   "clean fixture passes" "Skills OK (5 files)"
fresh; echo x >> "$S/alpha/reference/R.md";                 expect fail "changed file" "changed files"
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
fresh; echo "gamma maybe" >> "$S/manifest.txt"; mkdir "$S/gamma"; printf -- '---\nname: gamma\n---\n' > "$S/gamma/SKILL.md"; expect fail "bad kind" "needs kind"
fresh; echo x > "$S/alpha/with space.md"; bash "$SCRIPT" --write "$T" >/dev/null; expect ok "space in name after --write" "Skills OK (6 files)"
fresh; echo x >> "$S/alpha/reference/R.md"; bash "$SCRIPT" --write "$T" >/dev/null; expect ok "--write then check" "Skills OK"
fresh; rm "$S/alpha/NOTICE.md"; bash "$SCRIPT" --write "$T" >/dev/null; expect fail "third-party without NOTICE.md" "has no NOTICE.md"
fresh; printf '| Skill | Source |\n|---|---|\n| alphabet | x | %s |\n' "$SHA" > "$S/SKILLS-LOCK.md"; expect fail "third-party without lock row (no prefix match)" "no row in SKILLS-LOCK.md"
fresh; rm "$S/SKILLS-LOCK.md"; expect fail "third-party with no SKILLS-LOCK.md" "no row in SKILLS-LOCK.md"
fresh; printf '| Skill | Source |\n|---|---|\n| gamma, alpha | x | %s |\n' "$SHA" > "$S/SKILLS-LOCK.md"; expect ok "lock row listing several skills" "Skills OK"
fresh; rm "$S/alpha/UPSTREAM-LICENSE"; bash "$SCRIPT" --write "$T" >/dev/null; expect fail "third-party without license file" "no license file"
fresh; printf 'Upstream commit: %s\n' fedcba9876543210fedcba9876543210fedcba98 > "$S/alpha/NOTICE.md"; bash "$SCRIPT" --write "$T" >/dev/null; expect fail "NOTICE commit differs from lock" "differs between SKILLS-LOCK.md and NOTICE.md"
fresh; printf '| Skill | Source |\n|---|---|\n| alpha | x | abc123 |\n' > "$S/SKILLS-LOCK.md"; expect fail "lock row with a short commit" "no full 40-character commit"
fresh; printf -- '---\nname: alfa\n---\na\n' > "$S/alpha/SKILL.md"; bash "$SCRIPT" --write "$T" >/dev/null; expect fail "front matter name differs from folder" "front matter name is 'alfa'"
fresh; printf -- '---\nname: builder\nskills: alpha, beta, gama\n---\n' > "$A/builder.md"; expect fail "agent preloads a misspelled skill" "skill 'gama' is not in the manifest"
fresh; printf -- '---\nname: builder\nskills: alpha\n---\n' > "$A/builder.md"; expect fail "agent loads a skill without its required override" "'alpha' must be loaded together with 'beta'"
fresh; printf -- '---\nname: builder\nskills: beta\n---\n' > "$A/builder.md"; expect ok "agent loads only the override" "Skills OK"
fresh; sed -i 's/requires=beta/requires=delta/' "$S/manifest.txt"; expect fail "requires names an unknown skill" "requires 'delta'"
fresh; sed -i 's/requires=beta/needs=beta/' "$S/manifest.txt"; expect fail "unknown manifest option" "unknown option"
fresh; rm -rf "$A";                                            expect fail "missing .claude/agents" "missing .claude/agents"
fresh; rm "$A"/*.md;                                          expect ok   "agents folder with no .md files" "Skills OK"
fresh; printf -- '---\nname: builder\nskills:\n  - alpha\n  - beta\n---\n' > "$A/builder.md"; expect fail "skills as a YAML block list" "one-line comma list"
fresh; printf -- '---\nname: builder\nskills:\n---\n' > "$A/builder.md"; expect fail "empty skills line" "one-line comma list"
fresh; printf -- '---\nname: builder\nskills: [alpha, beta]\n---\n' > "$A/builder.md"; expect fail "skills in brackets" "one-line comma list"
fresh; rm "$S/beta/SKILL.md"; echo x > "$S/beta/README.md"; bash "$SCRIPT" --write "$T" >/dev/null; expect fail "skill folder without SKILL.md" "has no SKILL.md"
fresh; echo "no front matter" > "$S/beta/SKILL.md"; bash "$SCRIPT" --write "$T" >/dev/null; expect fail "SKILL.md without front matter" "front matter name is ''"
fresh; printf -- "---\nname: 'beta'\n---\n" > "$S/beta/SKILL.md"; bash "$SCRIPT" --write "$T" >/dev/null; expect ok "single-quoted name" "Skills OK"
fresh; echo "no commit here" > "$S/alpha/NOTICE.md"; bash "$SCRIPT" --write "$T" >/dev/null; expect fail "NOTICE.md without a commit" "NOTICE.md for 'alpha' has no full 40-character commit"
fresh; printf 'Upstream commit: %s\n' "$(tr 'a-f' 'A-F' <<<"$SHA")" > "$S/alpha/NOTICE.md"; bash "$SCRIPT" --write "$T" >/dev/null; expect ok "uppercase hex commit matches" "Skills OK"
fresh; mv "$S/alpha/UPSTREAM-LICENSE" "$S/alpha/LICENCE.txt"; bash "$SCRIPT" --write "$T" >/dev/null; expect ok "license name variant LICENCE.txt" "Skills OK"
fresh; rm "$S/alpha/UPSTREAM-LICENSE"; echo MIT > "$S/alpha/reference/LICENSE"; bash "$SCRIPT" --write "$T" >/dev/null; expect fail "license only in a subfolder" "has no license file"
fresh; : > "$S/alpha/UPSTREAM-LICENSE"; bash "$SCRIPT" --write "$T" >/dev/null; expect fail "empty license file" "has no license file"
fresh; mv "$S/alpha/UPSTREAM-LICENSE" "$S/alpha/license-notes.md"; bash "$SCRIPT" --write "$T" >/dev/null; expect fail "license-notes.md is not a license" "has no license file"
fresh; sed -i 's/requires=beta/requires=beta extra=1/' "$S/manifest.txt"; expect fail "second unknown manifest option" "unknown option 'extra=1'"
fresh; printf -- '---\nname: builder\nskills: alpha, beta\nskills: alpha\n---\n' > "$A/builder.md"; expect fail "duplicate skills lines" "more than one 'skills:' line"
echo "$pass passed, $failed failed"
[ "$failed" = 0 ]
