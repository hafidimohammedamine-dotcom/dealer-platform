#!/usr/bin/env bash
# Proves what the policy's post_claude_shell (scripts/check-workflows-policy.json) does on this machine's bash, the way a
# workflow step runs it: the runner replaces {0} with the step's script path. With -p bash reads no BASH_ENV or ENV file,
# ignores SHELLOPTS, BASHOPTS and CDPATH from the environment, and imports no function from a BASH_FUNC_<name>%% variable;
# -eo pipefail still applies. (IFS is never imported by bash, with or without -p.) The bash version is printed first.
# Run on the runners' bash by CI (scripts/check-coverage.sh runs every scripts/*.test.sh).
set -uo pipefail
. "$(cd "$(dirname "$0")" && pwd)/check-testlib.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
SHELL_LINE=$(python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1]))["post_claude_shell"])' "$HERE/check-workflows-policy.json")
T=$(mktemp -d "${TMPDIR:-/tmp}/pcs.XXXXXX"); trap 'rm -rf "$T"' EXIT
printf 'PLANTED=yes\n' > "$T/planted.sh"
mkdir -p "$T/cdp/sub"
printf 'echo "bash_env=${PLANTED:-}"\nf 2>/dev/null && echo "function=imported" || echo "function=none"\necho "opts=$SHELLOPTS bashopts=$BASHOPTS"\ncd sub 2>/dev/null && echo "cdpath=used" || echo "cdpath=ignored"\n' > "$T/step.sh"
printf 'false | true\necho reached\n' > "$T/pipe.sh"
read -ra WORDS <<<"$SHELL_LINE"   # the runner splits the shell line on spaces and replaces {0}
run_step() { local s=$1; local args=(); local w; for w in "${WORDS[@]}"; do args+=("${w//\{0\}/$s}"); done
  (cd "$T" && /usr/bin/env -i 'BASH_FUNC_f%%=() { echo planted; }' BASH_ENV="$T/planted.sh" ENV="$T/planted.sh" SHELLOPTS=xtrace BASHOPTS=nullglob CDPATH="$T/cdp" "${args[@]}" 2>&1); }
echo "bash: $(/usr/bin/bash --version | head -n 1)"

[ "${WORDS[0]}" = /usr/bin/bash ] && [[ " ${WORDS[*]} " == *" -p "* ]] && t PASS "the policy shell is an absolute bash with -p" || t FAIL "the policy shell: $SHELL_LINE"
out=$(run_step "$T/step.sh"); rc=$?
[ $rc = 0 ] && grep -q '^bash_env=$' <<<"$out" && t PASS "BASH_ENV and ENV are not read (-p)" || { t FAIL "BASH_ENV/ENV read: rc=$rc"; echo "$out"; }
grep -q '^function=none$' <<<"$out" && t PASS "no function is imported from BASH_FUNC_f%% (-p)" || { t FAIL "function imported"; echo "$out"; }
! grep -q 'opts=[^ ]*xtrace' <<<"$out" && ! grep -q 'bashopts=.*nullglob' <<<"$out" \
  && t PASS "SHELLOPTS and BASHOPTS from the environment are ignored (-p)" || { t FAIL "SHELLOPTS/BASHOPTS honoured"; echo "$out"; }
grep -q '^cdpath=ignored$' <<<"$out" && t PASS "CDPATH from the environment is ignored (-p)" || { t FAIL "CDPATH honoured"; echo "$out"; }
out=$(run_step "$T/pipe.sh"); rc=$?
[ $rc != 0 ] && ! grep -q reached <<<"$out" && t PASS "-eo pipefail still applies (a failed pipe stops the step)" || { t FAIL "pipefail: rc=$rc"; echo "$out"; }
# The same planted environment WITHOUT -p (what a default-shell step gets): shows the difference is real on this bash.
out=$(/usr/bin/env -i 'BASH_FUNC_f%%=() { echo planted; }' BASH_ENV="$T/planted.sh" /usr/bin/bash --noprofile --norc -eo pipefail "$T/step.sh" 2>&1)
grep -q '^bash_env=yes$' <<<"$out" && grep -q '^function=imported$' <<<"$out" && t PASS "without -p the same environment is honoured (the control case)" || { t FAIL "control case"; echo "$out"; }
summary
