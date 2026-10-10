#!/usr/bin/env bash
# Tests scripts/check-pins.sh (update and verify) on a small copy of the repo layout, and that the real repository's pins are
# current (the workflow checker verifies pins.txt and every PINS_SHA256 against the tree).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; REPO="$(cd "$HERE/.." && pwd)"; SCRIPT="$HERE/check-pins.sh"
. "$HERE/check-testlib.sh"
W=$(mktemp -d "${TMPDIR:-/tmp}/pn.XXXXXX") || exit 2; trap 'rm -rf "$W"' EXIT
tree() { # a small repo: two workflows with the pin step, one without; a lock action; guard scripts; a test and a test lib (not pinned)
  R="$W/r"; rm -rf "$R"; mkdir -p "$R/.github/workflows" "$R/.github/actions/lock" "$R/scripts" "$R/.claude/agents"
  printf 'echo lock\n' > "$R/.github/actions/lock/lock.sh"; printf 'echo a\n' > "$R/scripts/check-a.sh"; printf 'print(1)\n' > "$R/scripts/check-b.py"
  printf 'echo t\n' > "$R/scripts/check-a.test.sh"; printf 'x\n' > "$R/scripts/check-testlib.sh"; printf '[allowlist]\n' > "$R/.gitleaks.toml"
  printf '1 a founder\n' > "$R/.github/accounts.txt"; printf '# rules\n' > "$R/CLAUDE.md"; printf 'agent\n' > "$R/.claude/agents/x.md"
  mkdir -p "$R/apps/admin/.claude" "$R/.git/hooks" "$R/.worktrees/pr1/.claude" "$R/node_modules/x"; printf 'nested\n' > "$R/apps/admin/.claude/settings.json"
  printf '{}\n' > "$R/apps/admin/.mcp.json"; printf 'local\n' > "$R/apps/CLAUDE.local.md"; printf 'nested rules\n' > "$R/apps/admin/CLAUDE.md"
  printf 'ignored\n' > "$R/.git/hooks/CLAUDE.md"; printf 'ignored\n' > "$R/.worktrees/pr1/.claude/x.md"; printf 'ignored\n' > "$R/node_modules/x/CLAUDE.md"
  for w in a b; do printf 'name: %s\njobs:\n  j:\n    steps:\n      - name: pin\n        env:\n          PINS_SHA256: "%s"\n        run: echo\n' "$w" "$(printf '0%.0s' {1..64})" > "$R/.github/workflows/$w.yml"; done
  printf 'name: c\njobs:\n  j:\n    steps:\n      - run: echo\n' > "$R/.github/workflows/c.yml"
}
run() { local want=$1 name=$2 msg=$3; shift 3; out=$(bash "$SCRIPT" "$@" 2>&1); rc=$?; assert_result "$want" "$rc" "$name" "$msg" "$out"; }
run fail "usage" "usage: check-pins.sh update|verify" --
run fail "check mode is gone (verify is the pin step's set check; the checker verifies on every run)" "usage: check-pins.sh update|verify" check "$REPO"
run fail "no workflows folder" "no .github/workflows in" update "$W"
tree; run fail "verify before any pins.txt" ".github/pins.txt is missing" verify "$R"
run ok "update writes pins.txt and two workflows" "Updated .github/pins.txt (11 files) and PINS_SHA256 in 2 workflow(s)" update "$R"
check "pins.txt lists exactly the pinned files (policy pins_required): rule files at any depth (CLAUDE.md, CLAUDE.local.md, .mcp.json, .claude/), lock, guard scripts, gitleaks config, accounts; not tests, test libs, .git, .worktrees or node_modules" \
  bash -c '[ "$(cut -c67- "$1" | tr "\n" " ")" = ".claude/agents/x.md .github/accounts.txt .github/actions/lock/lock.sh .gitleaks.toml CLAUDE.md apps/CLAUDE.local.md apps/admin/.claude/settings.json apps/admin/.mcp.json apps/admin/CLAUDE.md scripts/check-a.sh scripts/check-b.py " ]' _ "$R/.github/pins.txt"
run ok "verify right after update" "Pins OK (11 files)" verify "$R"
check "every line is '<sha256>  <path>' with the file's real hash" bash -c 'cd "$1" && sha256sum --check --strict --quiet .github/pins.txt' _ "$R"
H=$(sha256sum "$R/.github/pins.txt" | cut -c1-64)
check "both workflows carry the hash, the third is untouched" bash -c 'grep -q "PINS_SHA256: \"$2\"" "$1/a.yml" && grep -q "PINS_SHA256: \"$2\"" "$1/b.yml" && ! grep -q PINS_SHA256 "$1/c.yml"' _ "$R/.github/workflows" "$H"
run ok "update again is idempotent" "Updated .github/pins.txt (11 files)" update "$R"
check "same hash after a second update" bash -c '[ "$(sha256sum "$1" | cut -c1-64)" = "$2" ]' _ "$R/.github/pins.txt" "$H"
printf 'echo changed\n' > "$R/scripts/check-a.sh"; run fail "verify after a change to a pinned file" "scripts/check-a.sh changed but its pin did not" verify "$R"
run ok "update after a change" "Updated" update "$R"
check "the changed file has a new pin and the workflows a new hash" bash -c 'cd "$1" && sha256sum --check --strict --quiet .github/pins.txt && [ "$(sha256sum .github/pins.txt | cut -c1-64)" != "$2" ] && grep -q "PINS_SHA256: \"$(sha256sum .github/pins.txt | cut -c1-64)\"" .github/workflows/a.yml' _ "$R" "$H"
rm "$R/scripts/check-b.py"; printf 'new\n' > "$R/scripts/check-new.sh"
run fail "verify with a removed and an added guard script" "does not list scripts/check-new.sh" verify "$R"
check "verify also names the listed file that is gone" bash -c 'bash "$1" verify "$2" 2>&1 | grep -q "lists scripts/check-b.py, which is not a pinned file"' _ "$SCRIPT" "$R"
run ok "a removed and an added guard script" "Updated .github/pins.txt (11 files)" update "$R"
check "the list follows the files" bash -c 'grep -q "scripts/check-new.sh" "$1" && ! grep -q "scripts/check-b.py" "$1"' _ "$R/.github/pins.txt"
# An added agent-instruction file anywhere fails verify until it is reviewed and pinned (a push cannot add one unnoticed)
mkdir -p "$R/.claude/commands"; printf 'hook\n' > "$R/.claude/commands/x.md"; run fail "an added file under .claude fails verify" "does not list .claude/commands/x.md" verify "$R"
rm -r "$R/.claude/commands"; mkdir -p "$R/services/ai/.claude"; printf '{}\n' > "$R/services/ai/.claude/settings.json"
run fail "a new nested .claude/ folder fails verify" "does not list services/ai/.claude/settings.json" verify "$R"
rm -r "$R/services/ai/.claude"; printf 'x\n' > "$R/services/CLAUDE.md"; run fail "a new nested CLAUDE.md fails verify" "does not list services/CLAUDE.md" verify "$R"
rm "$R/services/CLAUDE.md"; printf '{}\n' > "$R/.mcp.json"; run fail "a new .mcp.json fails verify" "does not list .mcp.json" verify "$R"
rm "$R/.mcp.json"; run ok "verify passes again once the tree matches" "Pins OK" verify "$R"
printf 'junk\n' >> "$R/.github/pins.txt"; run fail "a malformed pins.txt line" "line 12: want '<sha256>  <path>'" verify "$R"
run ok "the real repository's pins verify" "Pins OK" verify "$REPO"
out=$(python3 -I "$HERE/check-workflows-lib.py" 2>&1); rc=$?; [ $rc = 2 ] && grep -q "usage: check-workflows-lib.py paths|verify" <<<"$out" && t PASS "the library's command line prints its usage" || t FAIL "lib usage ($rc)"
# The real repository is up to date: the checker verifies pins.txt and every workflow's hash against the tree
out=$(bash "$HERE/check-workflows.sh" "$REPO" 2>&1); rc=$?
[ $rc = 0 ] && t PASS "the real repository's pins are current (checker passes)" || { t FAIL "real repository pins ($rc)"; grep -i pins <<<"$out" | head -n 5; }
check "the ledger workflow takes its hash from guards.yml (no PINS_SHA256 of its own)" bash -c '! grep -qE "^ *PINS_SHA256: \"" "$1/pusher-ledger.yml" && grep -q "PINS_SHA256: \"" "$1/guards.yml" && grep -q "sed -n -E .s/\^ \*PINS_SHA256" "$1/pusher-ledger.yml"' _ "$REPO/.github/workflows"
summary
