#!/usr/bin/env bash
# Tests scripts/check-review-prepare.sh against a local bare "remote" with a refs/pull/<n>/head ref.
set -uo pipefail
SCRIPT="$(cd "$(dirname "$0")" && pwd)/check-review-prepare.sh"
TMPROOT="${TMPDIR:-/tmp}"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-testlib.sh"
ok()  { t PASS "$1"; }
bad() { t FAIL "$1"; [ -n "${2:-}" ] && echo "$2"; }
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
out=$(bash "$SCRIPT" 7 "$W/pm" main 2>&1); rc=$?
[ $rc = 0 ] && grep -qF "history written to $W/pm-meta" <<<"$out" && ok "writes the history files with a base ref" || bad "history files" "$out"
grep -qx "A	src/b.ts" "$W/pm-meta/files.txt" 2>/dev/null && grep -q '^+new' "$W/pm-meta/diff.patch" && grep -q ' pr$' "$W/pm-meta/log.txt" \
  && grep -q '^+evil' "$W/pm-meta/log-patch.txt" && grep -q 'b.ts' "$W/pm-meta/diff-stat.txt" && ok "history files hold the diff, files, log and patches" || bad "history content" "$(ls -la "$W/pm-meta" 2>&1)"
out=$(bash "$SCRIPT" 7 "$W/pm" main 2>&1); rc=$?
[ $rc != 0 ] && grep -qF "already exists" <<<"$out" && ok "refuses an existing destination (with meta)" || bad "existing meta" "$out"
rm -rf "$W/pm"; git -C "$W/base" worktree prune; out=$(bash "$SCRIPT" 7 "$W/pm" main 2>&1); rc=$?
[ $rc != 0 ] && grep -qF "$W/pm-meta already exists" <<<"$out" && ok "refuses an existing meta folder" || bad "existing meta folder" "$out"
out=$(bash "$SCRIPT" 7 "$W/pn" 'main;rm' 2>&1); rc=$?
[ $rc != 0 ] && grep -qF "bad base ref" <<<"$out" && ok "rejects a bad base ref" || bad "bad base ref" "$out"
out=$(bash "$SCRIPT" 7 "$W/pq" nosuchbranch 2>&1); rc=$?
[ $rc != 0 ] && grep -qF "base ref not found" <<<"$out" && ok "missing base ref fails" || bad "missing base ref" "$out"
out=$(bash "$SCRIPT" 99 "$W/pr3" 2>&1); rc=$?
[ $rc != 0 ] && [ ! -d "$W/pr3" ] && ok "missing PR ref fails" || bad "missing PR ref" "$out"
# A merge commit whose conflict resolution adds a line (and a later commit removes it) still shows in log-patch.txt
cd "$W/base" && git checkout -q -b pr8 main && echo one > m.txt && git add m.txt && git commit -qm "pr side"
git checkout -q -b side main && echo two > m.txt && git add m.txt && git commit -qm "main side"
git checkout -q pr8 && { git merge -q side >/dev/null 2>&1 || true; } && printf 'one\nEVIL-IN-MERGE-ONLY\n' > m.txt && git add m.txt && git commit -qm "merge" >/dev/null
echo one > m.txt && git commit -qam "remove it again" && git push -q origin "HEAD:refs/pull/8/head" 2>/dev/null && git checkout -q main
out=$(cd "$W/base" && bash "$SCRIPT" 8 "$W/p8" main 2>&1); rc=$?
[ $rc = 0 ] && grep -q '^.*+EVIL-IN-MERGE-ONLY' "$W/p8-meta/log-patch.txt" 2>/dev/null && ok "a line added only inside a merge shows in log-patch.txt" || bad "merge-only line" "$out"
# With GIT_TOKEN, git gets the token only as a one-time header: never printed, never stored
mkdir -p "$W/bin" && printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/git.log"\nexec %s "$@"\n' "$W" "$(command -v git)" > "$W/bin/git" && chmod +x "$W/bin/git"
out=$(cd "$W/base" && PATH="$W/bin:$PATH" GIT_TOKEN=tok-test-not-real bash "$SCRIPT" 7 "$W/p9" 2>&1); rc=$?
hdr=$(printf 'x-access-token:%s' tok-test-not-real | base64 -w0)
[ $rc = 0 ] && grep -qF -- "-c http.extraheader=AUTHORIZATION: basic $hdr -c core.hooksPath=/dev/null -c filter.lfs.smudge= -c filter.lfs.process= -c filter.lfs.required=false -c filter.lfs.clean= fetch" "$W/git.log" && ok "GIT_TOKEN is passed as a one-time auth header, with filters and hooks off" || bad "GIT_TOKEN header" "$(cat "$W/git.log")"
# A PR that marks a file for git-lfs with a smudge filter configured on the runner: the filter never runs (the pointer stays as is)
cd "$W/base" && git checkout -q pr && printf '*.bin filter=lfs diff=lfs merge=lfs -text\n' > .gitattributes && printf 'version https://git-lfs.github.com/spec/v1\noid sha256:0000\nsize 4\n' > big.bin \
  && git add -A && git commit -qm lfs && git push -q origin "HEAD:refs/pull/10/head" 2>/dev/null && git checkout -q main && git fetch -q origin
git config filter.lfs.smudge 'printf SMUDGED-BY-FILTER'; git config filter.lfs.required true; git config filter.lfs.process ''
out=$(bash "$SCRIPT" 10 "$W/p10" 2>&1); rc=$?
[ $rc = 0 ] && grep -q '^version https://git-lfs' "$W/p10/big.bin" && ! grep -rq SMUDGED-BY-FILTER "$W/p10" && ok "an LFS-filtered file is checked out as its pointer (no filter ran)" || bad "LFS filter" "$out $(cat "$W/p10/big.bin" 2>&1)"
git config --unset filter.lfs.smudge; git config --unset filter.lfs.required; git config --unset filter.lfs.process
printf '#!/usr/bin/env bash\necho HOOK-RAN > "%s/hook-ran"\n' "$W" > "$W/base/.git/hooks/post-checkout"; chmod +x "$W/base/.git/hooks/post-checkout"
out=$(bash "$SCRIPT" 10 "$W/p10b" 2>&1); rc=$?
[ $rc = 0 ] && [ ! -f "$W/hook-ran" ] && ok "repository hooks do not run during the checkout" || bad "hooks off" "$out"
! grep -q 'tok-test-not-real' <<<"$out" && ok "the token is never printed" || bad "token printed" "$out"
[ "$(git -C "$W/base" config --get-regexp 'http\..*extraheader' || true)" = "" ] && ok "the token is not stored in git config" || bad "token stored"
# A PR with a symlink (docs/x.md -> /proc/self/environ would leak the job's environment to a reader) is refused
cd "$W/base" && git checkout -q pr && mkdir -p docs && ln -s /proc/self/environ docs/x.md && git add -A && git commit -qm link && git push -q origin "HEAD:refs/pull/9/head" 2>/dev/null && git checkout -q main && git fetch -q origin
out=$(bash "$SCRIPT" 9 "$W/pr9" 2>&1); rc=$?
[ $rc != 0 ] && grep -q "symlinks or special files in the PR" <<<"$out" && grep -q "docs/x.md" <<<"$out" && ok "a PR with a symlink is refused" || bad "symlink refused" "$out"
# The expected head: a PR that moved since the event fails instead of being reviewed against older results
H7=$(git -C "$W/base" ls-remote "$W/remote.git" refs/pull/7/head | cut -c1-40)
out=$(cd "$W/base" && bash "$SCRIPT" 7 "$W/p11" "" origin "$H7" 2>&1); rc=$?
[ $rc = 0 ] && grep -qF "ready in $W/p11" <<<"$out" && ok "the expected head matches the fetched head" || bad "expected head ok" "$out"
out=$(cd "$W/base" && bash "$SCRIPT" 7 "$W/p12" "" origin "$(printf 'd%.0s' {1..40})" 2>&1); rc=$?
[ $rc != 0 ] && grep -q "the fetched PR head is $H7, not this event's dddd" <<<"$out" && [ ! -d "$W/p12" ] && ok "a PR that moved since the event is refused" || bad "moved PR" "$out"
out=$(cd "$W/base" && bash "$SCRIPT" 7 "$W/p13" "" origin notasha 2>&1); rc=$?
[ $rc != 0 ] && grep -q "bad expected head sha" <<<"$out" && ok "a bad expected head is rejected" || bad "bad expected head" "$out"
# The PR's own .gitattributes cannot rewrite what the reviewers see (export-subst, ident, eol are off in the worktree)
cd "$W/base" && git checkout -q -b attrs main && mkdir -p docs && printf '*.txt ident export-subst\n' > .gitattributes && printf '$Id$ and $Format:%%H$\n' > docs/k.txt && git add -A && git commit -qm attrs && git push -q origin "HEAD:refs/pull/11/head" 2>/dev/null && git checkout -q main
out=$(bash "$SCRIPT" 11 "$W/p14" 2>&1); rc=$?
[ $rc = 0 ] && [ "$(cat "$W/p14/docs/k.txt")" = '$Id$ and $Format:%H$' ] && ok "ident and export-subst in the PR's .gitattributes do not rewrite files" || bad "attributes off" "$out $(cat "$W/p14/docs/k.txt" 2>&1)"
# A PR that marks a file binary (-diff) cannot hide its content from the reviewers' history files
cd "$W/base" && git checkout -q -b bindiff main && printf '*.conf -diff\n' > .gitattributes && printf 'SECRET-LOOKING-LINE\n' > app.conf && git add -A && git commit -qm bindiff && git push -q origin "HEAD:refs/pull/12/head" 2>/dev/null && git checkout -q main
out=$(bash "$SCRIPT" 12 "$W/p15" main 2>&1); rc=$?
[ $rc = 0 ] && grep -q '^+SECRET-LOOKING-LINE' "$W/p15-meta/diff.patch" && grep -q '^+SECRET-LOOKING-LINE' "$W/p15-meta/log-patch.txt" && ! grep -q 'Binary files' "$W/p15-meta/diff.patch" && ok "a -diff attribute in the PR does not hide content from diff.patch and log-patch.txt" || bad "-diff attribute" "$out $(grep -c . "$W/p15-meta/diff.patch" 2>&1)"
summary
