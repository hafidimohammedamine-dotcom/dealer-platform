#!/usr/bin/env bash
# Unit tests for .github/actions/agent-egress-lock/lock.sh with stubbed system commands (no root, no network).
# Covers every `die` branch and every self-test check; the real-runner proof is .github/workflows/egress-lock-test.yml.
set -uo pipefail
COVENV=(); [ -n "${COV_TRACE:-}" ] && COVENV=(COV_TRACE="$COV_TRACE" BASH_ENV="$BASH_ENV")   # scripts/check-coverage.sh
REPO="$(cd "$(dirname "$0")/.." && pwd)"
LOCK_DIR="$REPO/.github/actions/agent-egress-lock"
TMPROOT="${TMPDIR:-/tmp}"
pass=0; failed=0
GOOD_VER=2.1.295
stub() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$S/$1"; chmod +x "$S/$1"; }
fresh() {
  T=$(mktemp -d "$TMPROOT/el.XXXXXX") || exit 2; S="$T/stubs"; mkdir -p "$S" "$T/home" "$T/action" "$T/run"
  cp "$LOCK_DIR/lock.sh" "$LOCK_DIR/allow-domains.txt" "$T/action/"
  : > "$T/out"; : > "$T/env"
  # A fake Claude binary and its sha256.
  printf '#!/usr/bin/env bash\necho "%s (Claude Code)"\n' "$GOOD_VER" > "$T/fake-claude"
  SHA=$(sha256sum "$T/fake-claude" | cut -d' ' -f1)
  stub uname 'case "$1" in -s) echo "${STUB_OS:-Linux}";; -m) echo "${STUB_ARCH:-x86_64}";; esac'
  # sudo logs every call (one line each) so tests can check what the lock configured; STUB_SUDO_FAIL fails matching calls.
  stub sudo 'printf "%s\n" "$*" >> "$STUB_SUDO_LOG"; [ "$*" = "-n true" ] && exit "${STUB_SUDO_RC:-1}"; [ "$1" = -k ] && exit 0
case "$*" in *"${STUB_SUDO_FAIL:-@none@}"*) exit 1;; esac; exit 0'
  stub bwrap 'exit "${STUB_BWRAP_RC:-0}"'
  echo 1 > "$T/userns"; printf 'nameserver 127.0.0.53\nnameserver 10.1.2.3\n' > "$T/resolv.conf"
  stub docker 'exit "${STUB_DOCKER_RC:-1}"'
  stub id 'case "$*" in "-u dnsmasq") echo 999;; "-u www-data") echo 33;; *) [ "${STUB_NO_WWW:-}" = 1 ] && [ "$1" = www-data ] && exit 1
  [ "${STUB_NO_DNSMASQ:-}" = 1 ] && [ "$1" = dnsmasq ] && exit 1; exit 0;; esac'
  stub ls '[ "${STUB_NO_MODULE:-}" = 1 ] && exit 2; echo /usr/lib/nginx/modules/ngx_stream_module.so'
  stub getent 'case "$1 $2" in "ahostsv4 registry.npmjs.org") [ "${STUB_NO_NPM_DNS:-}" = 1 ] && exit 2; echo "1.2.3.4 STREAM registry.npmjs.org";; "hosts example.com") exit "${STUB_DNS_LEAK_RC:-2}";; *) exit 2;; esac'
  stub timeout 'exit "${STUB_TCP_RC:-1}"'
  cat > "$S/curl" <<'EOF'
#!/usr/bin/env bash
out=""; url=""; prev=""
for a in "$@"; do [ "$prev" = -o ] && out=$a; case "$a" in http*) url=$a;; esac; prev=$a; done
case "$url" in
  https://downloads.claude.ai/*) cp "$STUB_BINARY" "$out"; exit 0;;
  https://api.github.com/zen) exit "${STUB_ALLOWED_RC:-0}";;
  https://registry.npmjs.org/) [ "${STUB_FRONTING:-}" = 1 ] && case " $* " in *"Host: example.com"*) echo "<h1>Example Domain</h1>"; exit 0;; esac;;
esac
for r in ${STUB_REACHABLE:-}; do case " $* " in *"$r"*) exit 0;; esac; done
exit 7
EOF
  chmod +x "$S/curl"
}
invoke() { # invoke [VAR=value ...]: runs the copied lock.sh with a clean environment of stubs; sets out and rc
  out=$(cd "$T" && env -i "${COVENV[@]}" PATH="$S:/usr/bin:/bin" HOME="$T/home" USER=runner GITHUB_OUTPUT="$T/out" GITHUB_ENV="$T/env" \
        CLAUDE_CODE_VERSION="$GOOD_VER" CLAUDE_CODE_SHA256="$SHA" STUB_BINARY="$T/fake-claude" TMPDIR="$T" \
        AGENT_LOCK_TEST_DOCKER_SOCK="$T/no-docker.sock" AGENT_LOCK_TEST_RUN_DIRS="$T/run" \
        AGENT_LOCK_TEST_USERNS="$T/userns" AGENT_LOCK_TEST_RESOLV="$T/resolv.conf" STUB_SUDO_LOG="$T/sudo.log" "$@" \
        bash "$T/action/lock.sh" 2>&1); rc=$?; }
run() { # run <ok|fail> <name> <message> [VAR=value ...]
  local want=$1 name=$2 msg=$3; shift 3
  invoke "$@"
  got=$([ $rc = 0 ] && echo ok || echo fail)
  if [ "$got" = "$want" ] && grep -qF -- "$msg" <<<"$out"; then pass=$((pass+1)); echo "PASS  $name"
  else failed=$((failed+1)); echo "FAIL  $name ($got)"; echo "$out" | tail -n 8; fi
  [ "${KEEP:-}" = 1 ] || rm -rf "$T"; }
check() { # check <name> <condition...>: passes when the command succeeds
  local name=$1; shift
  if "$@"; then pass=$((pass+1)); echo "PASS  $name"; else failed=$((failed+1)); echo "FAIL  $name"; fi; }

fresh; run ok   "all stubs healthy: lock on" "Agent egress lock on:"
fresh; KEEP=1 run ok "lock on (kept for checks)" "Agent egress lock on:"
check "claude-path output written" grep -qx "claude-path=$T/home/.local/bin/claude" "$T/out"
check "nonessential traffic and autoupdater off" grep -qx "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1" "$T/env"
check "claude-path is the last output line" bash -c '[ "$(tail -n1 "$1")" = "claude-path=$2/home/.local/bin/claude" ]' _ "$T/out" "$T"
L="$T/sudo.log"
conf_of() { awk -v d="$1" '$1=="install" && $NF==d {print $(NF-1)}' "$L" | tail -n1; }
DC=$(conf_of /etc/agent-dnsmasq.conf); NC=$(conf_of /etc/nginx/agent-egress.conf)
check "dnsmasq: listens on 127.0.0.1 only, no outside resolv" bash -c 'grep -qx listen-address=127.0.0.1 "$1" && grep -qx bind-interfaces "$1" && grep -qx no-resolv "$1" && grep -qx filter-AAAA "$1"' _ "$DC"
check "dnsmasq: one server line per allowed name, upstream from resolv.conf" bash -c 'grep -qx "server=/api.anthropic.com/10.1.2.3" "$1" && grep -qx "server=/actions.githubusercontent.com/10.1.2.3" "$1" && [ "$(grep -c "^server=" "$1")" = "$(sed -e "s/#.*//" -e "/^[[:space:]]*$/d" "$2" | wc -l)" ]' _ "$DC" "$LOCK_DIR/allow-domains.txt"
check "dnsmasq: no wildcard or catch-all server" bash -c '! grep -E "^server=(/|[0-9])" "$1" | grep -qvE "^server=/[a-z0-9.-]+/" ' _ "$DC"
check "nginx: SNI map with hostnames, unknown names go nowhere" bash -c 'grep -q "hostnames;" "$1" && grep -q "default 127.0.0.1:1;" "$1" && grep -q "ssl_preread on;" "$1" && grep -q "listen 127.0.0.1:8443;" "$1" && grep -q "user www-data;" "$1"' _ "$NC"
check "nginx: suffix entry kept as a suffix" grep -q '    .actions.githubusercontent.com \$ssl_preread_server_name:443;' "$NC"
check "iptables: 443 redirected for everyone but the proxy" grep -qx -- "iptables -t nat -A OUTPUT -p tcp --dport 443 ! -d 127.0.0.0/8 -m owner ! --uid-owner 33 -j REDIRECT --to-ports 8443" "$L"
check "iptables: DNS only from dnsmasq to the upstream" bash -c 'grep -qx -- "iptables -A OUTPUT -p udp --dport 53 -d 10.1.2.3 -m owner --uid-owner 999 -j ACCEPT" "$1" && grep -qx -- "iptables -A OUTPUT -p tcp --dport 53 -d 10.1.2.3 -m owner --uid-owner 999 -j ACCEPT" "$1"' _ "$L"
check "iptables: reject then default drop (IPv4 and IPv6)" bash -c 'grep -qx -- "iptables -A OUTPUT -j REJECT" "$1" && grep -qx -- "iptables -P OUTPUT DROP" "$1" && grep -qx -- "ip6tables -A OUTPUT -j REJECT" "$1" && grep -qx -- "ip6tables -P OUTPUT DROP" "$1"' _ "$L"
check "iptables: nothing else accepted on the open internet" bash -c '[ "$(grep -c -- "^iptables -A OUTPUT .*-j ACCEPT" "$1")" = 8 ]' _ "$L"
check "AppArmor: restriction kept on, only bwrap allowed" bash -c 'grep -qx -- "sysctl -q -w kernel.apparmor_restrict_unprivileged_userns=1" "$1" && grep -qx -- "apparmor_parser -r /etc/apparmor.d/agent-bwrap" "$1" && ! grep -q "userns=0" "$1"' _ "$L"
check "sudo removed: group, sudoers lines and sudoers.d files" bash -c 'grep -qx -- "gpasswd -d runner sudo" "$1" && grep -qx -- "gpasswd -d runner docker" "$1" && grep -q "^sed -i -E /\^\[\[:space:\]\]\*runner\[\[:space:\]\]/d /etc/sudoers$" "$1" && grep -q "^sh -c grep -lE .* sh runner$" "$1"' _ "$L"
check "sudoers.d cleanup is the last real sudo call" bash -c 'tail -n 3 "$1" > "$1.tail"; sed -n 1p "$1.tail" | grep -q "^sh -c grep -lE" && sed -n 2p "$1.tail" | grep -qx -- "-k" && sed -n 3p "$1.tail" | grep -qx -- "-n true"' _ "$L"
check "Docker stopped and its sockets removed" grep -qx -- "rm -f /var/run/docker.sock /run/containerd/containerd.sock" "$L"
rm -rf "$T"
fresh; printf 'nameserver 127.0.0.53\n' > "$T/resolv.conf"; KEEP=1 run ok "no outside resolver: Azure DNS fallback" "Agent egress lock on:"
check "fallback upstream 168.63.129.16 used" grep -q "^server=/api.anthropic.com/168.63.129.16$" "$(awk '$1=="install" && $NF=="/etc/agent-dnsmasq.conf" {print $(NF-1)}' "$T/sudo.log")"; rm -rf "$T"
fresh; KEEP=1 run ok "no dnsmasq user: one is created" "Agent egress lock on:" STUB_NO_DNSMASQ=1
check "useradd called for dnsmasq" grep -qx -- "useradd --system --no-create-home --shell /usr/sbin/nologin dnsmasq" "$T/sudo.log"; rm -rf "$T"
fresh; KEEP=1 run ok "dnsmasq user exists: none created" "Agent egress lock on:"
check "useradd not called" bash -c '! grep -q useradd "$1"' _ "$T/sudo.log"; rm -rf "$T"
fresh; rm -f "$T/userns"; KEEP=1 run ok "no AppArmor userns switch: nothing to set" "Agent egress lock on:"
check "no sysctl or AppArmor profile without the switch" bash -c '! grep -qE "sysctl|apparmor_parser" "$1"' _ "$T/sudo.log"; rm -rf "$T"
fresh; stub sudo 'printf "%s\n" "$*" >> "$STUB_SUDO_LOG"; [ "$*" = "-n true" ] && exit 1; [ "$1" = -k ] && exit 0
case "$*" in *"apt-get install"*) [ -f "$STUB_SUDO_LOG.updated" ] && exit 0; exit 1;; *"apt-get update"*) touch "$STUB_SUDO_LOG.updated";; esac; exit 0'
KEEP=1 run ok "apt install retried after apt-get update" "Agent egress lock on:"
check "apt-get update ran once, install twice" bash -c '[ "$(grep -c "apt-get update" "$1")" = 1 ] && [ "$(grep -c "apt-get install" "$1")" = 2 ]' _ "$T/sudo.log"; rm -rf "$T"
fresh; KEEP=1 run ok "apt install works first time: no update" "Agent egress lock on:"
check "apt-get update not run" bash -c '! grep -q "apt-get update" "$1"' _ "$T/sudo.log"; rm -rf "$T"
fresh; run fail "packages cannot be installed" "could not install dnsmasq-base nginx libnginx-mod-stream bubblewrap socat" STUB_SUDO_FAIL="apt-get"
fresh; run fail "AppArmor profile does not load" "could not load the AppArmor profile for bubblewrap" STUB_SUDO_FAIL="apparmor_parser"
# die branches
fresh; run fail "non-Linux runner"          "Linux x64 runners only" STUB_OS=Darwin
fresh; run fail "non-x64 runner"            "Linux x64 runners only" STUB_ARCH=aarch64
fresh; run fail "outside GitHub Actions"    "must run inside GitHub Actions" GITHUB_OUTPUT= GITHUB_ENV=
fresh; run fail "bad version"               "bad CLAUDE_CODE_VERSION" CLAUDE_CODE_VERSION='2.1.295; curl evil'
fresh; run fail "bad sha256"                "bad CLAUDE_CODE_SHA256" CLAUDE_CODE_SHA256=abc
fresh; : > "$T/action/allow-domains.txt"; run fail "empty allow-list" "empty allow-list"
fresh; printf 'github.com\nevil.com/x\n' > "$T/action/allow-domains.txt"; run fail "not a plain host name" "not a plain host name: 'evil.com/x'"
fresh; printf 'github.com\n$(curl evil)\n' > "$T/action/allow-domains.txt"; run fail "injected text in the allow-list" "not a plain host name"
fresh; printf '.windows.net\n' > "$T/action/allow-domains.txt"; run fail "suffix entry not approved" "suffix entry not approved: '.windows.net'"
fresh; printf '.core.windows.net\n' > "$T/action/allow-domains.txt"; run fail "long suffix still not approved" "suffix entry not approved: '.core.windows.net'"
fresh; run fail "download does not match the pinned sha256" "does not match its pinned sha256" CLAUDE_CODE_SHA256=$(printf '%064d' 0)
fresh; printf '#!/usr/bin/env bash\necho "9.9.9 (Claude Code)"\n' > "$T/fake-claude"; SHA=$(sha256sum "$T/fake-claude" | cut -d' ' -f1); run fail "binary reports another version" "Claude Code 2.1.295 not installed"
fresh; run fail "no www-data user"          "no www-data user for nginx" STUB_NO_WWW=1
fresh; run fail "nginx stream module missing" "nginx stream module missing" STUB_NO_MODULE=1
fresh; stub sudo '[ "$*" = "-n true" ] && exit 1; [ "$1" = -k ] && exit 0; case "$*" in *"nginx -t"*) exit 1;; esac; exit 0'; run fail "nginx config invalid" "nginx config invalid"
# self-test checks
fresh; run fail "sudo still works"          "self-test: sudo still works" STUB_SUDO_RC=0
fresh; run fail "Docker still reachable"    "self-test: Docker still reachable" STUB_DOCKER_RC=0
fresh; python3 -c 'import socket,sys; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1])' "$T/sock"; run fail "Docker socket still there" "self-test: Docker still reachable" AGENT_LOCK_TEST_DOCKER_SOCK="$T/sock"
fresh; run fail "allowed host unreachable"  "self-test: allowed host api.github.com not reachable" STUB_ALLOWED_RC=7
fresh; run fail "blocked host reachable"    "self-test: blocked host example.com reachable" STUB_REACHABLE=https://example.com
fresh; run fail "gist reachable"            "self-test: gist.github.com reachable" STUB_REACHABLE=https://gist.github.com
fresh; run fail "uploads reachable"         "self-test: uploads.github.com reachable" STUB_REACHABLE=https://uploads.github.com
fresh; run fail "allowed IP under another name" "self-test: allowed IP reachable under another name (SNI)" STUB_REACHABLE=example.com:443:1.2.3.4
fresh; run fail "raw IP reachable"          "self-test: raw IP without a name reachable" STUB_REACHABLE=https://1.2.3.4
fresh; run fail "plain HTTP reachable"      "self-test: plain HTTP (port 80) reachable" STUB_REACHABLE=http://registry.npmjs.org
fresh; run fail "allowed name does not resolve" "self-test: DNS for an allowed name does not resolve" STUB_NO_NPM_DNS=1
fresh; run fail "blocked name resolves"     "self-test: DNS for a blocked name resolves" STUB_DNS_LEAK_RC=0
fresh; run fail "outside DNS reachable"     "self-test: outside DNS server reachable" STUB_TCP_RC=0
fresh; G=$(id -gn); python3 -c 'import socket,sys; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1])' "$T/run/admin.sock"; chmod 660 "$T/run/admin.sock"; run fail "group-writable admin socket still there" "group-writable admin socket still there" AGENT_LOCK_ADMIN_GROUPS="$G"
fresh; run ok "known open routes are printed" "Known open routes"
fresh; run fail "IPv6 reachable"            "self-test: IPv6 reachable" "STUB_REACHABLE=-6"
fresh; run fail "deliberate break"          "self-test: deliberate break" AGENT_LOCK_SELFTEST_BREAK=1
fresh; run fail "a failed self-test stops the job" "self-test failed; see errors above" STUB_SUDO_RC=0
fresh; run fail "bubblewrap cannot start"   "self-test: bubblewrap cannot start" STUB_BWRAP_RC=1
fresh; echo 0 > "$T/userns"; run fail "user namespaces left unrestricted" "self-test: unprivileged user namespaces are not restricted"
fresh; run fail "domain fronting reaches another site" "self-test: domain fronting through registry.npmjs.org reaches example.com" STUB_FRONTING=1
fresh; KEEP=1 run fail "failed self-test (kept for checks)" "self-test failed" STUB_SUDO_RC=0
check "no claude-path output when the self-test fails" bash -c '! grep -q "^claude-path=" "$1"' _ "$T/out"; rm -rf "$T"
echo "$pass passed, $failed failed"
[ "$failed" = 0 ]
