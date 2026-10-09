#!/usr/bin/env bash
# Agent egress lock (founder-owned). See action.yml. Runs on GitHub-hosted Ubuntu runners as the `runner` user with sudo.
# Order matters: everything that needs sudo or the open internet happens first; sudo is removed last.
#
# Design: every outbound TCP connection on port 443 from any user except the proxy is redirected to a local nginx "stream"
# proxy that reads the TLS server name (SNI) and connects only to allow-listed host names - so an allowed IP cannot be
# reused for another name. Port 80, raw IPs without a name, other DNS servers and IPv6 are rejected. DNS answers only for
# allow-listed names (dnsmasq). Docker is stopped and sudo removed so no later step can undo this.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
die() { echo "::error::agent egress lock: $*"; exit 1; }
[ "$(uname -s)" = Linux ] && [ "$(uname -m)" = x86_64 ] || die "Linux x64 runners only"
[ -n "${GITHUB_OUTPUT:-}" ] && [ -n "${GITHUB_ENV:-}" ] || die "must run inside GitHub Actions"
[[ "${CLAUDE_CODE_VERSION:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "bad CLAUDE_CODE_VERSION"
[[ "${CLAUDE_CODE_SHA256:-}" =~ ^[0-9a-f]{64}$ ]] || die "bad CLAUDE_CODE_SHA256"
[[ "${BUN_VERSION:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "bad BUN_VERSION"
[[ "${BUN_SHA256:-}" =~ ^[0-9a-f]{64}$ ]] || die "bad BUN_SHA256"

# --- Allowed names (founder-owned list; no extras from workflows) ---------------------------------------------------------
mapfile -t NAMES < <(sed -e 's/#.*//' -e 's/[[:space:]]//g' "$HERE/allow-domains.txt" | sed '/^$/d')
[ "${#NAMES[@]}" -gt 0 ] || die "empty allow-list"
for d in "${NAMES[@]}"; do   # exact host names only, no wildcards
  [[ "$d" =~ ^([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}$ ]] || die "not a plain host name: '$d'"
done
# The runner's own services need no new connection during the steps (measured 2026-10-09). The one exception is the OIDC
# token service of a job with `id-token: write` (claude.yml): its generated host name is read from the runner's variable and
# allowed exactly, for this run only.
if [ -n "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" ]; then
  OIDC_HOST=$(sed -E 's#^https://([^/:]+)/.*$#\1#' <<<"$ACTIONS_ID_TOKEN_REQUEST_URL")
  [[ "$OIDC_HOST" =~ ^[a-z0-9-]+\.actions\.githubusercontent\.com$ ]] || die "unexpected OIDC host: '$OIDC_HOST'"
  NAMES+=("$OIDC_HOST")
fi

# --- 1. Install the pinned Claude Code binary, checked against its pinned sha256 (from Anthropic's release manifest) ------
BIN="$HOME/.local/bin/claude"
mkdir -p "$HOME/.local/bin"
DL=$(mktemp)
curl -fsSL --retry 3 -o "$DL" "https://downloads.claude.ai/claude-code-releases/$CLAUDE_CODE_VERSION/linux-x64/claude"
echo "$CLAUDE_CODE_SHA256  $DL" | sha256sum --check --quiet || die "Claude Code download does not match its pinned sha256"
install -m 0755 "$DL" "$BIN" && rm -f "$DL"
"$BIN" --version | grep -q "^$CLAUDE_CODE_VERSION " || die "Claude Code $CLAUDE_CODE_VERSION not installed"
{ echo "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1"; echo "DISABLE_AUTOUPDATER=1"; } >> "$GITHUB_ENV"
# Bun for the claude-code-action (its own setup-bun would download from GitHub's release storage, which the lock blocks),
# pinned to the version the action expects and checked against the release's SHASUMS256.txt.
BUN="$HOME/.local/bin/bun"
DL=$(mktemp); UZ=$(mktemp -d)
curl -fsSL --retry 3 -o "$DL" "https://github.com/oven-sh/bun/releases/download/bun-v$BUN_VERSION/bun-linux-x64.zip"
echo "$BUN_SHA256  $DL" | sha256sum --check --quiet || die "Bun download does not match its pinned sha256"
unzip -q -o "$DL" -d "$UZ" && install -m 0755 "$UZ/bun-linux-x64/bun" "$BUN" && rm -rf "$DL" "$UZ"
[ "$("$BUN" --version)" = "$BUN_VERSION" ] || die "Bun $BUN_VERSION not installed"

# --- 2. DNS allow-list (dnsmasq) and SNI proxy (nginx stream) ------------------------------------------------------------
PKGS=(dnsmasq-base nginx libnginx-mod-stream bubblewrap socat)
apt_install() { sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends "${PKGS[@]}" >/dev/null 2>&1; }
apt_install || { sudo apt-get update -qq >/dev/null && apt_install; } || die "could not install ${PKGS[*]}"
# Claude Code's subprocess isolation (CLAUDE_CODE_SUBPROCESS_ENV_SCRUB) runs tools in bubblewrap, which needs user
# namespaces. Ubuntu 24.04 restricts those through AppArmor; keep the restriction on for everything else and let only
# /usr/bin/bwrap create them; what bwrap starts gets no capabilities and no user namespaces (agent-bwrap.apparmor).
USERNS="${AGENT_LOCK_TEST_USERNS:-/proc/sys/kernel/apparmor_restrict_unprivileged_userns}"   # tests use a temp file
if [ -f "$USERNS" ]; then
  sudo sysctl -q -w kernel.apparmor_restrict_unprivileged_userns=1
  sudo install -m 0644 "$HERE/agent-bwrap.apparmor" /etc/apparmor.d/agent-bwrap
  sudo apparmor_parser -r /etc/apparmor.d/agent-bwrap || die "could not load the AppArmor profile for bubblewrap"
  # Other profiles on the image grant user namespaces too (browsers, podman, lxc, ...); unload them so only bwrap keeps it.
  # unprivileged_userns stays: it is the profile the kernel uses to restrict user namespaces of unconfined programs.
  AA_DIR="${AGENT_LOCK_TEST_APPARMOR_DIR:-/etc/apparmor.d}"
  AA_LOADED="${AGENT_LOCK_TEST_APPARMOR_LOADED:-/sys/kernel/security/apparmor/profiles}"
  mapfile -t UNS < <(grep -lE '^[[:space:]]*(audit[[:space:]]+)?(allow[[:space:]]+)?userns' "$AA_DIR"/* 2>/dev/null | grep -vE '/(agent-bwrap|unprivileged_userns)$' || true)
  for f in "${UNS[@]}"; do sudo apparmor_parser -R "$f" >/dev/null 2>&1 || true; done
  # Checked now, while sudo still works (the list of loaded profiles is root-only); reported by the self-test.
  UNS_NAMES=$( { [ "${#UNS[@]}" = 0 ] || awk '$1 == "profile" {print $2}' "${UNS[@]}"; } | sort -u)
  UNS_LEFT=$(sudo cat "$AA_LOADED" 2>/dev/null | awk '{print $1}' | grep -xF -f <(printf '%s\n' "$UNS_NAMES" | sed '/^$/d') || true)
fi
UPSTREAM=$(awk '$1=="nameserver" && $2 !~ /^127\./ && $2 ~ /^[0-9.]+$/ {print $2; exit}' "${AGENT_LOCK_TEST_RESOLV:-/run/systemd/resolve/resolv.conf}" 2>/dev/null || true)
[ -n "$UPSTREAM" ] || UPSTREAM=168.63.129.16
id dnsmasq >/dev/null 2>&1 || sudo useradd --system --no-create-home --shell /usr/sbin/nologin dnsmasq
id www-data >/dev/null 2>&1 || die "no www-data user for nginx"
DNS_UID=$(id -u dnsmasq); PROXY_UID=$(id -u www-data)

CONF=$(mktemp)
{
  echo "listen-address=127.0.0.1"; echo "bind-interfaces"; echo "port=53"; echo "no-resolv"; echo "no-poll"
  echo "user=dnsmasq"; echo "cache-size=1000"; echo "filter-AAAA"
  for d in "${NAMES[@]}"; do echo "server=/${d#.}/$UPSTREAM"; done
} > "$CONF"
sudo install -m 0644 "$CONF" /etc/agent-dnsmasq.conf
sudo systemctl stop systemd-resolved.service 2>/dev/null || true
sudo dnsmasq --conf-file=/etc/agent-dnsmasq.conf --pid-file=/run/agent-dnsmasq.pid
sudo rm -f /etc/resolv.conf
printf 'nameserver 127.0.0.1\noptions edns0\n' | sudo tee /etc/resolv.conf >/dev/null

MOD=$(ls /usr/lib/nginx/modules/ngx_stream_module.so 2>/dev/null || true)
[ -n "$MOD" ] || die "nginx stream module missing"
NG=$(mktemp)
{
  echo "load_module $MOD;"
  echo "user www-data; worker_processes 2; pid /run/agent-nginx.pid; error_log /var/log/agent-nginx.log info;"
  echo "events { worker_connections 1024; }"
  echo "stream {"
  echo "  resolver 127.0.0.1 ipv6=off valid=60s; resolver_timeout 10s;"
  echo "  map \$ssl_preread_server_name \$agent_upstream {"
  echo "    hostnames;"
  for d in "${NAMES[@]}"; do echo "    $d \$ssl_preread_server_name:443;"; done
  echo "    default 127.0.0.1:1;"
  echo "  }"
  echo "  server { listen 127.0.0.1:8443; ssl_preread on; proxy_connect_timeout 15s; proxy_pass \$agent_upstream; }"
  echo "}"
} > "$NG"
sudo install -m 0644 "$NG" /etc/nginx/agent-egress.conf
sudo install -m 0644 /dev/null /var/log/agent-nginx.log
sudo systemctl stop nginx.service 2>/dev/null || true
sudo nginx -t -c /etc/nginx/agent-egress.conf >/dev/null 2>&1 || { sudo nginx -t -c /etc/nginx/agent-egress.conf || true; die "nginx config invalid"; }
sudo nginx -c /etc/nginx/agent-egress.conf

# --- 3. Firewall -----------------------------------------------------------------------------------------------------------
# NAT: every new TCP/443 connection, except the proxy's own, goes to the SNI proxy.
sudo iptables -t nat -F OUTPUT
sudo iptables -t nat -A OUTPUT -p tcp --dport 443 ! -d 127.0.0.0/8 -m owner ! --uid-owner "$PROXY_UID" -j REDIRECT --to-ports 8443
# Filter: loopback, replies, DNS only from dnsmasq to the upstream, 443 only from the proxy, Azure host services for root.
sudo iptables -F OUTPUT
sudo iptables -A OUTPUT -o lo -j ACCEPT
sudo iptables -A OUTPUT -d 127.0.0.0/8 -j ACCEPT   # connections redirected to the local proxy keep their outer interface
sudo iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
for p in udp tcp; do sudo iptables -A OUTPUT -p "$p" --dport 53 -d "$UPSTREAM" -m owner --uid-owner "$DNS_UID" -j ACCEPT; done
sudo iptables -A OUTPUT -p tcp --dport 443 -m owner --uid-owner "$PROXY_UID" -j ACCEPT
sudo iptables -A OUTPUT -d 168.63.129.16 -m owner --uid-owner 0 -j ACCEPT
sudo iptables -A OUTPUT -d 169.254.169.254 -m owner --uid-owner 0 -j ACCEPT
sudo iptables -A OUTPUT -j REJECT
sudo iptables -P OUTPUT DROP
sudo ip6tables -F OUTPUT
sudo ip6tables -A OUTPUT -o lo -j ACCEPT
sudo ip6tables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
sudo ip6tables -A OUTPUT -j REJECT
sudo ip6tables -P OUTPUT DROP

# --- 4. Nothing later in the job may undo this: stop Docker, remove sudo ---------------------------------------------------
sudo systemctl stop docker.socket docker.service containerd.service 2>/dev/null || true
sudo rm -f /var/run/docker.sock /run/containerd/containerd.sock
sudo gpasswd -d "$USER" sudo >/dev/null 2>&1 || true
sudo gpasswd -d "$USER" docker >/dev/null 2>&1 || true
# Who sudo could match: this user, ALL, and every group the job's processes still carry (they keep their start-up groups).
WHO="$USER|ALL"; for g in $(id -Gn); do [[ "$g" =~ ^[A-Za-z0-9_.-]+$ ]] && WHO+="|%$g"; done
sudo sed -i -E "/^[[:space:]]*($WHO)[[:space:]]/d" /etc/sudoers
# Last sudo call: delete every sudoers.d file that grants any of them anything.
sudo sh -c 'grep -lE "^[[:space:]]*($1)[[:space:]]" /etc/sudoers.d/* 2>/dev/null | xargs -r rm -f' sh "$WHO"
sudo -k || true

# --- 5. Prove it (each failure names the check; see docs/runbooks/agent-network-lock.md) ----------------------------
fail=0; bad() { echo "::error::agent egress lock self-test: $*"; fail=1; }
blocked() { ! curl -sS -o /dev/null --max-time 8 "$@" 2>/dev/null; }
if sudo -n true 2>/dev/null; then bad "sudo still works"; fi
if sudo -n -l >/dev/null 2>&1; then bad "sudo still lists rules for this user (a command-limited rule is left)"; fi
DOCKER_SOCK="${AGENT_LOCK_TEST_DOCKER_SOCK:-/var/run/docker.sock}"   # tests point these AGENT_LOCK_* hooks at temp paths
if [ -S "$DOCKER_SOCK" ] || docker info >/dev/null 2>&1; then bad "Docker still reachable"; fi
# The job's processes keep the groups they started with (docker, adm, ...): no socket those groups can write may remain.
RUN_DIRS="${AGENT_LOCK_TEST_RUN_DIRS:-/run /var/run}"
GROUP_SOCKS=""
for g in ${AGENT_LOCK_ADMIN_GROUPS:-docker lxd containerd}; do
  grep -q "^$g:" /etc/group || continue
  # shellcheck disable=SC2086
  GROUP_SOCKS+=$(find $RUN_DIRS -maxdepth 3 -type s -group "$g" -writable 2>/dev/null | head -3 || true)
done
[ -z "$GROUP_SOCKS" ] || bad "group-writable admin socket still there: $GROUP_SOCKS"
curl -fsS -o /dev/null --max-time 20 https://api.github.com/zen || bad "allowed host api.github.com not reachable"
blocked https://example.com || bad "blocked host example.com reachable"
blocked https://gist.github.com || bad "gist.github.com reachable"
blocked https://uploads.github.com || bad "uploads.github.com reachable"
NPM_IP=$(getent ahostsv4 registry.npmjs.org 2>/dev/null | awk 'NR==1{print $1}' || true)
[ -n "$NPM_IP" ] || bad "DNS for an allowed name does not resolve"
blocked --resolve "example.com:443:$NPM_IP" https://example.com || bad "allowed IP reachable under another name (SNI)"
blocked -k "https://$NPM_IP" || bad "raw IP without a name reachable"
blocked http://registry.npmjs.org || bad "plain HTTP (port 80) reachable"
if getent hosts example.com >/dev/null; then bad "DNS for a blocked name resolves"; fi
if timeout 8 bash -c 'exec 3<>/dev/tcp/8.8.8.8/53' 2>/dev/null; then bad "outside DNS server reachable"; fi
blocked -6 'https://[2606:4700:4700::1111]' || bad "IPv6 reachable"
bwrap --unshare-pid --ro-bind / / true 2>/dev/null || bad "bubblewrap cannot start (subprocess isolation would fail)"
[ -z "${UNS_LEFT:-}" ] || bad "AppArmor profiles that allow user namespaces are still loaded: $(echo $UNS_LEFT)"
if [ -f "$USERNS" ] && unshare -U true 2>/dev/null; then bad "a program outside bubblewrap can create user namespaces"; fi
if [ -f "$USERNS" ] && command -v podman >/dev/null && podman unshare true >/dev/null 2>&1; then
  bad "podman can still create user namespaces"
fi
if [ -f "$USERNS" ] && bwrap --unshare-user --ro-bind / / unshare -U true 2>/dev/null; then
  bad "a program started by bubblewrap can create user namespaces"
fi
if [ -f "$USERNS" ] && [ "$(cat "$USERNS")" != 1 ]; then
  bad "unprivileged user namespaces are not restricted"
fi
# Domain fronting: each exact allowed name, asked for another site in the HTTP Host header, must not answer with content
# (2xx) or send us to another host (3xx).
for d in "${NAMES[@]}"; do
  read -r code loc < <(curl -sS -o /dev/null --max-time 10 -w '%{http_code} %{redirect_url}\n' -H 'Host: example.com' "https://$d/" 2>/dev/null || echo "000")
  lh=$(sed -E 's#^https?://([^/:]+).*#\1#' <<<"${loc:-}")
  if [[ "${code:-000}" == 2* ]] || { [[ "${code:-000}" == 3* ]] && [ "$lh" != "$d" ]; }; then
    bad "domain fronting through $d answers for another host (HTTP ${code} ${loc:-})"
  fi
done
[ "${AGENT_LOCK_SELFTEST_BREAK:-}" != "1" ] || bad "deliberate break (AGENT_LOCK_SELFTEST_BREAK=1)"
if [ "$fail" != 0 ]; then
  echo "--- proxy log (last 20 lines) ---"; tail -n 20 /var/log/agent-nginx.log 2>/dev/null || true
  curl -sv -o /dev/null --max-time 15 https://api.github.com/zen 2>&1 | tail -n 15 || true
  die "self-test failed; see errors above"
fi
{ echo "claude-path=$BIN"; echo "bun-path=$BUN"; } >> "$GITHUB_OUTPUT"   # only now: a Claude step can find them only after the self-test passed
echo "::notice::Known open routes (an attacker with their own credentials could use them): github.com / api.github.com (pushes, issues, gists), registry.npmjs.org (publish), api.anthropic.com. See docs/runbooks/agent-network-lock.md."
echo "Agent egress lock on: ${#NAMES[@]} allowed names, SNI proxy, sudo and Docker removed."
