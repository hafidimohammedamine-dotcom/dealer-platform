#!/usr/bin/env bash
# Agent egress lock (founder-owned). See action.yml. Runs on GitHub-hosted Ubuntu runners as the `runner` user with sudo.
# Order matters: everything that needs sudo or the open internet happens first; sudo is removed last.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
die() { echo "::error::agent egress lock: $*"; exit 1; }
[ "$(uname -s)" = Linux ] || die "Linux runners only"
[ -n "${GITHUB_OUTPUT:-}" ] && [ -n "${GITHUB_ENV:-}" ] || die "must run inside GitHub Actions"
[[ "${CLAUDE_CODE_VERSION:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "bad CLAUDE_CODE_VERSION"

# --- Allowed domains: the founder-owned list plus validated extras -------------------------------------------------------
mapfile -t DOMAINS < <(sed -e 's/#.*//' -e 's/[[:space:]]//g' "$HERE/allow-domains.txt" | sed '/^$/d')
for d in ${EXTRA_DOMAINS:-}; do DOMAINS+=("$d"); done
for d in "${DOMAINS[@]}"; do
  [[ "$d" =~ ^([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}$ ]] || die "not a plain domain name: '$d'"
done
[ "${#DOMAINS[@]}" -gt 0 ] || die "empty allow-list"

# --- 1. Pre-install the pinned Claude Code (the action would otherwise download it later, after the lock) -----------------
curl -fsSL --retry 3 https://claude.ai/install.sh -o /tmp/claude-install.sh
bash /tmp/claude-install.sh "$CLAUDE_CODE_VERSION"
CLAUDE="$HOME/.local/bin/claude"
"$CLAUDE" --version | grep -q "^$CLAUDE_CODE_VERSION " || die "Claude Code $CLAUDE_CODE_VERSION not installed"
echo "claude-path=$CLAUDE" >> "$GITHUB_OUTPUT"
{ echo "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1"; echo "DISABLE_AUTOUPDATER=1"; } >> "$GITHUB_ENV"

# --- 2. DNS allow-list (dnsmasq) feeding an ipset, and a default-deny firewall ---------------------------------------------
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends dnsmasq-base ipset >/dev/null 2>&1 || {
  sudo apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends dnsmasq-base ipset >/dev/null; }
UPSTREAM=$(awk '$1=="nameserver" && $2 !~ /^127\./ && $2 ~ /^[0-9.]+$/ {print $2; exit}' /run/systemd/resolve/resolv.conf 2>/dev/null || true)
[ -n "$UPSTREAM" ] || UPSTREAM=168.63.129.16
id dnsmasq >/dev/null 2>&1 || sudo useradd --system --no-create-home --shell /usr/sbin/nologin dnsmasq
DNS_UID=$(id -u dnsmasq)

sudo ipset create agent-allow4 hash:ip -exist
CONF=$(mktemp)
{
  echo "listen-address=127.0.0.1"; echo "bind-interfaces"; echo "port=53"; echo "no-resolv"; echo "no-poll"
  echo "user=dnsmasq"; echo "cache-size=1000"; echo "filter-AAAA"
  for d in "${DOMAINS[@]}"; do echo "server=/$d/$UPSTREAM"; done
  printf 'ipset='; printf '/%s' "${DOMAINS[@]}"; echo "/agent-allow4"
} > "$CONF"
sudo install -m 0644 "$CONF" /etc/agent-dnsmasq.conf
sudo systemctl stop systemd-resolved.service 2>/dev/null || true
sudo dnsmasq --conf-file=/etc/agent-dnsmasq.conf --pid-file=/run/agent-dnsmasq.pid
sudo rm -f /etc/resolv.conf
printf 'nameserver 127.0.0.1\noptions edns0\n' | sudo tee /etc/resolv.conf >/dev/null

# IPv4: loopback, replies on open connections, DNS only from dnsmasq to the upstream, web only to allow-listed IPs,
# the Azure host agent and metadata service for root only. Everything else is rejected.
sudo iptables -F OUTPUT
sudo iptables -A OUTPUT -o lo -j ACCEPT
sudo iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
for p in udp tcp; do sudo iptables -A OUTPUT -p "$p" --dport 53 -d "$UPSTREAM" -m owner --uid-owner "$DNS_UID" -j ACCEPT; done
sudo iptables -A OUTPUT -p tcp -m multiport --dports 80,443 -m set --match-set agent-allow4 dst -j ACCEPT
sudo iptables -A OUTPUT -d 168.63.129.16 -m owner --uid-owner 0 -j ACCEPT
sudo iptables -A OUTPUT -d 169.254.169.254 -m owner --uid-owner 0 -j ACCEPT
sudo iptables -A OUTPUT -j REJECT
sudo iptables -P OUTPUT DROP
# IPv6: nothing leaves except loopback and replies.
sudo ip6tables -F OUTPUT
sudo ip6tables -A OUTPUT -o lo -j ACCEPT
sudo ip6tables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
sudo ip6tables -A OUTPUT -j REJECT
sudo ip6tables -P OUTPUT DROP

# --- 3. Nothing later in the job may undo this: stop Docker, remove sudo ---------------------------------------------------
sudo systemctl stop docker.socket docker.service containerd.service 2>/dev/null || true
sudo rm -f /var/run/docker.sock /run/containerd/containerd.sock
sudo gpasswd -d "$USER" sudo >/dev/null 2>&1 || true
sudo gpasswd -d "$USER" docker >/dev/null 2>&1 || true
sudo sed -i -E "/^[[:space:]]*$USER[[:space:]]/d" /etc/sudoers
# Last sudo call: delete every sudoers.d file that grants this user (or everyone) anything.
sudo sh -c 'grep -lE "^[[:space:]]*($1|%$1|ALL)[[:space:]]" /etc/sudoers.d/* 2>/dev/null | xargs -r rm -f' sh "$USER"
sudo -k || true

# --- 4. Prove it ---------------------------------------------------------------------------------------------------------
fail=0; bad() { echo "::error::agent egress lock self-test: $*"; fail=1; }
if sudo -n true 2>/dev/null; then bad "sudo still works"; fi
if [ -S /var/run/docker.sock ] || docker info >/dev/null 2>&1; then bad "Docker still reachable"; fi
curl -fsS -o /dev/null --max-time 20 https://api.github.com/zen || bad "allowed host api.github.com not reachable"
if curl -sS -o /dev/null --max-time 8 https://example.com 2>/dev/null; then bad "blocked host example.com reachable"; fi
if getent hosts example.com >/dev/null; then bad "DNS for a blocked domain resolves"; fi
if curl -sS -o /dev/null --max-time 8 https://1.1.1.1 2>/dev/null; then bad "raw IP 1.1.1.1 reachable"; fi
if timeout 8 bash -c 'exec 3<>/dev/tcp/8.8.8.8/53' 2>/dev/null; then bad "outside DNS server reachable"; fi
if curl -6 -sS -o /dev/null --max-time 8 'https://[2606:4700:4700::1111]' 2>/dev/null; then bad "IPv6 reachable"; fi
[ "$fail" = 0 ] || die "self-test failed; see errors above"
echo "Agent egress lock on: ${#DOMAINS[@]} allowed domains, sudo and Docker removed."
