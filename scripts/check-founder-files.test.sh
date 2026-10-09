#!/usr/bin/env bash
# Tests scripts/check-founder-files.sh in throwaway git repos.
set -uo pipefail
SCRIPT="$(cd "$(dirname "$0")" && pwd)/check-founder-files.sh"
TMPROOT="${TMPDIR:-/tmp}"
pass=0; failed=0
setup() {
  R=$(mktemp -d "$TMPROOT/cff.XXXXXX"); cd "$R"
  git init -q -b main . && git config user.email t@t && git config user.name t
  mkdir -p .claude/agents docs src && echo a > CLAUDE.md && echo a > .claude/agents/x.md && echo a > src/a.ts && echo a > docs/a.md
  git add -A && git commit -qm base && git checkout -qb work
}
commit() { git add -A && git commit -qm change >/dev/null; }
expect() { # expect <ok|fail> <branch> <name> [message-substring]
  out=$(bash "$SCRIPT" main "$2" 2>&1); rc=$?
  got=$([ $rc = 0 ] && echo ok || echo fail)
  if [ "$got" = "$1" ] && { [ -z "${4:-}" ] || grep -qF -- "$4" <<<"$out"; }; then pass=$((pass+1)); echo "PASS  $3"
  else failed=$((failed+1)); echo "FAIL  $3 (expected $1, got $got)"; echo "$out"; fi
  cd /; rm -rf "$R"
}
setup; echo b > src/a.ts; commit;                         expect ok   agent/1-x "normal code change"
setup;                                                    expect ok   agent/1-x "empty diff"
setup; echo b > CLAUDE.md; commit;                        expect fail agent/1-x "root CLAUDE.md" "CLAUDE.md"
setup; echo b > docs/CLAUDE.md; commit;                   expect fail agent/1-x "nested CLAUDE.md" "docs/CLAUDE.md"
setup; echo b > CLAUDE.local.md; commit;                  expect fail agent/1-x "CLAUDE.local.md"
setup; echo '{}' > .mcp.json; commit;                     expect fail agent/1-x ".mcp.json"
setup; echo b > .claude/agents/x.md; commit;              expect fail agent/1-x ".claude file"
setup; mkdir -p .github/workflows; echo b > .github/workflows/ci.yml; commit; expect fail agent/1-x "any workflow (ci.yml)"
setup; mkdir -p scripts; echo b > scripts/check-skills.sh; commit; expect fail agent/1-x "check script"
setup; echo b > .gitleaks.toml; commit;                   expect fail agent/1-x ".gitleaks.toml"
setup; mkdir -p packages/contracts; echo b > packages/contracts/a.ts; commit; expect fail agent/1-x "contracts"
setup; git mv .claude/agents/x.md src/moved.md; commit;   expect fail agent/1-x "rename out of .claude (old path listed)" ".claude/agents/x.md"
setup; mkdir -p .claude/é; echo b > ".claude/é/a.md"; commit; expect fail agent/1-x "unicode path under .claude"
setup; mkdir -p .claudeX docs; echo b > .claudeX/a.md; echo b > docs/CLAUDE.md.txt; commit; expect ok agent/1-x "lookalikes are fine"
setup; echo b > CLAUDE.md; commit;                        expect fail feature/x "non-agent, non-founder branch is checked too"
setup; echo b > CLAUDE.md; commit;                        expect ok   founder/x "founder branch allowed" "Founder branch"
setup; out=$(bash "$SCRIPT" no-such-ref agent/1-x 2>&1); rc=$?; cd /; rm -rf "$R"
if [ $rc != 0 ] && grep -qF "could not diff" <<<"$out"; then pass=$((pass+1)); echo "PASS  bad base ref fails closed"; else failed=$((failed+1)); echo "FAIL  bad base ref fails closed"; echo "$out"; fi
echo "$pass passed, $failed failed"
[ "$failed" = 0 ]
