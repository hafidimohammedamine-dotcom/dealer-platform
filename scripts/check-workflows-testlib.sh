#!/usr/bin/env bash
# Shared helpers for scripts/check-workflows*.test.sh (founder-owned): a temp copy of the real workflows, the small
# fixture workflow t.yml, and edit helpers. Sourced, never run on its own.
SCRIPT="$(cd "$(dirname "$0")" && pwd)/check-workflows.sh"
PY="$(cd "$(dirname "$0")" && pwd)/check-workflows.py"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMPROOT="${TMPDIR:-/tmp}"
W=.github/workflows
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-testlib.sh"
# A fresh root: the real workflows, accounts.txt, and every pinned file with pins.txt (the pin steps must verify).
fresh() { T=$(mktemp -d "$TMPROOT/cw.XXXXXX") || exit 2; mkdir -p "$T/.github" "$T/scripts"; cp -r "$REPO/$W" "$REPO/.github/actions" "$T/.github/"
  cp "$REPO/.github/accounts.txt" "$REPO/.github/pins.txt" "$T/.github/"; cp "$REPO/.gitleaks.toml" "$REPO/CLAUDE.md" "$T/"; cp -r "$REPO/.claude" "$T/"
  local _pf; for _pf in "$REPO"/scripts/check-*; do case "$_pf" in *.test.sh|*testlib.sh) ;; *) cp "$_pf" "$T/scripts/";; esac; done; }
PINS_HASH=$(sha256sum "$REPO/.github/pins.txt" | cut -c1-64)
PIN_STEP="      - name: The repository files this job runs are the reviewed ones (pinned here, outside any push's reach)
        env:
          PINS_SHA256: \"$PINS_HASH\"
        run: |
          echo \"\$PINS_SHA256  .github/pins.txt\" | sha256sum --check --strict --quiet
          sha256sum --check --strict --quiet .github/pins.txt
          bash scripts/check-pins.sh verify"
# plain <file>: a minimal non-claude workflow (one job, checkout + pin step + one run step) for argument/format cases
plain() { printf 'name: y\non: push\njobs:\n  a:\n    runs-on: ubuntu-latest\n    steps:\n      - uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803\n%s\n      - run: echo\n' "$PIN_STEP" > "$T/$W/$1"; }
expect() { # expect <ok|fail> <name> <message> [extra args]
  local want=$1 name=$2 msg=$3; shift 3
  out=$(bash "$SCRIPT" "$T" "$@" 2>&1); rc=$?
  assert_result "$want" "$rc" "$name" "$msg" "$out"; rm -rf "$T"; }
drop() { python3 - "$T/$W/$1" "$2" <<'EOF'
import sys
p, item = sys.argv[1], sys.argv[2]
s = open(p).read()
for a, b in ((item + ",", ""), ("," + item + '"', '"')):
    if a in s:
        s = s.replace(a, b, 1); break
else:
    sys.exit("item not found: " + item)
open(p, "w").write(s)
EOF
}
# A small valid workflow; tests edit it with sed.
mk() { sed "s|^PIN_STEP_HERE$|$(printf '%s' "$PIN_STEP" | sed 's/[&|]/\\&/g; s/$/\\/' | sed '$ s/\\$//')|" <<'EOF' > "$T/$W/t.yml"
name: t
on: workflow_dispatch
jobs:
  a:
    runs-on: ubuntu-latest
    env:
      CLAUDE_CODE_SUBPROCESS_ENV_SCRUB: "1"
    steps:
      - uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803
        with:
          ref: main
          persist-credentials: false
PIN_STEP_HERE
      - id: lock
        uses: ./.github/actions/agent-egress-lock
      - id: claude
        uses: anthropics/claude-code-action@2dca132ff0e0c4094ce6048b422c6915a071210b
        with:
          claude_code_oauth_token: ${{ secrets.CLAUDE_TOKEN_REVIEW }}
          path_to_claude_code_executable: ${{ steps.lock.outputs.claude-path }}
          path_to_bun_executable: ${{ steps.lock.outputs.bun-path }}
          github_token: ${{ github.token }}
          prompt: "Do the task."
          claude_args: |
            --model haiku
            --disallowedTools "Skill(payload),Write,WebFetch,WebSearch,Read(//proc/**),Read(//sys/**),Read(//home/runner/work/_temp/**),Read(//home/runner/.*/**),Read(//etc/**),Read(//dev/**),Read(//home/runner/runners/**),Read(./.git/**)"
      - name: After
        if: always() && steps.claude.outputs.execution_file != ''
        run: echo "steps.claude.outputs are fine, and so are refs/remotes/pr/head:.claude and @claude"
EOF
}
fx() { fresh; mk; }   # fresh copy of the real workflows plus the small fixture

before() { python3 - "$T/$W/t.yml" "$1" <<'PYEOF'
import sys; p, add = sys.argv[1], sys.argv[2]; s = open(p).read()
s = s.replace("      - id: claude\n", add.replace("\\n", "\n") + "\n      - id: claude\n", 1); open(p, "w").write(s)
PYEOF
}
swap() { python3 - "$T/$W/$1" "$2" "$3" <<'PYEOF'
import sys; p, old, new = sys.argv[1:4]; s = open(p).read(); assert old in s, old; open(p, "w").write(s.replace(old, new, 1))
PYEOF
}   # swap <workflow file> <old text> <new text>: exact, one replacement, fails if the old text is missing
