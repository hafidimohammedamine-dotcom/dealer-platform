#!/usr/bin/env bash
# Tests scripts/check-pins.sh on a small copy of the repo: update writes pins.txt and every workflow's PINS_SHA256, check
# finds a changed file, a stale hash, a missing pins.txt; and the real repository is up to date.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; REPO="$(cd "$HERE/.." && pwd)"; SCRIPT="$HERE/check-pins.sh"
. "$HERE/check-testlib.sh"
W=$(mktemp -d "${TMPDIR:-/tmp}/pn.XXXXXX") || exit 2; trap 'rm -rf "$W"' EXIT
tree() { # a small repo: two workflows with the pin step, one without, a lock action, two guard scripts, a test (not pinned)
  R="$W/r"; rm -rf "$R"; mkdir -p "$R/.github/workflows" "$R/.github/actions/lock" "$R/scripts"
  printf 'echo lock\n' > "$R/.github/actions/lock/lock.sh"; printf 'echo a\n' > "$R/scripts/check-a.sh"; printf 'print(1)\n' > "$R/scripts/check-b.py"
  printf 'echo t\n' > "$R/scripts/check-a.test.sh"; printf 'x\n' > "$R/scripts/check-testlib.sh"; printf '[allowlist]\n' > "$R/.gitleaks.toml"; printf '1 a founder\n' > "$R/.github/accounts.txt"
  for w in a b; do printf 'name: %s\njobs:\n  j:\n    steps:\n      - name: pin\n        env:\n          PINS_SHA256: "%s"\n        run: echo\n' "$w" "$(printf '0%.0s' {1..64})" > "$R/.github/workflows/$w.yml"; done
  printf 'name: c\njobs:\n  j:\n    steps:\n      - run: echo\n' > "$R/.github/workflows/c.yml"
}
run() { # run <ok|fail> <name> <message> <args...>
  local want=$1 name=$2 msg=$3; shift 3; out=$(bash "$SCRIPT" "$@" 2>&1); rc=$?; assert_result "$want" "$rc" "$name" "$msg" "$out"; }
run fail "usage" "usage: check-pins.sh update|check" --
run fail "no workflows folder" "no .github/workflows in" check "$W"
tree; run fail "check before any update: pins.txt missing" "pins.txt is missing; run: bash scripts/check-pins.sh update" check "$R"
tree; run ok "update writes pins.txt and two workflows" "Updated .github/pins.txt (5 files) and PINS_SHA256 in 2 workflow(s)" update "$R"
check "pins.txt lists exactly the pinned files" bash -c '[ "$(cut -c67- "$1" | tr "\n" " ")" = ".github/accounts.txt .github/actions/lock/lock.sh .gitleaks.toml scripts/check-a.sh scripts/check-b.py " ]' _ "$R/.github/pins.txt"
H=$(sha256sum "$R/.github/pins.txt" | cut -c1-64)
check "both workflows carry the hash, the third is untouched" bash -c 'grep -q "PINS_SHA256: \"$2\"" "$1/a.yml" && grep -q "PINS_SHA256: \"$2\"" "$1/b.yml" && ! grep -q PINS_SHA256 "$1/c.yml"' _ "$R/.github/workflows" "$H"
run ok "check right after update" "Pins OK: .github/pins.txt (5 files) matches the files and 2 workflow(s)" check "$R"
printf 'echo changed\n' > "$R/scripts/check-a.sh"
run fail "a pinned file changed" "pins.txt is out of date (a pinned file changed, was added or removed)" check "$R"
run ok "update after the change" "Updated" update "$R"; run ok "check after the update" "Pins OK" check "$R"
printf 'new\n' > "$R/scripts/check-new.sh"; run fail "a new guard script" "out of date" check "$R"; bash "$SCRIPT" update "$R" >/dev/null
rm "$R/scripts/check-new.sh"; run fail "a removed guard script" "out of date" check "$R"; bash "$SCRIPT" update "$R" >/dev/null
sed -i 's|PINS_SHA256: "[0-9a-f]*"|PINS_SHA256: "'"$(printf 'f%.0s' {1..64})"'"|' "$R/.github/workflows/b.yml"
run fail "a workflow with a stale hash" "b.yml pins .github/pins.txt at ffff" check "$R"
sed -i '/PINS_SHA256/d' "$R/.github/workflows/a.yml" "$R/.github/workflows/b.yml"; run fail "no workflow carries the hash" "no workflow carries PINS_SHA256" check "$R"
# The real repository is up to date (a founder who changes a pinned file runs update in the same PR)
run ok "the real repository's pins are current" "Pins OK" check "$REPO"
summary
