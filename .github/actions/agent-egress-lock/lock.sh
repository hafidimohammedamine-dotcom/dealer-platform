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

# --- Allowed names (founder-owned list; no extras from workflows) ---------------------------------------------------------
mapfile -t NAMES < <(sed -e 's/#.*//' -e 's/[[:space:]]//g' "$HERE/allow-domains.txt" | sed '/^$/d')
[ "${#NAMES[@]}" -gt 0 ] || die "empty allow-list"
for d in "${NAMES[@]}"; do
  [[ "$d" =~ ^\.?([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}$ ]] || die "not a plain host name: '$d'"
  [[ "$d" != .* ]] || [ "$(tr -cd . <<<"$d" | wc -c)" -ge 3 ] || die "suffix entry too broad (needs 3+ labels): '$d'"
done

# --- 1. Install the pinned Claude Code binary, checked against its pinned sha256 (from Anthropic's release manifest) ------
BIN="$HOME/.local/bin/claude"
mkdir -p "$HOME/.local/bin"
curl -fsSL --retry 3 -o /tmp/claude.bin "https://downloads.claude.ai/claude-code-releases/$CLAUDE_CODE_VERSION/linux-x64/claude"
echo "$CLAUDE_CODE_SHA256  /tmp/claude.bin" | sha256sum --check --quiet || die "Claude Code download does not match its pinned sha256"
install -m 0755 /tmp/claude.bin "$BIN" && rm -f /tmp/claude.bin
"$BIN" --version | grep -q "^$CLAUDE_CODE_VERSION " || die "Claude Code $CLAUDE_CODE_VERSION not installed"
echo "claude-path=$BIN" >> "$GITHUB_OUTPUT"
{ echo "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1"; echo "DISABLE_AUTOUPDATER=1"; } >> "$GITHUB_ENV"

# --- 2. DNS allow-list (dnsmasq) and SNI proxy (nginx stream) ------------------------------------------------------------
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends dnsmasq-base nginx libnginx-mod-stream >/dev/null 2>&1 || {
  sudo apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends dnsmasq-base nginx libnginx-mod-stream >/dev/null; }
UPSTREAM=$(awk '$1=="nameserver" && $2 !~ /^127\./ && $2 ~ /^[0-9.]+$/ {print $2; exit}' /run/systemd/resolve/resolv.conf 2>/dev/null || true)
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
  echo "user www-data; worker_processes 2; pid /run/agent-nginx.pid; error_log /var/log/agent-nginx.log warn;"
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
sudo systemctl stop nginx.service 2>/dev/null || true
sudo nginx -t -c /etc/nginx/agent-egress.conf >/dev/null 2>&1 || { sudo nginx -t -c /etc/nginx/agent-egress.conf; die "nginx config invalid"; }
sudo nginx -c /etc/nginx/agent-egress.conf

# --- 3. Firewall -----------------------------------------------------------------------------------------------------------
# NAT: every new TCP/443 connection, except the proxy's own, goes to the SNI proxy.
sudo iptables -t nat -F OUTPUT
sudo iptables -t nat -A OUTPUT -p tcp --dport 443 ! -d 127.0.0.0/8 -m owner ! --uid-owner "$PROXY_UID" -j REDIRECT --to-ports 8443
# Filter: loopback, replies, DNS only from dnsmasq to the upstream, 443 only from the proxy, Azure host services for root.
sudo iptables -F OUTPUT
sudo iptables -A OUTPUT -o lo -j ACCEPT
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
sudo sed -i -E "/^[[:space:]]*$USER[[:space:]]/d" /etc/sudoers
# Last sudo call: delete every sudoers.d file that grants this user (or everyone) anything.
sudo sh -c 'grep -lE "^[[:space:]]*($1|%$1|ALL)[[:space:]]" /etc/sudoers.d/* 2>/dev/null | xargs -r rm -f' sh "$USER"
sudo -k || true

# --- 5. Prove it (each failure names the check; see docs/runbooks/ci-guards.md "Agent network lock") ----------------------
fail=0; bad() { echo "::error::agent egress lock self-test: $*"; fail=1; }
blocked() { ! curl -sS -o /dev/null --max-time 8 "$@" 2>/dev/null; }
if sudo -n true 2>/dev/null; then bad "sudo still works"; fi
if [ -S /var/run/docker.sock ] || docker info >/dev/null 2>&1; then bad "Docker still reachable"; fi
curl -fsS -o /dev/null --max-time 20 https://api.github.com/zen || bad "allowed host api.github.com not reachable"
blocked https://example.com || bad "blocked host example.com reachable"
blocked https://gist.github.com || bad "gist.github.com reachable"
blocked https://uploads.github.com || bad "uploads.github.com reachable"
NPM_IP=$(getent ahostsv4 registry.npmjs.org | awk 'NR==1{print $1}')
[ -n "$NPM_IP" ] || bad "DNS for an allowed name does not resolve"
blocked --resolve "example.com:443:$NPM_IP" https://example.com || bad "allowed IP reachable under another name (SNI)"
blocked -k "https://$NPM_IP" || bad "raw IP without a name reachable"
blocked http://registry.npmjs.org || bad "plain HTTP (port 80) reachable"
if getent hosts example.com >/dev/null; then bad "DNS for a blocked name resolves"; fi
if timeout 8 bash -c 'exec 3<>/dev/tcp/8.8.8.8/53' 2>/dev/null; then bad "outside DNS server reachable"; fi
blocked -6 'https://[2606:4700:4700::1111]' || bad "IPv6 reachable"
[ "${AGENT_LOCK_SELFTEST_BREAK:-}" != "1" ] || bad "deliberate break (AGENT_LOCK_SELFTEST_BREAK=1)"
[ "$fail" = 0 ] || die "self-test failed; see errors above"
echo "Agent egress lock on: ${#NAMES[@]} allowed names, SNI proxy, sudo and Docker removed."
