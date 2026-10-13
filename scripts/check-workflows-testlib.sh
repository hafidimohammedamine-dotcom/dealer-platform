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
  cp "$REPO/.github/accounts.txt" "$REPO/.github/pins.txt" "$T/.github/"; cp "$REPO/.gitleaks.toml" "$REPO/CLAUDE.md" "$REPO/.yarnrc.yml" "$T/"; cp -r "$REPO/.claude" "$T/"
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
plain() { printf 'name: y\non: push\njobs:\n  a:\n    runs-on: ubuntu-latest\n    permissions:\n      contents: read\n    steps:\n      - uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803\n%s\n      - run: echo\n' "$PIN_STEP" > "$T/$W/$1"; }
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
# The one shell allowed after the claude step (policy post_claude_shell) and what a step with it must look like.
SH='/usr/bin/bash --noprofile --norc -p -eo pipefail {0}'
EV=$(python3 -I -c 'import json, sys; P = json.load(open(sys.argv[1])); print("        env:\n" + "".join(f"          {k}: \"\"\n" for k in P["post_claude_empty_env"]) + "".join(f"          {k}: {v}\n" for k, v in P["post_claude_fixed_env"].items()) + f"          PINS_SHA256: \"{sys.argv[2]}\"\n          EXEC_FILE: f\n", end="")' "$(dirname "$PY")/check-workflows-policy.json" "$PINS_HASH")   # the full env block of a hardened step (real newlines, no trailing one)
repin() { bash "$T/scripts/check-pins.sh" update "$T" >/dev/null; }   # after editing a pinned file in the copy
PIN1='          echo "$PINS_SHA256  .github/pins.txt" | /usr/bin/sha256sum --check --strict --quiet\n          /usr/bin/sha256sum --check --strict --quiet .github/pins.txt\n'
SCR='          /usr/bin/env -i PATH=/usr/bin:/bin HOME=/nonexistent TMPDIR=/tmp GITLEAKS_BIN=/tmp/gitleaks /usr/bin/bash scripts/check-claude-answer.sh answer "$EXEC_FILE" >> "$GITHUB_OUTPUT"\n'
MARK='          echo "hardened=ok" >> "$GITHUB_OUTPUT"\n'
RUN="        run: |\n          export PATH=/usr/bin:/bin\n          set -u\n$PIN1$SCR"   # a hand-off body without the marker (allowed while post_claude_require_marker is false)
MRUN="$RUN$MARK"   # the same body ending with the marker line
marker_on() { sed -i 's|"post_claude_require_marker": false|"post_claude_require_marker": true|' "$T/scripts/check-workflows-policy.json"; repin; }   # then run the COPY's checker: SCRIPT="$T/scripts/check-workflows.sh" expect ...
# sync_hardened: give every step of job `a` that has the hardened shell an id (h1, h2, ...) if it has none; for the steps
# that end with the marker line, write the job's outputs (<id>_ran) and the hardened-check job at the end of the file
# (replacing an old one), as the checker expects.
sync_hardened() { python3 -I - "$T/$W/t.yml" "$SH" "${1:-}" <<'PYSYNC'   # [step text to append to job a first]
import re, sys
p, sh, add = sys.argv[1:4]; s = open(p).read()
s = s.split("\n  hardened-check:\n", 1)[0].rstrip("\n") + "\n" + add
s = re.sub(r"\n    outputs:\n(?:      \S+_ran: .*\n)+", "\n", s)
lines = s.split("\n"); steps = []   # [first line index, has the shell, id]
for i, line in enumerate(lines):
    if line.startswith("      - "):
        steps.append([i, False, None])
    if steps and line.lstrip(" -") == "shell: " + sh:
        steps[-1][1] = True
    if steps and line.strip() == 'echo "hardened=ok" >> "$GITHUB_OUTPUT"':
        steps[-1].append("marked")
    m = re.match(r" {6}[ -] id: ([a-z][a-z0-9-]*)$", line)
    if m and steps:
        steps[-1][2] = m.group(1)
ids = []
for n, (i, hard, sid, *marked) in enumerate(reversed(steps)):
    if hard and sid is None:
        sid = f"h{len(steps) - n}"; lines.insert(i + 1, f"        id: {sid}")
    if hard and marked:   # only a step that ends with the marker line is read by the check job
        ids.insert(0, sid)
s = "\n".join(lines)
if ids:
    s = s.replace("  a:\n", "  a:\n    outputs:\n" + "".join(f"      {i}_ran: ${{{{ steps.{i}.outputs.hardened }}}}\n" for i in ids), 1)
    env = "      a_result: ${{ needs.a.result }}\n" + "".join(f"      a_{i}: ${{{{ needs.a.outputs.{i}_ran }}}}\n" for i in ids)
    run = "".join(f'          [ "$a_result" = skipped ] || [ "$a_{i}" = ok ] || {{ echo "hardened step a/{i} did not run"; exit 1; }}\n' for i in ids)
    s += "  hardened-check:\n    needs: [a]\n    if: always()\n    runs-on: ubuntu-latest\n    permissions:\n      contents: read\n    env:\n" + env + "    steps:\n      - run: |\n" + run
open(p, "w").write(s)
PYSYNC
}
hs() { sync_hardened "$(printf '%b' "      - shell: $SH\n$1")
"; }   # a hardened step after the claude step (id h<n>), then the given keys; outputs and the check job kept in step
noenv() { printf '%s' "$EV" | grep -v "^          $1:"; }   # the env block without one name
setenv() { printf '%s' "$EV" | sed "s|^          $1: .*|          $1: $2|"; }   # the env block with one name changed

# A small valid workflow; tests edit it with sed.
esc() { printf '%b' "$1" | sed 's/[&|]/\\&/g; s/$/\\/' | sed '$ s/\\$//'; }   # a multi-line sed replacement
mk() { sed "s|^PIN_STEP_HERE$|$(esc "$PIN_STEP")|; s|^ENV_HERE$|$(esc "$EV")|; s|^RUN_HERE$|$(esc "$RUN")|" <<'EOF' > "$T/$W/t.yml"
name: t
on: workflow_dispatch
jobs:
  a:
    if: github.run_attempt == '1'
    runs-on: ubuntu-latest
    permissions:
      contents: read
    env:
      CLAUDE_CODE_SUBPROCESS_ENV_SCRUB: "1"
    steps:
      - uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803
        with:
          ref: main
          persist-credentials: false
PIN_STEP_HERE
      - name: The default branch's head passed the main guard
        run: bash scripts/check-main-head.sh
      - id: lock
        uses: ./.github/actions/agent-egress-lock
      - id: claude
        uses: anthropics/claude-code-action@2dca132ff0e0c4094ce6048b422c6915a071210b
        with:
          claude_code_oauth_token: ${{ secrets.CLAUDE_TOKEN_REVIEW_V2 }}
          path_to_claude_code_executable: ${{ steps.lock.outputs.claude-path }}
          path_to_bun_executable: ${{ steps.lock.outputs.bun-path }}
          github_token: ${{ github.token }}
          classify_inline_comments: "false"
          prompt: "Do the task."
          claude_args: |
            --model haiku
            --disallowedTools "Skill(payload),Write,WebFetch,WebSearch,Read(//proc/**),Read(//sys/**),Read(//home/runner/work/_temp/**),Read(//home/runner/.*/**),Read(//etc/**),Read(//dev/**),Read(//home/runner/runners/**),Read(./.git/**)"
      - name: After
        if: always() && steps.claude.outputs.execution_file != ''
        id: after
        shell: /usr/bin/bash --noprofile --norc -p -eo pipefail {0}
ENV_HERE
RUN_HERE
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
