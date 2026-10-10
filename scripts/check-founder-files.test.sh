#!/usr/bin/env bash
# Tests scripts/check-founder-files.sh in throwaway git repos.
set -uo pipefail
SCRIPT="$(cd "$(dirname "$0")" && pwd)/check-founder-files.sh"
TMPROOT="${TMPDIR:-/tmp}"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-testlib.sh"
setup() {
  R=$(mktemp -d "$TMPROOT/cff.XXXXXX") || exit 2; cd "$R"
  git init -q -b main . && git config user.email t@t && git config user.name t
  mkdir -p .claude/agents docs src scripts && echo a > CLAUDE.md && echo a > .claude/agents/x.md && echo a > src/a.ts \
    && echo a > docs/a.md && echo a > .gitleaks.toml && echo a > scripts/gitleaks-config.test.sh
  printf '# accounts\n111 founder-one founder\n  222   founder-two founder  # second\n333 agents-bot agent' > "$R.founders"
  git add -A && git commit -qm base && git checkout -qb work
}
commit() { git add -A && git commit -qm change >/dev/null; }
expect() { # expect <ok|fail> <author> <name> [message-substring]
  out=$(bash "$SCRIPT" main HEAD "$2" "$R.founders" 2>&1); rc=$?
  got=$([ $rc = 0 ] && echo ok || echo fail)
  if [ "$got" = "$1" ] && { [ -z "${4:-}" ] || grep -qF -- "$4" <<<"$out"; }; then t PASS "$3"
  else t FAIL "$3 (expected $1, got $got)"; echo "$out"; fi
  cd /; rm -rf "$R" "$R.founders"
}
A=333   # the agents' account ID
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
setup; echo b > CLAUDE.md; commit;                         expect ok   111 "founder author allowed" "are founders"
setup; echo b > CLAUDE.md; commit;                         expect ok   222 "founder with spaces/comment in list"
setup; echo b > CLAUDE.md; commit;                         expect fail 11 "prefix of a founder ID is not a founder"
setup; echo b > CLAUDE.md; commit;                         expect fail founder-one "a founder's login is not an ID" "Not all of"
setup; echo b > CLAUDE.md; commit;                         expect fail "#" "comment marker is not a founder"
setup; echo b > CLAUDE.md; commit;                         expect ok   111,222 "author and pusher both founders"
setup; echo b > CLAUDE.md; commit;                         expect fail 111,$A "founder PR but agent pushed" "Not all of '111,333'"
setup; echo b > CLAUDE.md; commit;                         expect fail 111, "empty ID in the list"
setup; echo b > CLAUDE.md; commit;                         expect fail $A "the agent account is not a founder"
# The accounts file must be well formed and list a founder, or nothing passes (fail closed)
setup; echo b > CLAUDE.md; commit; printf '111 founder-one\n' > "$R.founders"; expect fail 111 "line without a role" "bad line 1"
setup; echo b > CLAUDE.md; commit; printf 'founder-one 111 founder\n' > "$R.founders"; expect fail 111 "swapped columns" "bad line 1"
setup; echo b > CLAUDE.md; commit; printf '111 founder-one owner\n' > "$R.founders"; expect fail 111 "unknown role" "bad line 1"
setup; echo b > CLAUDE.md; commit; printf '111 founder-one founder extra\n' > "$R.founders"; expect fail 111 "extra field" "bad line 1"
setup; echo b > CLAUDE.md; commit; printf '# only comments\n333 agents-bot agent\n' > "$R.founders"; expect fail 333 "no founder listed" "no founder listed"
setup; echo b > CLAUDE.md; commit; printf '111 founder-one founder' > "$R.founders"; expect ok 111 "last line without a newline still counts" "are founders"
setup; out=$(bash "$SCRIPT" no-such-ref HEAD $A "$R.founders" 2>&1); rc=$?; cd /; rm -rf "$R" "$R.founders"
if [ $rc != 0 ] && grep -qF "could not diff" <<<"$out"; then t PASS "bad base ref fails closed"; else t FAIL "bad base ref fails closed"; echo "$out"; fi
setup; out=$(bash "$SCRIPT" main HEAD $A /nonexistent 2>&1); rc=$?; cd /; rm -rf "$R" "$R.founders"
if [ $rc != 0 ] && grep -qF "accounts file not found" <<<"$out"; then t PASS "missing accounts file fails closed"; else t FAIL "missing accounts file"; echo "$out"; fi
# The pusher ledger (5th argument): founder-only changes need every commit pushed by a founder
expectp() { # expectp <ok|fail> <author> <name> <pushers text> [message-substring]
  printf '%b' "$4" > "$R.pushers"
  out=$(bash "$SCRIPT" main HEAD "$2" "$R.founders" "$R.pushers" 2>&1); rc=$?
  got=$([ $rc = 0 ] && echo ok || echo fail)
  if [ "$got" = "$1" ] && { [ -z "${5:-}" ] || grep -qF -- "$5" <<<"$out"; }; then t PASS "$3"
  else t FAIL "$3 (expected $1, got $got)"; echo "$out"; fi
  cd /; rm -rf "$R" "$R.founders" "$R.pushers"
}
setup; echo b > CLAUDE.md; commit; H=$(git rev-parse HEAD); expectp ok   111 "founder change, every commit pushed by a founder" "$H 111 founder\n" "every commit was pushed by a founder"
setup; echo b > CLAUDE.md; commit; H=$(git rev-parse HEAD); expectp fail 111 "founder change, one commit pushed by the agent" "$H 333 agent\n" "Commits not pushed by a founder"
setup; echo b > CLAUDE.md; commit; H=$(git rev-parse HEAD); expectp fail 111 "founder change, a commit without a record" "$H - unknown\n" "$H - unknown"
setup; echo b > CLAUDE.md; commit; H=$(git rev-parse HEAD); expectp fail 111 "founder change, an unknown pusher id" "$H 999 unknown\n" "$H 999 unknown"
setup; echo b > src/a.ts; commit; H=$(git rev-parse HEAD);  expectp ok   111 "code change pushed by the agent onto a founder's PR is fine" "$H 333 agent\n" "No founder-only files changed"
setup; echo b > CLAUDE.md; commit; H=$(git rev-parse HEAD); expectp fail 333 "agent author with a founder's push still fails" "$H 111 founder\n" "Not all of '333' are founders"
setup; echo b > CLAUDE.md; commit; out=$(bash "$SCRIPT" main HEAD 111 "$R.founders" "$R.nofile" 2>&1); rc=$?; cd /; rm -rf "$R" "$R.founders"
if [ $rc != 0 ] && grep -qF "pushers file not found" <<<"$out"; then t PASS "missing pushers file fails closed"; else t FAIL "missing pushers file"; echo "$out"; fi
# The real accounts file is well formed
out=$(bash -c '. "$1"; accounts_rows "$2"' _ "$(dirname "$SCRIPT")/check-accounts-lib.sh" "$(cd "$(dirname "$SCRIPT")/.." && pwd)/.github/accounts.txt" 2>&1); rc=$?
if [ $rc = 0 ] && grep -qE '^[0-9]+ [A-Za-z0-9-]+ founder$' <<<"$out"; then t PASS "the real .github/accounts.txt is well formed"; else t FAIL "real accounts file"; echo "$out"; fi
# CODEOWNERS lists every root founder-only file the script guards by exact path
REPO_ROOT="$(cd "$(dirname "$SCRIPT")/.." && pwd)"
if grep -qE '^/packages/data/override-allowlist\.txt[[:space:]]+@' "$REPO_ROOT/.github/CODEOWNERS"; then t PASS "CODEOWNERS has the allow-list entry"
else t FAIL "CODEOWNERS is missing /packages/data/override-allowlist.txt"; fi
summary
