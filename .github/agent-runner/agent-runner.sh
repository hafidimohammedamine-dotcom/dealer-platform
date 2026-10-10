#!/usr/bin/env bash
# Runs the agents' GitHub Actions jobs on this PC: one throwaway container per job, N lanes in parallel (founder-owned file).
# Usage: bash .github/agent-runner/agent-runner.sh <command>
#   setup [lanes]  one-time host setup: checks rootless Docker and the gh login, loads the firewall kernel modules, allows
#                  user namespaces for bubblewrap, writes the config and the user service, enables lingering.
#   build          builds the runner image from this checkout (tag agent-runner:current).
#   check          runs the image once without registering: the network lock in container mode and its self-test.
#   start / stop   starts or stops every lane (systemd user services agent-lane@1..N).
#   status         lanes, running containers, runners GitHub sees for this repository.
#   lane <n>       the lane loop itself (what the service runs): registration token -> one ephemeral job -> again.
# Config: ~/.config/agent-runner/env (REPO, LANES, MEMORY, CPUS, DNS). Nothing here stores a token: gh keeps the founder's
# login; each container gets a one-hour registration token on stdin. Details: docs/runbooks/agent-runner.md.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${AGENT_RUNNER_REPO_DIR:-$(cd "$HERE/../.." && pwd)}"
CONFIG="${AGENT_RUNNER_CONFIG:-$HOME/.config/agent-runner/env}"
UNIT_DIR="${AGENT_RUNNER_UNIT_DIR:-$HOME/.config/systemd/user}"
IMAGE=agent-runner:current
LABELS=agents   # workflows select these runners with runs-on: [self-hosted, agents]
die() { echo "ERROR: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 is not installed$2"; }
load_config() { [ -f "$CONFIG" ] || die "no config at $CONFIG: run 'agent-runner.sh setup' first"; # shellcheck source=/dev/null
  . "$CONFIG"; : "${REPO:?}" "${LANES:?}" "${MEMORY:?}" "${CPUS:?}" "${DNS:?}"; }

# The host's upstream DNS server, for the containers: the lock allows DNS only to it (dnsmasq inside the container).
host_dns() {
  local d
  d=$(resolvectl status 2>/dev/null | awk '/DNS Servers:/ {for (i=3; i<=NF; i++) if ($i ~ /^[0-9.]+$/) {print $i; exit}}' || true)
  [ -n "$d" ] || d=$(awk '$1=="nameserver" && $2 !~ /^127\./ && $2 ~ /^[0-9.]+$/ {print $2; exit}' "${AGENT_RUNNER_RESOLV:-/etc/resolv.conf}" 2>/dev/null || true)
  echo "$d"
}

# Settings read from the lock action, so the check runs exactly what the jobs run.
lock_env() {
  awk -F'"' '/^ *(CLAUDE_CODE_VERSION|CLAUDE_CODE_SHA256|BUN_VERSION|BUN_SHA256): "/ {gsub(/^ *| *$/, "", $1); sub(/:$/, "", $1); printf "-e %s=%s\n", $1, $2}' \
    "$ROOT/.github/actions/agent-egress-lock/action.yml"
}

# Every container: no capability except what the lock needs inside its own network namespace, Docker's seccomp profile
# plus user namespaces (bubblewrap), limits. Rootless Docker makes the container's root an unprivileged user on this PC.
run_flags() {
  echo --rm --cap-drop ALL --cap-add NET_ADMIN --cap-add NET_BIND_SERVICE --cap-add SETUID --cap-add SETGID \
       --cap-add CHOWN --cap-add FOWNER --cap-add DAC_OVERRIDE --cap-add AUDIT_WRITE \
       --security-opt "seccomp=$HERE/seccomp.json" --memory "$MEMORY" --memory-swap "$MEMORY" --cpus "$CPUS" \
       --pids-limit 4096 --dns "$DNS"
}

cmd_setup() {
  local lanes="${1:-3}" mods=/etc/modules-load.d/agent-runner.conf sysd=/etc/sysctl.d/80-agent-runner.conf
  [[ "$lanes" =~ ^[1-9][0-9]?$ ]] || die "lanes must be 1-99"
  [ "$(uname -m)" = x86_64 ] || die "this PC is $(uname -m); the runner image is x86_64 only"
  need docker " (rootless mode: https://docs.docker.com/engine/security/rootless/)"
  need gh " (then: gh auth login)"
  docker info --format '{{.SecurityOptions}}' 2>/dev/null | grep -q rootless || die "Docker is not in rootless mode for this user (containers must not be root on this PC)"
  gh auth status >/dev/null 2>&1 || die "gh is not logged in: run 'gh auth login' as the founder"
  local repo; repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null) || repo=$(git -C "$ROOT" remote get-url origin | sed -E 's#.*github.com[:/]##; s#\.git$##')
  [[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "cannot tell the repository (run inside the checkout, or gh repo view fails)"
  local dns; dns=$(host_dns); [ -n "$dns" ] || die "cannot find this PC's DNS server (resolvectl status / /etc/resolv.conf)"
  # The firewall inside a container cannot load kernel modules; load them here and keep them across reboots.
  echo "Loading the firewall kernel modules (sudo): nf_tables nf_conntrack nf_nat nft_compat nft_redir xt_owner"
  sudo modprobe nf_tables nf_conntrack nf_nat nft_compat nft_redir xt_owner || die "modprobe failed"
  printf 'nf_tables\nnf_conntrack\nnf_nat\nnft_compat\nnft_redir\nxt_owner\n' | sudo tee "$mods" >/dev/null
  # Ubuntu 24.04 strips capabilities from user namespaces of unconfined programs; inside the containers that would break
  # bubblewrap (Claude Code's subprocess isolation). This PC is dedicated to the agents; the rootless containers are the
  # boundary, so the host switch goes off (recorded in docs/runbooks/agent-runner.md).
  if [ -f /proc/sys/kernel/apparmor_restrict_unprivileged_userns ]; then
    echo "Allowing user namespaces for bubblewrap inside the containers (sudo): kernel.apparmor_restrict_unprivileged_userns=0"
    sudo sysctl -q -w kernel.apparmor_restrict_unprivileged_userns=0 || die "sysctl failed"
    echo 'kernel.apparmor_restrict_unprivileged_userns=0' | sudo tee "$sysd" >/dev/null
  fi
  local cpus; cpus=$(( $(nproc) / lanes )); [ "$cpus" -ge 1 ] || cpus=1
  mkdir -p "$(dirname "$CONFIG")" "$UNIT_DIR"
  { echo "REPO=$repo"; echo "LANES=$lanes"; echo "MEMORY=4g"; echo "CPUS=$cpus"; echo "DNS=$dns"; } > "$CONFIG"
  cat > "$UNIT_DIR/agent-lane@.service" <<EOF
[Unit]
Description=Agent runner lane %i (one throwaway container per GitHub Actions job)
After=default.target

[Service]
ExecStart=/usr/bin/env bash $HERE/agent-runner.sh lane %i
Restart=always
RestartSec=30

[Install]
WantedBy=default.target
EOF
  systemctl --user daemon-reload
  loginctl enable-linger "$USER" 2>/dev/null || echo "note: 'loginctl enable-linger $USER' failed; lanes stop when you log out"
  echo "Setup done: $repo, $lanes lanes, ${cpus} CPUs and 4g memory each, DNS $dns. Next: build, check, start."
}

cmd_build() {
  local sha; sha=$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo local)
  docker build --pull=false -t "$IMAGE" -t "agent-runner:$sha" "$HERE"
  echo "Built $IMAGE (agent-runner:$sha)"
}

cmd_check() {
  load_config
  # shellcheck disable=SC2046
  docker run $(run_flags) -v "$ROOT/.github/actions/agent-egress-lock:/lock:ro" $(lock_env) "$IMAGE" check
}

cmd_lane() {
  local n="${1:?lane number}" token rc
  [[ "$n" =~ ^[0-9]+$ ]] || die "lane must be a number"
  load_config
  while :; do
    if ! token=$(gh api -X POST "repos/$REPO/actions/runners/registration-token" --jq .token 2>/dev/null) || [ -z "$token" ]; then
      echo "lane $n: no registration token (offline, or gh not logged in); retrying in 60s"; sleep 60; continue
    fi
    rc=0
    # shellcheck disable=SC2046
    docker run $(run_flags) -i --name "agent-lane-$n" --hostname "agent-lane-$n" \
      -e "RUNNER_URL=https://github.com/$REPO" -e "RUNNER_NAME=$(hostname -s)-lane$n" -e "RUNNER_LABELS=$LABELS" \
      "$IMAGE" run <<<"$token" || rc=$?
    token=
    echo "lane $n: container finished (exit $rc)"; sleep 5
    [ -z "${AGENT_RUNNER_ONCE:-}" ] || return "$rc"   # tests
  done
}

cmd_start() { load_config; local i; for i in $(seq 1 "$LANES"); do systemctl --user enable --now "agent-lane@$i.service"; done; echo "$LANES lanes started"; }
cmd_stop() { load_config; local i; for i in $(seq 1 "$LANES"); do systemctl --user disable --now "agent-lane@$i.service" 2>/dev/null || true; done
  docker ps -q --filter name=agent-lane- | xargs -r docker stop >/dev/null 2>&1 || true; echo "lanes stopped"; }
cmd_status() { load_config
  systemctl --user list-units 'agent-lane@*' --no-pager 2>/dev/null || true
  docker ps --filter name=agent-lane- --format 'container {{.Names}} up {{.RunningFor}}' 2>/dev/null || true
  gh api "repos/$REPO/actions/runners" --jq '.runners[] | "runner \(.name): \(.status), busy=\(.busy)"' 2>/dev/null || echo "(GitHub runner list unavailable)"; }

case "${1:-}" in
  setup) cmd_setup "${2:-}";; build) cmd_build;; check) cmd_check;; lane) cmd_lane "${2:-}";;
  start) cmd_start;; stop) cmd_stop;; status) cmd_status;;
  *) sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 2;;
esac
