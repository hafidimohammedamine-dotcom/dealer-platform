#!/usr/bin/env bash
# Tests for the shape of a run step after the claude step (scripts/check-workflows-hardened.py and the post_claude_*
# policy keys), split out of scripts/check-workflows.test.sh. Helpers (SH, EV, RUN, hs, noenv, setenv, repin) are in
# scripts/check-workflows-testlib.sh.
set -uo pipefail
# shellcheck source=scripts/check-workflows-testlib.sh
. "$(cd "$(dirname "$0")" && pwd)/check-workflows-testlib.sh"
HEAD='        run: |\n          export PATH=/usr/bin:/bin\n          set -u\n'   # the body's fixed start, then PIN1
PY='          /usr/bin/env -i PATH=/usr/bin:/bin HOME=/nonexistent TMPDIR=/tmp /usr/bin/python3 -I scripts/check-claude-probe.py skill-deny "$EXEC_FILE"\n'

# Allowed shapes
fx; hs "$EV\n$RUN"; expect ok "the hardened shell with the full env and the hand-off body" "Workflow denies OK"
fx; hs "$EV\n        run: |\n          # a comment and a blank line come first\n\n          export PATH=/usr/bin:/bin\n          set -u\n$PIN1"; expect ok "comments and blank lines are skipped; a body may end after the pin lines" "Workflow denies OK"
fx; hs "$EV\n$HEAD$PIN1$PY"; expect ok "a probe body (python3 -I under env -i, the argument set in the step env)" "Workflow denies OK"
fx; hs "$EV\n$RUN"; hs "$EV\n$RUN"; expect ok "two hardened steps in one job" "Workflow denies OK"
fx; hs "$EV\n        run: |\n          export PATH=/usr/bin:/bin\n          set -u\n$PIN1          /usr/bin/env -i PATH=/usr/bin:/bin HOME=/nonexistent TMPDIR=/tmp GITLEAKS_BIN=/tmp/gitleaks /usr/bin/bash scripts/check-x.sh\n"; expect ok "a script line with a reviewed extra name (post_claude_script_env)" "Workflow denies OK"

# The run body: the PATH reset, set -u, the two pin lines, in that order, then script lines only
ORDER="must start its run with these lines, in this order: export PATH=/usr/bin:/bin / set -u / "
fx; hs "$EV\n        run: echo hi\n"; expect fail "a one-line body" "$ORDER"
fx; hs "$EV\n        run: |\n          set -u\n          export PATH=/usr/bin:/bin\n$PIN1"; expect fail "the PATH line not first" "$ORDER"
fx; hs "$EV\n        run: |\n          export PATH=/usr/bin:/bin\n$PIN1"; expect fail "set -u missing" "$ORDER"
fx; hs "$EV\n        run: |\n          export PATH=/usr/bin:/bin\n          set -u\n          /usr/bin/sha256sum --check --strict --quiet .github/pins.txt\n          echo \"\$PINS_SHA256  .github/pins.txt\" | /usr/bin/sha256sum --check --strict --quiet\n"; expect fail "the pin lines in the other order" "$ORDER"
fx; hs "$EV\n        run: |\n          export PATH=/usr/bin:/bin\n          set -u\n          echo \"\$PINS_SHA256  .github/pins.txt\" | /usr/bin/sha256sum --check --strict --quiet\n$SCR"; expect fail "only one pin line" "$ORDER"
fx; hs "$EV\n        run: |\n          export PATH=/usr/bin:/bin\n          set -u\n          # echo \"\$PINS_SHA256  .github/pins.txt\" | /usr/bin/sha256sum --check --strict --quiet\n          # /usr/bin/sha256sum --check --strict --quiet .github/pins.txt\n$SCR"; expect fail "the pin lines as comments" "$ORDER"
fx; hs "$EV\n$HEAD$SCR$PIN1"; expect fail "a script line before the pin lines" "$ORDER"
for bad in 'export PATH=/usr/bin:/bin:/tmp/x' 'export PATH=/usr/bin:/bin;' 'export PATH=/usr/bin:/bin \\' 'export PATH=/usr/bin:/bin # c' 'Export PATH=/usr/bin:/bin'; do
  fx; hs "$EV\n        run: |\n          $bad\n          set -u\n$PIN1"; expect fail "a wrong PATH line: '$bad'" "$ORDER"
done
for bad in 'echo hi' 'bash scripts/check-x.sh' 'python3 -I scripts/check-claude-probe.py x f' 'sha256sum --check --strict --quiet .github/pins.txt' 'set -euo pipefail' '/usr/bin/env -i PATH=/usr/bin:/bin HOME=/nonexistent TMPDIR=/tmp /usr/bin/bash scripts/check-x.sh; id' '/usr/bin/env -i PATH=/usr/bin:/bin HOME=/nonexistent TMPDIR=/tmp X=$(id) /usr/bin/bash scripts/check-x.sh' '/usr/bin/env -i PATH=/usr/bin:/bin HOME=/nonexistent /usr/bin/bash scripts/check-x.sh' '/usr/bin/env -i PATH=/usr/bin:/bin HOME=/nonexistent TMPDIR=/tmp /usr/bin/bash scripts/x.sh' '/usr/bin/env -i PATH=/usr/bin:/bin HOME=/nonexistent TMPDIR=/tmp /usr/bin/bash scripts/check-X.sh' '/usr/bin/env -i PATH=/usr/bin:/bin HOME=/nonexistent TMPDIR=/tmp /usr/bin/bash scripts/check-x.sh "$(id)"' '/usr/bin/env -i PATH=/usr/bin:/bin HOME=/nonexistent TMPDIR=/tmp /usr/bin/bash scripts/check-x.sh > /tmp/out' '/usr/bin/env -i PATH=/usr/bin:/bin HOME=/nonexistent TMPDIR=/tmp /usr/bin/bash scripts/check-x.sh Arg'; do
  fx; hs "$EV\n$HEAD$PIN1          $bad\n"; expect fail "a line not on the allow-list: '$bad'" "line not allowed in a step with the hardened shell"
done
for bad in LD_PRELOAD=/tmp/x.so PATH=/tmp/x HOME=/tmp TMPDIR=/tmp/x BASH_ENV=/tmp/x X=1; do
  fx; hs "$EV\n$HEAD$PIN1          /usr/bin/env -i PATH=/usr/bin:/bin HOME=/nonexistent TMPDIR=/tmp $bad /usr/bin/bash scripts/check-x.sh\n"; expect fail "a script line that sets $bad" "the script line may not set ${bad%%=*} (only post_claude_script_env"
done
# Variables the body reads come from the step's own env, never from $GITHUB_ENV
fx; hs "$(noenv EXEC_FILE)\n$HEAD$PIN1$PY"; expect fail "a script line reading an unset \$EXEC_FILE" 'the run reads $EXEC_FILE, which the step'"'"'s own env does not set'
fx; hs "$(noenv PINS_SHA256)\n$RUN"; expect fail "a hardened step without PINS_SHA256 in its own env" "must set env PINS_SHA256 to the sha256 of .github/pins.txt itself"
fx; hs "$(setenv PINS_SHA256 '"0000000000000000000000000000000000000000000000000000000000000000"')\n$RUN"; expect fail "a hardened step with a wrong PINS_SHA256" "must set env PINS_SHA256 to the sha256 of .github/pins.txt itself"
# Only printable ASCII, tabs and newlines: bash and the checker must split the same lines (YAML double-quoted escapes
# put the real character into the string; a raw one would not survive the YAML reader)
QPINS='echo \\"$PINS_SHA256  .github/pins.txt\\" | /usr/bin/sha256sum --check --strict --quiet\\n/usr/bin/sha256sum --check --strict --quiet .github/pins.txt'
for c in '\\r' '\\v' '\\f' '\\N' '\\L' '\\P' '\\0' '\\e' '\\x7f' '\\xa0'; do
  fx; hs "$EV\n        run: \"export PATH=/usr/bin:/bin$c#x\"\n"; expect fail "a control character in the PATH line: $c" "may hold only printable ASCII, tabs and newlines"
  fx; hs "$EV\n        run: \"export PATH=/usr/bin:/bin\\\\nset -u\\\\n$QPINS\\\\n/usr/bin/env -i PATH=/usr/bin:/bin HOME=/nonexistent TMPDIR=/tmp /usr/bin/bash scripts/check-x.sh$c#x\"\n"; expect fail "a control character in a script line: $c" "may hold only printable ASCII, tabs and newlines"
done
fx; hs "$EV\n        run: \"export PATH=/usr/bin:/bin\\\\nset -u\\\\n$QPINS\\\\n\\\\t# a tab in a comment is fine\"\n"; expect ok "a double-quoted body with a tab is fine" "Workflow denies OK"
fx; hs "$EV\n        run: \"export PATH=/usr/bin:/bin\\\\nset -u\\\\n$QPINS\\\\n$(printf '%s' "$SCR" | sed 's/^ *//; s/"/\\\\"/g')\"\n"; expect ok "a double-quoted body with the hand-off line is fine" "Workflow denies OK"
# The env block
fx; hs "        run: |\n          export PATH=/usr/bin:/bin\n"; expect fail "the hardened shell without an env mapping" "must have an env mapping"
fx; hs "        env: x\n        run: |\n          export PATH=/usr/bin:/bin\n"; expect fail "the hardened shell with a non-mapping env" "must have an env mapping"
for v in BASH_ENV CDPATH LD_PRELOAD LD_AUDIT LD_DEBUG GLIBC_TUNABLES MALLOC_CHECK_ LC_ALL TZ HOSTALIASES HTTPS_PROXY GIT_CONFIG_PARAMETERS; do
  fx; hs "$(noenv $v)\n$RUN"; expect fail "the hardened shell without env $v" "must set env $v: \"\""
done
fx; hs "$(setenv LD_PRELOAD /tmp/x.so)\n$RUN"; expect fail "the hardened shell with LD_PRELOAD set" 'must set env LD_PRELOAD: ""'
fx; hs "$EV\n          http_proxy: \"\"\n$RUN"; expect fail "two env names that differ only by case (GitHub refuses the file)" "env names HTTP_PROXY and http_proxy differ only by case"
fx; hs "$(setenv LD_PRELOAD null)\n$RUN"; expect fail "the hardened shell with LD_PRELOAD null" 'must set env LD_PRELOAD: ""'
fx; hs "$(setenv LD_PRELOAD '[]')\n$RUN"; expect fail "the hardened shell with LD_PRELOAD a list" 'must set env LD_PRELOAD: ""'
fx; hs "$(noenv HOME)\n$RUN"; expect fail "the hardened shell without HOME fixed" "must set env HOME: /nonexistent"
fx; hs "$(setenv HOME null)\n$RUN"; expect fail "the hardened shell with HOME null" "must set env HOME: /nonexistent"
fx; hs "$(setenv TMPDIR /tmp/x)\n$RUN"; expect fail "the hardened shell with another TMPDIR" "must set env TMPDIR: /tmp"
fx; hs "$(setenv TMPDIR '{a: b}')\n$RUN"; expect fail "the hardened shell with TMPDIR a mapping" "must set env TMPDIR: /tmp"
fx; hs "$EV\n"; expect fail "a hardened step with no run" "must have a run body"
fx; hs "$EV\n        run: \"\"\n"; expect fail "a hardened step with an empty run" "must have a run body"
fx; hs "$EV\n        run: [a]\n"; expect fail "a hardened step with a non-string run" "must have a run body"
# The shell itself
fx; printf '      - shell: bash\n        run: echo hi\n' >> "$T/$W/t.yml"; expect fail "another shell after the claude step" "after the claude step only shell: $SH"
for bad in "$SH " '/usr/bin/bash --noprofile --norc -p -eo pipefail' '/usr/bin/bash --noprofile --norc -eo pipefail {0}' '/usr/bin/bash -p -eo pipefail {0}' '/usr/bin/bash --noprofile --norc -p {0}' '/bin/bash --noprofile --norc -p -eo pipefail {0}' '/usr/bin/Bash --noprofile --norc -p -eo pipefail {0}' "/usr/bin/bash --noprofile\t--norc -p -eo pipefail {0}" sh pwsh python; do
  fx; printf '      - shell: "%b"\n        run: echo hi\n' "$bad" >> "$T/$W/t.yml"; expect fail "near-miss shell after the claude step: '$bad'" "'shell' not allowed in a job with a claude step"
done
fx; printf '      - shell: [a, b]\n        run: echo hi\n' >> "$T/$W/t.yml"; expect fail "a list as the shell" "'shell' not allowed in a job with a claude step"
fx; printf '      - shell: {a: b}\n        run: echo hi\n' >> "$T/$W/t.yml"; expect fail "a mapping as the shell" "'shell' not allowed in a job with a claude step"
fx; printf '%b' "      - uses: actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093\n        shell: $SH\n$EV\n" >> "$T/$W/t.yml"; expect fail "a uses step with the hardened shell" "a uses step may not set the hardened shell"
fx; before "      - shell: $SH\n        run: bash scripts/check-x.sh"; expect fail "the hardened shell before the claude step" "not allowed in a job with a claude step"
fx; sed -i "s|      - id: lock|      - shell: $SH\n        run: bash scripts/check-x.sh\n      - id: lock|" "$T/$W/t.yml"; expect fail "the hardened shell on step 4 (steps 1-4 are checked by shape)" "a job with a claude step must start with actions/checkout, the pin step"
fx; sed -i "s|      - name: The default branch's head passed the main guard|      - shell: $SH\n        run: bash scripts/check-x.sh\n      - name: The default branch's head passed the main guard|" "$T/$W/t.yml"; expect fail "the hardened shell on step 3" "a job with a claude step must start with actions/checkout, the pin step"
fx; sed -i "s|      - uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803|      - uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803\n        shell: $SH|" "$T/$W/t.yml"; expect fail "the hardened shell on the checkout (step 1)" "t.yml job a step 1: 'shell' not allowed in a job with a claude step"
fx; hs "$EV\n        working-directory: /tmp\n$RUN"; expect fail "the hardened shell with working-directory" "'working-directory' not allowed in a job with a claude step"
fx; sed -i "s|    runs-on: ubuntu-latest|    runs-on: ubuntu-latest\n    defaults:\n      run:\n        shell: $SH|" "$T/$W/t.yml"; expect fail "the hardened shell as a job default" "'defaults' not allowed in a job with a claude step"
fx; sed -i "s|^jobs:|defaults:\n  run:\n    shell: bash\njobs:|" "$T/$W/t.yml"; expect fail "a workflow-level default shell in a workflow with a claude step" "no workflow-level defaults in a workflow with a claude step"
fx; sed -i "s|^jobs:|defaults:\n  run:\n    shell: $SH\njobs:|" "$T/$W/t.yml"; expect fail "the hardened shell as a workflow-level default" "no workflow-level defaults in a workflow with a claude step"
fx; sed -i "s|^jobs:|defaults:\n  run:\n    shell: bash\njobs:\n  other:\n    runs-on: ubuntu-latest\n    permissions:\n      contents: read\n    steps:\n      - run: echo\n|" "$T/$W/t.yml"; expect fail "a workflow-level default shell when the claude job is one of several" "no workflow-level defaults in a workflow with a claude step"
fresh; plain p.yml; sed -i 's|    runs-on: ubuntu-latest|    runs-on: ubuntu-latest\n    defaults:\n      run:\n        shell: bash|' "$T/$W/p.yml"; expect ok "a job-level default shell on a job without a claude step" "Workflow denies OK"
fresh; plain p.yml; sed -i 's|^jobs:|defaults:\n  run:\n    shell: bash\njobs:|' "$T/$W/p.yml"; expect ok "a workflow-level default shell in a workflow without a claude step" "Workflow denies OK"
fresh; plain p.yml; sed -i 's|      - run: echo|      - run: echo\n        shell: bash|' "$T/$W/p.yml"; expect ok "a shell on a step in a job without a claude step" "Workflow denies OK"
# The other post-claude rules still apply under the hardened shell
fx; hs "$EV\n$HEAD$SCR"; expect fail "the hardened shell does not excuse a missing pin check (the body rule)" "$ORDER"
fx; printf '      - run: |\n          # sha256sum --check --strict\n          bash scripts/check-x.sh\n' >> "$T/$W/t.yml"; expect fail "a pin check in a comment does not count (default-shell step)" "must check its pinned files"
fx; hs "$EV\n$HEAD$PIN1          /usr/bin/env -i PATH=/usr/bin:/bin HOME=/nonexistent TMPDIR=/tmp /usr/bin/bash scripts/check-x.sh pull/1\n"; expect fail "the hardened shell does not excuse PR data" "runs or checks out PR code"
fx; before "      - id: claude2\n        uses: anthropics/claude-code-action@2dca132ff0e0c4094ce6048b422c6915a071210b\n        with:\n          claude_code_oauth_token: \${{ secrets.CLAUDE_TOKEN_REVIEW_V2 }}\n          path_to_claude_code_executable: \${{ steps.lock.outputs.claude-path }}\n          path_to_bun_executable: \${{ steps.lock.outputs.bun-path }}\n          github_token: \${{ github.token }}\n          classify_inline_comments: \"false\"\n          prompt: \"Do the task.\"\n          claude_args: |\n            --model haiku\n            --disallowedTools \"Skill(payload),Write,WebFetch,WebSearch,Read(//proc/**),Read(//sys/**),Read(//home/runner/work/_temp/**),Read(//home/runner/.*/**),Read(//etc/**),Read(//dev/**),Read(//home/runner/runners/**),Read(./.git/**)\"\n      - shell: $SH\n$EV\n$RUN"; expect fail "two claude steps in one job" "only one claude step per job (found 2)"
# post_claude_require_shell: off here (the workflows run their post-Claude steps in the default shell until #44, a founder decision recorded in the changelog); on, every run step after the claude step must be hardened
fresh; expect ok "the real workflows with post_claude_require_shell off" "Workflow denies OK"
fresh; require_on; out=$(bash "$T/scripts/check-workflows.sh" "$T" 2>&1); n=$(grep -c "a run step after the claude step must set shell: $SH (policy post_claude_require_shell)" <<<"$out")
if [ "$n" = 8 ] && grep -q "review.yml job review step 8:" <<<"$out" && grep -q "egress-lock-claude.yml job probe step 7:" <<<"$out" && grep -q "egress-lock-claude.yml job scrub step 6:" <<<"$out" && grep -q "egress-lock-claude.yml job reads step 6:" <<<"$out" && grep -q "agent-manager.yml job shift step 9:" <<<"$out" && grep -q "claude.yml job answer step 6:" <<<"$out" && grep -q "agent-daily-report.yml job report step 6:" <<<"$out" && grep -q "agent-weekly-audit.yml job audit step 8:" <<<"$out"; then t PASS "the real workflows with post_claude_require_shell on: all 8 post-Claude steps (5 hand-off, 3 probe) refused"; else t FAIL "require_shell on: expected 8 refused steps, got $n"; echo "$out"; fi; rm -rf "$T"
fx; require_on; SCRIPT="$T/scripts/check-workflows.sh" expect fail "require_shell on: the fixture's After step runs in the default shell" "t.yml job a step 6: a run step after the claude step must set shell: $SH"
fx; require_on; python3 - "$T/$W/t.yml" "$SH" "$EV" "$RUN" "$(sha256sum "$T/.github/pins.txt" | cut -c1-64)" <<'PYEOF2'
import re, sys; p, sh, ev, run, pins = sys.argv[1:6]; s = open(p).read(); a = s.index("      - name: After\n")
ev = re.sub(r'PINS_SHA256: "[0-9a-f]*"', f'PINS_SHA256: "{pins}"', ev)   # repin changed pins.txt
s = s[:a] + f"      - name: After\n        shell: {sh}\n{ev}\n{run}".replace("\\n", "\n"); open(p, "w").write(s)
PYEOF2
out=$(bash "$T/scripts/check-workflows.sh" "$T" 2>&1); if grep -q "^ERROR: t.yml" <<<"$out"; then t FAIL "require_shell on: a hardened After step passes (only the real, not yet hardened, workflows may fail)"; echo "$out"; else t PASS "require_shell on: a hardened After step passes (only the real, not yet hardened, workflows fail)"; fi; rm -rf "$T"
summary
