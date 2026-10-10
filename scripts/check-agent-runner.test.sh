#!/usr/bin/env bash
# Tests scripts/check-agent-runner.sh (on copies of .github/agent-runner with one thing broken at a time) and the host script
# .github/agent-runner/agent-runner.sh with stubbed docker, gh, systemctl, sudo and friends (no Docker, no network).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
SCRIPT="$HERE/check-agent-runner.sh"; SRC="$ROOT/.github/agent-runner"
TMPROOT="${TMPDIR:-/tmp}"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-testlib.sh"

# --- the guard ------------------------------------------------------------------------------------------------------------
fresh() { T=$(mktemp -d "$TMPROOT/arg.XXXXXX"); cp -r "$SRC/." "$T/"; }
expect() { # expect <ok|fail> <name> <message>: runs the guard on $T
  local want=$1 name=$2 msg=$3
  out=$(bash "$SCRIPT" "$T" 2>&1); rc=$?; got=$([ $rc = 0 ] && echo ok || echo fail)
  if [ "$got" = "$want" ] && grep -qF -- "$msg" <<<"$out"; then t PASS "$name"; else t FAIL "$name ($got)"; echo "$out" | tail -n 5; fi
  rm -rf "$T"; }
fresh; expect ok "the real folder passes" "Agent runner files OK"
out=$(bash "$SCRIPT" 2>&1) && grep -q "Agent runner files OK" <<<"$out" && t PASS "default folder is .github/agent-runner" || t FAIL "default folder"
fresh; rm "$T/NOTICE.md"; expect fail "missing file" "missing $T/NOTICE.md"
fresh; python3 -I -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["syscalls"].append({"names":["ptrace"],"action":"SCMP_ACT_ALLOW"}); json.dump(d,open(p,"w"))' "$T/seccomp.json"
expect fail "hand-edited seccomp.json" "seccomp.json differs from make-seccomp.py's output"
fresh; printf 'import sys; sys.exit(1)\n' > "$T/make-seccomp.py"; expect fail "generator fails" "make-seccomp.py failed"
fresh; python3 -I -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["defaultAction"]="SCMP_ACT_ALLOW"; json.dump(d,open(p,"w"))' "$T/docker-default-seccomp.json"
python3 -I "$T/make-seccomp.py" "$T/docker-default-seccomp.json" "$T/seccomp.json"; expect fail "allow-by-default profile" "must deny by default"
fresh; sed -i 's|^FROM ubuntu:24.04@sha256:[0-9a-f]*$|FROM ubuntu:24.04|' "$T/Dockerfile"; expect fail "base image not pinned by digest" "FROM must be ubuntu:<version>@sha256:<digest>"
fresh; printf 'FROM ubuntu:24.04@sha256:%s\n' "$(printf 'a%.0s' {1..64})" >> "$T/Dockerfile"; expect fail "two FROM lines" "exactly one FROM"
fresh; sed -i 's|^ARG RUNNER_VERSION=.*|ARG RUNNER_VERSION=latest|' "$T/Dockerfile"; expect fail "runner version not pinned" "ARG RUNNER_VERSION=<x.y.z>"
fresh; sed -i 's|^ARG RUNNER_SHA256=.*|ARG RUNNER_SHA256=|' "$T/Dockerfile"; expect fail "runner sha missing" "ARG RUNNER_SHA256=<64 hex>"
fresh; sed -i 's|sha256sum --check --quiet|true|' "$T/Dockerfile"; expect fail "runner download unchecked" "must be checked against RUNNER_SHA256"
fresh; sed -i 's|^ENV AGENT_LOCK_CONTAINER=1|ENV AGENT_LOCK_CONTAINER=0|' "$T/Dockerfile"; expect fail "container mode off" "ENV AGENT_LOCK_CONTAINER=1"
fresh; sed -i 's|^USER runner$|USER root|' "$T/Dockerfile"; expect fail "image runs as root" "USER runner"
fresh; sed -i 's|rm -f /usr/bin/newuidmap /usr/bin/newgidmap|true|' "$T/Dockerfile"; expect fail "setuid helpers kept" "remove the setuid helpers"
fresh; printf 'RUN curl -fsSL https://example.com/tool.sh | bash\n' >> "$T/Dockerfile"; expect fail "extra download" "only the pinned runner download may use curl/wget"
fresh; printf 'RUN wget -O /tmp/x https://example.com/x\n' >> "$T/Dockerfile"; expect fail "extra wget download" "only the pinned runner download"
fresh; printf 'FROM node:latest\n' >> "$T/Dockerfile"; sed -i '0,/^FROM /{/^FROM ubuntu/d}' "$T/Dockerfile"; expect fail "latest tag" "FROM must be ubuntu"
fresh; printf 'if [ ; then\n' >> "$T/entrypoint.sh"; expect fail "entrypoint does not parse" "entrypoint.sh does not parse"
fresh; printf 'if [ ; then\n' >> "$T/agent-runner.sh"; expect fail "host script does not parse" "agent-runner.sh does not parse"
fresh; sed -i 's|<<<"\$token"|-e "TOKEN=$token"|' "$T/agent-runner.sh"; expect fail "token in the environment" "must go to the container on stdin"
fresh; sed -i 's|--cap-drop ALL|--cap-drop NET_RAW|' "$T/agent-runner.sh"; expect fail "capabilities kept" "must start with --cap-drop ALL"
fresh; sed -i 's|seccomp=\$HERE/seccomp.json|seccomp=unconfined|' "$T/agent-runner.sh"; expect fail "seccomp off" "must use seccomp.json"
fresh; sed -i 's|--cap-add NET_ADMIN|--cap-add NET_ADMIN --cap-add SYS_ADMIN|' "$T/agent-runner.sh"; expect fail "SYS_ADMIN added" "no SYS_ADMIN or --privileged"
fresh; sed -i 's|TOKEN=\$(head -c 200|TOKEN=$(echo "$REG_TOKEN"|' "$T/entrypoint.sh"; expect fail "entrypoint token from env" "must be read from stdin"
fresh; printf 'nothing here\n' > "$T/NOTICE.md"; expect fail "notice without the profile" "NOTICE.md must name docker-default-seccomp.json"

# --- the host script, with stubs ----------------------------------------------------------------------------------------
H=$(mktemp -d "$TMPROOT/arh.XXXXXX"); trap 'rm -rf "$H"' EXIT
S="$H/stubs"; mkdir -p "$S" "$H/home" "$H/repo/.github/actions/agent-egress-lock"
cp -r "$SRC" "$H/repo/.github/agent-runner"; cp "$ROOT/.github/actions/agent-egress-lock/action.yml" "$H/repo/.github/actions/agent-egress-lock/"
stub() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$S/$1"; chmod +x "$S/$1"; }
LOG="$H/calls.log"
stub docker 'echo "docker $*" >> "$LOG"; case "$1" in info) echo "[name=${STUB_SEC:-rootless}]";; run) case " $* " in *" -i "*) cat > "$LOG.stdin";; esac; exit "${STUB_RUN_RC:-0}";; ps) echo "${STUB_PS:-}";; esac'
stub gh 'echo "gh $*" >> "$LOG"; case "$*" in "auth status") exit "${STUB_AUTH_RC:-0}";; "repo view"*) echo "${STUB_REPO:-owner/repo}";;
  *registration-token*) [ -n "${STUB_TOKEN+x}" ] && { echo "$STUB_TOKEN"; exit 0; }; echo "AAAAtest-not-a-real-token"; exit "${STUB_TOKEN_RC:-0}";;
  *actions/runners*) echo "runner pc-lane1: online, busy=false";; esac'
stub sudo 'echo "sudo $*" >> "$LOG"; [ "$1" = tee ] && cat > /dev/null; exit "${STUB_SUDO_RC:-0}"'
stub systemctl 'echo "systemctl $*" >> "$LOG"'
stub loginctl 'echo "loginctl $*" >> "$LOG"; exit "${STUB_LINGER_RC:-0}"'
stub resolvectl 'printf "Global\n  DNS Servers: %s\n" "${STUB_DNS:-192.168.1.1 fe80::1}"'
stub nproc 'echo 12'; stub uname 'echo "${STUB_ARCH:-x86_64}"'; stub hostname 'echo pc'
stub git 'echo "git $*" >> "$LOG"; case "$*" in *rev-parse*) echo abc1234;; *get-url*) echo git@github.com:owner/repo.git;; esac'
AR="$H/repo/.github/agent-runner/agent-runner.sh"
run() { # run <ok|fail> <name> <message> [VAR=value ...] -- <args...>
  local want=$1 name=$2 msg=$3; shift 3; local envs=(); while [ "$1" != -- ]; do envs+=("$1"); shift; done; shift
  : > "$LOG"; rm -f "$LOG.stdin"
  out=$(cd "$H" && env -i PATH="$S:/usr/bin:/bin" HOME="$H/home" USER=founder LOG="$LOG" AGENT_RUNNER_CONFIG="$H/home/env" AGENT_RUNNER_UNIT_DIR="$H/home/units" \
        AGENT_RUNNER_ONCE=1 "${envs[@]}" bash "$AR" "$@" 2>&1); rc=$?; got=$([ $rc = 0 ] && echo ok || echo fail)
  if [ "$got" = "$want" ] && grep -qF -- "$msg" <<<"$out"; then t PASS "$name"; else t FAIL "$name ($got)"; echo "$out" | tail -n 6; fi; }

run fail "no command: usage" "Usage: bash .github/agent-runner/agent-runner.sh <command>" --
run fail "lane before setup" "no config at" -- lane 1
run fail "setup: not x86_64" "the runner image is x86_64 only" STUB_ARCH=aarch64 -- setup
run fail "setup: Docker not rootless" "Docker is not in rootless mode" STUB_SEC=apparmor -- setup
run fail "setup: gh not logged in" "gh is not logged in" STUB_AUTH_RC=1 -- setup
run fail "setup: bad lanes" "lanes must be 1-99" -- setup 0
printf 'nameserver 127.0.0.53\n' > "$H/resolv.conf"
run fail "setup: no DNS found" "cannot find this PC's DNS server" STUB_DNS=fe80::1 "AGENT_RUNNER_RESOLV=$H/resolv.conf" -- setup
printf 'nameserver 127.0.0.53\nnameserver 10.0.0.2\n' > "$H/resolv.conf"
run ok "setup: DNS from resolv.conf when resolvectl has none" "DNS 10.0.0.2" STUB_DNS=fe80::1 "AGENT_RUNNER_RESOLV=$H/resolv.conf" -- setup
run fail "setup: modprobe fails" "modprobe failed" STUB_SUDO_RC=1 -- setup
run fail "setup: odd repository name" "cannot tell the repository" "STUB_REPO=owner/re po" -- setup
run ok "setup writes config and unit" "Setup done: owner/repo, 3 lanes, 4 CPUs and 4g memory each, DNS 192.168.1.1" -- setup
check "config has the repo, lanes and DNS" bash -c 'grep -qx "REPO=owner/repo" "$1" && grep -qx "LANES=3" "$1" && grep -qx "DNS=192.168.1.1" "$1" && grep -qx "CPUS=4" "$1"' _ "$H/home/env"
check "unit runs the lane loop" grep -q 'agent-runner.sh lane %i' "$H/home/units/agent-lane@.service"
check "modules loaded and kept, user namespaces allowed, linger enabled" bash -c 'grep -q "sudo modprobe nf_tables nf_conntrack nf_nat nft_compat nft_redir xt_owner" "$1" && grep -q "tee /etc/modules-load.d/agent-runner.conf" "$1" && grep -q "loginctl enable-linger founder" "$1" && grep -q "systemctl --user daemon-reload" "$1"' _ "$LOG"
run ok "setup with 6 lanes" "6 lanes, 2 CPUs" -- setup 6
run ok "setup: linger failure is only a note" "lanes stop when you log out" STUB_LINGER_RC=1 -- setup
run ok "build tags the image" "Built agent-runner:current (agent-runner:abc1234)" -- build
check "build uses this folder, no pull" grep -q "docker build --pull=false -t agent-runner:current -t agent-runner:abc1234 $H/repo/.github/agent-runner" "$LOG"
run ok "check runs the lock in the image" "" -- check
check "check: lock mounted read-only, lock pins passed, image in check mode" bash -c 'grep -q -- "-v $2/repo/.github/actions/agent-egress-lock:/lock:ro" "$1" && grep -q -- "-e CLAUDE_CODE_VERSION=" "$1" && grep -q -- "-e BUN_SHA256=" "$1" && grep -q "agent-runner:current check" "$1"' _ "$LOG" "$H"
check "containers drop every capability and use the seccomp profile and limits" bash -c 'grep -q -- "--cap-drop ALL --cap-add NET_ADMIN" "$1" && grep -q -- "--security-opt seccomp=$2/repo/.github/agent-runner/seccomp.json" "$1" && grep -q -- "--memory 4g --memory-swap 4g --cpus 4 --pids-limit 4096 --dns 192.168.1.1" "$1" && ! grep -qE -- "--privileged|SYS_ADMIN" "$1"' _ "$LOG" "$H"
run ok "lane: one job then exit (test mode)" "lane 1: container finished (exit 0)" -- lane 1
check "lane: token on stdin only, ephemeral runner in run mode" bash -c 'grep -qx "AAAAtest-not-a-real-token" "$1.stdin" && ! grep -q "AAAAtest" "$1" && grep -q -- "-e RUNNER_URL=https://github.com/owner/repo -e RUNNER_NAME=pc-lane1 -e RUNNER_LABELS=agents agent-runner:current run" "$1"' _ "$LOG"
run fail "lane: container failure is reported (and returned in test mode)" "container finished (exit 3)" STUB_RUN_RC=3 -- lane 1
run fail "lane: bad number" "lane must be a number" -- lane x
run ok "start enables every lane" "3 lanes started" -- start
check "start: agent-lane@1..3" bash -c '[ "$(grep -c "systemctl --user enable --now agent-lane@" "$1")" = 3 ]' _ "$LOG"
run ok "stop disables lanes and stops containers" "lanes stopped" STUB_PS=abc -- stop
check "stop: containers stopped" grep -q "docker stop abc" "$LOG"
run ok "status lists runners" "runner pc-lane1: online, busy=false" -- status
# The lane loop waits when no token comes (offline): run with a fast sleep and stop after the retry message.
stub sleep 'echo "sleep $*" >> "$LOG"; [ "$1" = 60 ] && exit 99'
out=$(cd "$H" && env -i PATH="$S:/usr/bin:/bin" HOME="$H/home" USER=founder LOG="$LOG" AGENT_RUNNER_CONFIG="$H/home/env" STUB_TOKEN_RC=1 bash "$AR" lane 2 2>&1)
grep -q "lane 2: no registration token (offline, or gh not logged in); retrying in 60s" <<<"$out" && grep -q "sleep 60" "$LOG" && ! grep -q "docker run" "$LOG" \
  && t PASS "lane: no token -> wait, no container" || { t FAIL "lane: no token"; echo "$out" | tail -n 4; }

summary
