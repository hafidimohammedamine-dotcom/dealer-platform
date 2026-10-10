#!/usr/bin/env bash
# Tests scripts/check-pins.sh (update) on a small copy of the repo layout, and that the real repository's pins are current
# (the workflow checker verifies pins.txt and every PINS_SHA256 against the tree).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; REPO="$(cd "$HERE/.." && pwd)"; SCRIPT="$HERE/check-pins.sh"
. "$HERE/check-testlib.sh"
W=$(mktemp -d "${TMPDIR:-/tmp}/pn.XXXXXX") || exit 2; trap 'rm -rf "$W"' EXIT
tree() { # a small repo: two workflows with the pin step, one without; a lock action; guard scripts; a test and a test lib (not pinned)
  R="$W/r"; rm -rf "$R"; mkdir -p "$R/.github/workflows" "$R/.github/actions/lock" "$R/scripts" "$R/.claude/agents"
  printf 'echo lock\n' > "$R/.github/actions/lock/lock.sh"; printf 'echo a\n' > "$R/scripts/check-a.sh"; printf 'print(1)\n' > "$R/scripts/check-b.py"
  printf 'echo t\n' > "$R/scripts/check-a.test.sh"; printf 'x\n' > "$R/scripts/check-testlib.sh"; printf '[allowlist]\n' > "$R/.gitleaks.toml"
  printf '1 a founder\n' > "$R/.github/accounts.txt"; printf '# rules\n' > "$R/CLAUDE.md"; printf 'agent\n' > "$R/.claude/agents/x.md"
  for w in a b; do printf 'name: %s\njobs:\n  j:\n    steps:\n      - name: pin\n        env:\n          PINS_SHA256: "%s"\n        run: echo\n' "$w" "$(printf '0%.0s' {1..64})" > "$R/.github/workflows/$w.yml"; done
  printf 'name: c\njobs:\n  j:\n    steps:\n      - run: echo\n' > "$R/.github/workflows/c.yml"
}
run() { local want=$1 name=$2 msg=$3; shift 3; out=$(bash "$SCRIPT" "$@" 2>&1); rc=$?; assert_result "$want" "$rc" "$name" "$msg" "$out"; }
run fail "usage" "usage: check-pins.sh update" --
run fail "check mode is gone (the checker verifies)" "usage: check-pins.sh update" check "$REPO"
run fail "no workflows folder" "no .github/workflows in" update "$W"
tree; run ok "update writes pins.txt and two workflows" "Updated .github/pins.txt (7 files) and PINS_SHA256 in 2 workflow(s)" update "$R"
check "pins.txt lists exactly the pinned files (policy pins_required): rule files, lock, guard scripts, gitleaks config, accounts; not tests or test libs" \
  bash -c '[ "$(cut -c67- "$1" | tr "\n" " ")" = ".claude/agents/x.md .github/accounts.txt .github/actions/lock/lock.sh .gitleaks.toml CLAUDE.md scripts/check-a.sh scripts/check-b.py " ]' _ "$R/.github/pins.txt"
check "every line is '<sha256>  <path>' with the file's real hash" bash -c 'cd "$1" && sha256sum --check --strict --quiet .github/pins.txt' _ "$R"
H=$(sha256sum "$R/.github/pins.txt" | cut -c1-64)
check "both workflows carry the hash, the third is untouched" bash -c 'grep -q "PINS_SHA256: \"$2\"" "$1/a.yml" && grep -q "PINS_SHA256: \"$2\"" "$1/b.yml" && ! grep -q PINS_SHA256 "$1/c.yml"' _ "$R/.github/workflows" "$H"
run ok "update again is idempotent" "Updated .github/pins.txt (7 files)" update "$R"
check "same hash after a second update" bash -c '[ "$(sha256sum "$1" | cut -c1-64)" = "$2" ]' _ "$R/.github/pins.txt" "$H"
printf 'echo changed\n' > "$R/scripts/check-a.sh"; run ok "update after a change" "Updated" update "$R"
check "the changed file has a new pin and the workflows a new hash" bash -c 'cd "$1" && sha256sum --check --strict --quiet .github/pins.txt && [ "$(sha256sum .github/pins.txt | cut -c1-64)" != "$2" ] && grep -q "PINS_SHA256: \"$(sha256sum .github/pins.txt | cut -c1-64)\"" .github/workflows/a.yml' _ "$R" "$H"
rm "$R/scripts/check-b.py"; printf 'new\n' > "$R/scripts/check-new.sh"; run ok "a removed and an added guard script" "Updated .github/pins.txt (7 files)" update "$R"
check "the list follows the files" bash -c 'grep -q "scripts/check-new.sh" "$1" && ! grep -q "scripts/check-b.py" "$1"' _ "$R/.github/pins.txt"
# The real repository is up to date: the checker verifies pins.txt and every workflow's hash against the tree
out=$(bash "$HERE/check-workflows.sh" "$REPO" 2>&1); rc=$?
[ $rc = 0 ] && t PASS "the real repository's pins are current (checker passes)" || { t FAIL "real repository pins ($rc)"; grep -i pins <<<"$out" | head -n 5; }
check "the ledger workflow takes its hash from guards.yml (no PINS_SHA256 of its own)" bash -c '! grep -qE "^ *PINS_SHA256: \"" "$1/pusher-ledger.yml" && grep -q "PINS_SHA256: \"" "$1/guards.yml" && grep -q "sed -n -E .s/\^ \*PINS_SHA256" "$1/pusher-ledger.yml"' _ "$REPO/.github/workflows"
summary
