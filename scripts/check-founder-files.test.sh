#!/usr/bin/env bash
# Tests scripts/check-founder-files.sh in throwaway git repos.
set -uo pipefail
SCRIPT="$(cd "$(dirname "$0")" && pwd)/check-founder-files.sh"
TMPROOT="${TMPDIR:-/tmp}"
pass=0; failed=0
setup() {
  R=$(mktemp -d "$TMPROOT/cff.XXXXXX") || exit 2; cd "$R"
  git init -q -b main . && git config user.email t@t && git config user.name t
  mkdir -p .claude/agents docs src scripts && echo a > CLAUDE.md && echo a > .claude/agents/x.md && echo a > src/a.ts \
    && echo a > docs/a.md && echo a > .gitleaks.toml && echo a > scripts/gitleaks-config.test.sh
  printf '# founders\nfounder-one\n  founder-two  # second\n' > "$R.founders"
  git add -A && git commit -qm base && git checkout -qb work
}
commit() { git add -A && git commit -qm change >/dev/null; }
expect() { # expect <ok|fail> <author> <name> [message-substring]
  out=$(bash "$SCRIPT" main HEAD "$2" "$R.founders" 2>&1); rc=$?
  got=$([ $rc = 0 ] && echo ok || echo fail)
  if [ "$got" = "$1" ] && { [ -z "${4:-}" ] || grep -qF -- "$4" <<<"$out"; }; then pass=$((pass+1)); echo "PASS  $3"
  else failed=$((failed+1)); echo "FAIL  $3 (expected $1, got $got)"; echo "$out"; fi
  cd /; rm -rf "$R" "$R.founders"
}
A=itri-agents
setup; echo b > src/a.ts; commit;                          expect ok   $A "normal code change"
setup;                                                     expect ok   $A "empty diff"
setup; echo b > CLAUDE.md; commit;                         expect fail $A "root CLAUDE.md" "CLAUDE.md"
setup; echo b > docs/CLAUDE.md; commit;                    expect fail $A "nested CLAUDE.md" "docs/CLAUDE.md"
setup; echo b > CLAUDE.local.md; commit;                   expect fail $A "CLAUDE.local.md"
setup; echo '{}' > .mcp.json; commit;                      expect fail $A ".mcp.json"
setup; echo b > .claude/agents/x.md; commit;               expect fail $A ".claude file"
setup; mkdir -p apps/admin/.claude; echo b > apps/admin/.claude/settings.json; commit; expect fail $A "nested .claude folder" "apps/admin/.claude"
setup; mkdir -p .github/workflows; echo b > .github/workflows/ci.yml; commit; expect fail $A "any workflow (ci.yml)"
setup; echo b > scripts/check-skills.sh; commit;           expect fail $A "check script"
setup; echo b > scripts/gitleaks-config.test.sh; commit;   expect fail $A "gitleaks-config test changed"
setup; git rm -q scripts/gitleaks-config.test.sh; commit;  expect fail $A "gitleaks-config test deleted"
setup; echo b > .gitleaks.toml; commit;                    expect fail $A ".gitleaks.toml"
setup; git mv .gitleaks.toml docs/gl.toml; commit;         expect fail $A ".gitleaks.toml renamed away" ".gitleaks.toml"
setup; echo x > .gitleaksignore; commit;                   expect fail $A ".gitleaksignore"
setup; mkdir -p packages/data; echo x > packages/data/override-allowlist.txt; commit; expect fail $A "override allow-list is founder-only" "override-allowlist"
setup; mkdir -p packages/data/sub; echo x > packages/data/sub/override-allowlist.txt; echo y > packages/data/override-allowlists.ts; echo z > packages/data/other.ts; commit; expect ok $A "near-miss allow-list paths are fine"
setup; mkdir -p apps/x/packages/data; echo x > apps/x/packages/data/override-allowlist.txt; commit; expect ok $A "allow-list name under another folder is not founder-only (anchored at the root)"
setup; git checkout -q main; mkdir -p packages/data; echo x > packages/data/override-allowlist.txt; git add -A; git commit -qm base2; git checkout -q -B work main; git mv packages/data/override-allowlist.txt docs/x.txt; commit; expect fail $A "allow-list renamed away" "override-allowlist.txt"
setup; git checkout -q main; mkdir -p packages/data; echo x > packages/data/override-allowlist.txt; git add -A; git commit -qm base2; git checkout -q -B work main; git rm -q packages/data/override-allowlist.txt; commit; expect fail $A "allow-list deleted" "override-allowlist.txt"
setup; git checkout -q main; mkdir -p packages/data; echo x > packages/data/notes.txt; git add -A; git commit -qm base2; git checkout -q -B work main; git mv packages/data/notes.txt packages/data/override-allowlist.txt; commit; expect fail $A "file renamed into the allow-list path" "override-allowlist.txt"
setup; mkdir -p packages/contracts; echo b > packages/contracts/a.ts; commit; expect ok   $A "contracts are agent-built (founder approves via CODEOWNERS)"
setup; git mv .claude/agents/x.md src/moved.md; commit;    expect fail $A "rename out of .claude (old path listed)" ".claude/agents/x.md"
setup; mkdir -p .claude/é; echo b > ".claude/é/a.md"; commit; expect fail $A "unicode path under .claude"
setup; mkdir -p .claude/n; echo b > ".claude/n/new
line.md"; commit;                                          expect fail $A "newline in a .claude path"
setup; mkdir -p .claudeX; echo b > .claudeX/a.md; echo b > docs/CLAUDE.md.txt; commit; expect ok $A "lookalikes are fine"
setup; echo b > CLAUDE.md; commit;                         expect ok   founder-one "founder author allowed" "are founders"
setup; echo b > CLAUDE.md; commit;                         expect ok   founder-two "founder with spaces/comment in list"
setup; echo b > CLAUDE.md; commit;                         expect fail founder "prefix of a founder name is not a founder"
setup; echo b > CLAUDE.md; commit;                         expect fail "#" "comment marker is not a founder"
setup; echo b > CLAUDE.md; commit;                         expect ok   founder-one,founder-two "author and pusher both founders"
setup; echo b > CLAUDE.md; commit;                         expect fail founder-one,$A "founder PR but agent pushed" "Not all of"
setup; echo b > CLAUDE.md; commit;                         expect fail founder-one, "empty login in the list"
setup; out=$(bash "$SCRIPT" no-such-ref HEAD $A "$R.founders" 2>&1); rc=$?; cd /; rm -rf "$R" "$R.founders"
if [ $rc != 0 ] && grep -qF "could not diff" <<<"$out"; then pass=$((pass+1)); echo "PASS  bad base ref fails closed"; else failed=$((failed+1)); echo "FAIL  bad base ref fails closed"; echo "$out"; fi
setup; out=$(bash "$SCRIPT" main HEAD $A /nonexistent 2>&1); rc=$?; cd /; rm -rf "$R" "$R.founders"
if [ $rc != 0 ] && grep -qF "founders file not found" <<<"$out"; then pass=$((pass+1)); echo "PASS  missing founders file fails closed"; else failed=$((failed+1)); echo "FAIL  missing founders file"; echo "$out"; fi
# CODEOWNERS lists every root founder-only file the script guards by exact path
REPO_ROOT="$(cd "$(dirname "$SCRIPT")/.." && pwd)"
if grep -qE '^/packages/data/override-allowlist\.txt[[:space:]]+@' "$REPO_ROOT/.github/CODEOWNERS"; then pass=$((pass+1)); echo "PASS  CODEOWNERS has the allow-list entry"
else failed=$((failed+1)); echo "FAIL  CODEOWNERS is missing /packages/data/override-allowlist.txt"; fi
echo "$pass passed, $failed failed"
[ "$failed" = 0 ]
