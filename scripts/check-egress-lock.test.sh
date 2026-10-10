#!/usr/bin/env bash
# Unit tests for .github/actions/agent-egress-lock/lock.sh with stubbed system commands (no root, no network).
# Covers every `die` branch and every self-test check; the real-runner proof is .github/workflows/egress-lock-test.yml.
set -uo pipefail
COVENV=(); [ -n "${COV_TRACE:-}" ] && COVENV=(COV_TRACE="$COV_TRACE" BASH_ENV="$BASH_ENV")   # scripts/check-coverage.sh
REPO="$(cd "$(dirname "$0")/.." && pwd)"
LOCK_DIR="$REPO/.github/actions/agent-egress-lock"
TMPROOT="${TMPDIR:-/tmp}"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-testlib.sh"
GOOD_VER=2.1.295
BUN_VER=1.3.14
stub() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$S/$1"; chmod +x "$S/$1"; }
fresh() {
  T=$(mktemp -d "$TMPROOT/el.XXXXXX") || exit 2; S="$T/stubs"; mkdir -p "$S" "$T/home" "$T/action" "$T/run"
  cp "$LOCK_DIR/lock.sh" "$LOCK_DIR/allow-domains.txt" "$LOCK_DIR/agent-bwrap.apparmor" "$T/action/"
  : > "$T/out"; : > "$T/env"
  # A fake Claude binary and its sha256.
  printf '#!/usr/bin/env bash\necho "%s (Claude Code)"\n' "$GOOD_VER" > "$T/fake-claude"
  SHA=$(sha256sum "$T/fake-claude" | cut -d' ' -f1)
  # A fake Bun release zip and its sha256.
  mkdir -p "$T/bunsrc/bun-linux-x64"; printf '#!/usr/bin/env bash\necho "%s"\n' "${FAKE_BUN_VER:-$BUN_VER}" > "$T/bunsrc/bun-linux-x64/bun"
  chmod +x "$T/bunsrc/bun-linux-x64/bun"; (cd "$T/bunsrc" && zip -q -r "$T/fake-bun.zip" bun-linux-x64)
  BUN_SHA=$(sha256sum "$T/fake-bun.zip" | cut -d' ' -f1)
  stub uname 'case "$1" in -s) echo "${STUB_OS:-Linux}";; -m) echo "${STUB_ARCH:-x86_64}";; esac'
  # sudo logs every call (one line each) so tests can check what the lock configured; STUB_SUDO_FAIL fails matching calls.
  stub sudo 'printf "%s\n" "$*" >> "$STUB_SUDO_LOG"; [ "$1" = tee ] && { cat >/dev/null; exit 0; }; [ "$*" = "-n true" ] && exit "${STUB_SUDO_RC:-1}"; [ "$*" = "-n -l" ] && exit "${STUB_SUDO_L_RC:-1}"; [ "$1" = -k ] && exit 0
case "$*" in *"${STUB_SUDO_FAIL:-@none@}"*) exit 1;; "cat "*) shift; exec cat "$@";; "chmod "*) [ "${STUB_CHMOD_NOOP:-}" = 1 ] && exit 0; shift; exec chmod "$@";; esac; exit 0'
  stub unshare 'exit "${STUB_UNSHARE_RC:-1}"'
  [ -z "${STUB_PODMAN:-}" ] || stub podman '[ "$2" = id ] && echo "${STUB_PODMAN_UID:-1001}"; exit "${STUB_PODMAN_RC:-1}"'
  mkdir -p "$T/setuid"; for f in newuidmap newgidmap; do : > "$T/setuid/$f"; chmod u+s,g+s "$T/setuid/$f"; done
  mkdir -p "$T/apparmor.d"; : > "$T/aa-loaded"
  stub bwrap 'case " $* " in *" unshare -U "*) exit "${STUB_CHILD_USERNS_RC:-1}";; esac; exit "${STUB_BWRAP_RC:-0}"'
  echo 1 > "$T/userns"; printf 'nameserver 127.0.0.53\nnameserver 10.1.2.3\n' > "$T/resolv.conf"
  stub docker 'exit "${STUB_DOCKER_RC:-1}"'
  stub systemctl 'echo "systemctl $*" >> "$STUB_CALLS_LOG"; exit "${STUB_SYSTEMCTL_RC:-1}"'; stub pkexec 'exit "${STUB_PKEXEC_RC:-1}"'
  stub systemd-run 'echo "systemd-run $*" >> "$STUB_CALLS_LOG"; case " $* " in *" -p User=root true "*) exit "${STUB_SYSTEMD_RUN_RC:-1}";; esac; exit 1'
  stub id 'case "$*" in "-Gn") echo "runner adm docker bad;group";; "-u dnsmasq") echo 999;; "-u www-data") echo 33;; *) [ "${STUB_NO_WWW:-}" = 1 ] && [ "$1" = www-data ] && exit 1
  [ "${STUB_NO_DNSMASQ:-}" = 1 ] && [ "$1" = dnsmasq ] && exit 1; exit 0;; esac'
  stub ls '[ "${STUB_NO_MODULE:-}" = 1 ] && exit 2; echo /usr/lib/nginx/modules/ngx_stream_module.so'
  stub getent 'case "$1 $2" in "ahostsv4 registry.npmjs.org") [ "${STUB_NO_NPM_DNS:-}" = 1 ] && exit 2; echo "${STUB_NPM_IP:-192.0.2.1} STREAM registry.npmjs.org";; "hosts example.com") exit "${STUB_DNS_LEAK_RC:-2}";; *) exit 2;; esac'
  stub timeout 'exit "${STUB_TCP_RC:-1}"'
  cat > "$S/curl" <<'EOF'
#!/usr/bin/env bash
[ -z "${STUB_CURL_LOG:-}" ] || echo "$*" >> "$STUB_CURL_LOG"
out=""; url=""; prev=""
for a in "$@"; do [ "$prev" = -o ] && out=$a; case "$a" in http*) url=$a;; esac; prev=$a; done
case "$url" in
  https://downloads.claude.ai/*) [ "${STUB_CLAUDE_DL_RC:-0}" = 0 ] || exit "$STUB_CLAUDE_DL_RC"; cp "$STUB_BINARY" "$out"; exit 0;;
  https://github.com/oven-sh/bun/releases/download/*) [ "${STUB_BUN_DL_RC:-0}" = 0 ] || exit "$STUB_BUN_DL_RC"; cp "$STUB_BUN_ZIP" "$out"; exit 0;;
  https://api.github.com/zen) exit "${STUB_ALLOWED_RC:-0}";;
esac
# Domain-fronting probe: STUB_FRONT="<host>=<code>[=<redirect url>] ..." answers for those hosts (whatever the Host header),
# STUB_UNREACHABLE="<host> ..." do not answer at all; every other allowed name answers 400 for a foreign Host header.
case " $* " in *"Host: "*)   # the self-test probes every allowed name with several foreign Host values
  for h in ${STUB_UNREACHABLE:-}; do [ "$url" = "https://$h/" ] && { echo "000 "; exit 7; }; done
  for f in ${STUB_FRONT:-}; do IFS== read -r h c l <<<"$f"; [ "$url" = "https://$h/" ] && { printf '%s' "${STUB_FRONT_BODY:-}" > "$out"; echo "$c ${l:-}"; exit 0; }; done
  echo "400 "; exit 0;; esac
for r in ${STUB_REACHABLE:-}; do case " $* " in *"$r"*) exit 0;; esac; done
exit 7
EOF
  chmod +x "$S/curl"
}
invoke() { # invoke [VAR=value ...]: runs the copied lock.sh with a clean environment of stubs; sets out and rc
  out=$(cd "$T" && env -i "${COVENV[@]}" PATH="$S:/usr/bin:/bin" HOME="$T/home" USER=runner GITHUB_OUTPUT="$T/out" GITHUB_ENV="$T/env" \
        CLAUDE_CODE_VERSION="$GOOD_VER" CLAUDE_CODE_SHA256="$SHA" STUB_BINARY="$T/fake-claude" TMPDIR="$T" \
        BUN_VERSION="$BUN_VER" BUN_SHA256="$BUN_SHA" STUB_BUN_ZIP="$T/fake-bun.zip" \
        AGENT_LOCK_TEST_DOCKER_SOCK="$T/no-docker.sock" AGENT_LOCK_TEST_RUN_DIRS="$T/run" \
        AGENT_LOCK_TEST_USERNS="$T/userns" AGENT_LOCK_TEST_RESOLV="$T/resolv.conf" STUB_SUDO_LOG="$T/sudo.log" STUB_CALLS_LOG="$T/calls.log" STUB_CURL_LOG="$T/curl.log" \
        AGENT_LOCK_TEST_APPARMOR_DIR="$T/apparmor.d" AGENT_LOCK_TEST_APPARMOR_LOADED="$T/aa-loaded" AGENT_LOCK_TEST_SETUID_DIR="$T/setuid" "$@" \
        bash "$T/action/lock.sh" 2>&1); rc=$?; }
run() { # run <ok|fail> <name> <message> [VAR=value ...]
  local want=$1 name=$2 msg=$3; shift 3
  invoke "$@"
  assert_result "$want" "$rc" "$name" "$msg" "$out"
  [ "${KEEP:-}" = 1 ] || rm -rf "$T"; }
conf_of() { # conf_of <sudo log> <destination>: the temp file the lock installed at <destination> (last install wins)
  awk -v d="$2" '$1=="install" && $NF==d {print $(NF-1)}' "$1" | tail -n1; }

fresh; run ok   "all stubs healthy: lock on" "Agent egress lock on:"
fresh; KEEP=1 run ok "lock on (kept for checks)" "Agent egress lock on:"
check "claude-path output written" grep -qx "claude-path=$T/home/.local/bin/claude" "$T/out"
check "nonessential traffic and autoupdater off" grep -qx "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1" "$T/env"
check "claude-path and bun-path are the last output lines" bash -c '[ "$(tail -n2 "$1")" = "claude-path=$2/home/.local/bin/claude
bun-path=$2/home/.local/bin/bun" ]' _ "$T/out" "$T"
L="$T/sudo.log"
DC=$(conf_of "$L" /etc/agent-dnsmasq.conf); NC=$(conf_of "$L" /etc/nginx/agent-egress.conf)
check "dnsmasq: listens on 127.0.0.1 only, no outside resolv" bash -c 'grep -qx listen-address=127.0.0.1 "$1" && grep -qx bind-interfaces "$1" && grep -qx no-resolv "$1" && grep -qx filter-AAAA "$1"' _ "$DC"
check "dnsmasq: one sink address line per allowed name and runner service plus the run-service suffix, no forwarding at all" bash -c 'grep -qx "address=/api.anthropic.com/192.0.2.1" "$1" && grep -qx "address=/github.com/192.0.2.1" "$1" && grep -qx "address=/broker.actions.githubusercontent.com/192.0.2.1" "$1" && grep -qx "address=/results-receiver.actions.githubusercontent.com/192.0.2.1" "$1" && grep -qx "address=/actions.githubusercontent.com/192.0.2.1" "$1" && [ "$(grep -c "^address=" "$1")" = "$(( $(sed -e "s/#.*//" -e "/^[[:space:]]*$/d" "$2" | wc -l) + 3 ))" ] && ! grep -qE "^(server|rev-server)=" "$1" && grep -qx "no-resolv" "$1" && grep -qx "no-hosts" "$1"' _ "$DC" "$LOCK_DIR/allow-domains.txt"
check "nginx resolves exact names itself, through the upstream resolver" grep -q "  resolver 10.1.2.3 ipv6=off" "$NC"
check "nginx: the run service only as its name pattern, never a bare suffix" bash -c 'grep -qF "    ~^run-actions-[0-9]+-azure-[a-z0-9]+\\.actions\\.githubusercontent\\.com\$ \$ssl_preread_server_name:443;" "$1" && ! grep -qE "^    \.?actions\.githubusercontent\.com " "$1" && grep -q "    broker.actions.githubusercontent.com \$ssl_preread_server_name:443;" "$1"' _ "$NC"
check "dnsmasq: no wildcard or catch-all server" bash -c '! grep -E "^server=(/|[0-9])" "$1" | grep -qvE "^server=/[a-z0-9.-]+/" ' _ "$DC"
check "nginx: SNI map with hostnames, unknown names go nowhere" bash -c 'grep -q "hostnames;" "$1" && grep -q "default 127.0.0.1:1;" "$1" && grep -q "ssl_preread on;" "$1" && grep -q "listen 127.0.0.1:8443;" "$1" && grep -q "user www-data;" "$1"' _ "$NC"
check "nginx: map hash buckets big enough for long generated names" grep -q "  map_hash_bucket_size 128;" "$NC"
check "nginx: exact names only, no suffix entry" bash -c 'grep -q "    api.anthropic.com \$ssl_preread_server_name:443;" "$1" && ! grep -qE "^    \." "$1"' _ "$NC"
check "iptables: 443 redirected for everyone but the proxy" grep -qx -- "iptables -t nat -A OUTPUT -p tcp --dport 443 ! -d 127.0.0.0/8 -m owner ! --uid-owner 33 -j REDIRECT --to-ports 8443" "$L"
check "iptables: DNS only from the proxy to the upstream, none for dnsmasq" bash -c 'grep -qx -- "iptables -A OUTPUT -p udp --dport 53 -d 10.1.2.3 -m owner --uid-owner 33 -j ACCEPT" "$1" && grep -qx -- "iptables -A OUTPUT -p tcp --dport 53 -d 10.1.2.3 -m owner --uid-owner 33 -j ACCEPT" "$1" && ! grep -q -- "--dport 53 .*--uid-owner 999" "$1"' _ "$L"
check "iptables: reject then default drop (IPv4 and IPv6)" bash -c 'grep -qx -- "iptables -A OUTPUT -j REJECT" "$1" && grep -qx -- "iptables -P OUTPUT DROP" "$1" && grep -qx -- "ip6tables -A OUTPUT -j REJECT" "$1" && grep -qx -- "ip6tables -P OUTPUT DROP" "$1"' _ "$L"
check "iptables: nothing else accepted on the open internet" bash -c '[ "$(grep -c -- "^iptables -A OUTPUT .*-j ACCEPT" "$1")" = 8 ]' _ "$L"
check "AppArmor: restriction kept on, only bwrap allowed" bash -c 'grep -qx -- "sysctl -q -w kernel.apparmor_restrict_unprivileged_userns=1" "$1" && grep -qx -- "apparmor_parser -r /etc/apparmor.d/agent-bwrap" "$1" && ! grep -q "userns=0" "$1"' _ "$L"
check "AppArmor: the profile file from the action is installed" bash -c 'grep -qx -- "install -m 0644 $2/action/agent-bwrap.apparmor /etc/apparmor.d/agent-bwrap" "$1"' _ "$L" "$T"
check "sudo removed: group, sudoers lines and sudoers.d files" bash -c 'grep -qx -- "gpasswd -d runner sudo" "$1" && grep -qx -- "gpasswd -d runner docker" "$1" && grep -qxF "sed -i -E /^[[:space:]]*(runner|ALL|%runner|%adm|%docker)[[:space:]]/d /etc/sudoers" "$1" && grep -q "^sh -c grep -lE .* sh runner|ALL|%runner|%adm|%docker$" "$1"' _ "$L"
check "sudoers.d cleanup is the last real sudo call" bash -c 'tail -n 4 "$1" > "$1.tail"; sed -n 1p "$1.tail" | grep -q "^sh -c grep -lE" && sed -n 2p "$1.tail" | grep -qx -- "-k" && sed -n 3p "$1.tail" | grep -qx -- "-n true" && sed -n 4p "$1.tail" | grep -qx -- "-n -l"' _ "$L"
check "Docker stopped and its sockets removed" grep -qx -- "rm -f /var/run/docker.sock /run/containerd/containerd.sock" "$L"
rm -rf "$T"
fresh; printf 'nameserver 127.0.0.53\n' > "$T/resolv.conf"; KEEP=1 run ok "no outside resolver: Azure DNS fallback" "Agent egress lock on:"
check "fallback upstream 168.63.129.16 used by the proxy's resolver" grep -q "  resolver 168.63.129.16 ipv6=off" "$(conf_of "$T/sudo.log" /etc/nginx/agent-egress.conf)"; rm -rf "$T"
fresh; KEEP=1 run ok "no dnsmasq user: one is created" "Agent egress lock on:" STUB_NO_DNSMASQ=1
check "useradd called for dnsmasq" grep -qx -- "useradd --system --no-create-home --shell /usr/sbin/nologin dnsmasq" "$T/sudo.log"; rm -rf "$T"
fresh; KEEP=1 run ok "dnsmasq user exists: none created" "Agent egress lock on:"
check "useradd not called" bash -c '! grep -q useradd "$1"' _ "$T/sudo.log"; rm -rf "$T"
fresh; rm -f "$T/userns"; KEEP=1 run ok "no AppArmor userns switch: nothing to set" "Agent egress lock on:"
check "no sysctl or AppArmor profile without the switch" bash -c '! grep -qE "sysctl|apparmor_parser" "$1"' _ "$T/sudo.log"; rm -rf "$T"
fresh; stub sudo 'printf "%s\n" "$*" >> "$STUB_SUDO_LOG"; [ "$*" = "-n true" ] && exit 1; [ "$*" = "-n -l" ] && exit 1; [ "$1" = -k ] && exit 0
case "$*" in *"apt-get install"*) [ -f "$STUB_SUDO_LOG.updated" ] && exit 0; exit 1;; *"apt-get update"*) touch "$STUB_SUDO_LOG.updated";; "chmod "*) shift; exec chmod "$@";; esac; exit 0'
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
fresh; printf '.windows.net\n' > "$T/action/allow-domains.txt"; run fail "suffix (wildcard) entry" "not a plain host name: '.windows.net'"
fresh; printf '.actions.githubusercontent.com\n' > "$T/action/allow-domains.txt"; run fail "the old Actions wildcard is refused" "not a plain host name: '.actions.githubusercontent.com'"
fresh; run fail "download does not match the pinned sha256" "does not match its pinned sha256" CLAUDE_CODE_SHA256=$(printf '%064d' 0)
fresh; printf '#!/usr/bin/env bash\necho "9.9.9 (Claude Code)"\n' > "$T/fake-claude"; SHA=$(sha256sum "$T/fake-claude" | cut -d' ' -f1); run fail "binary reports another version" "Claude Code 2.1.295 not installed"
fresh; run fail "no www-data user"          "no www-data user for nginx" STUB_NO_WWW=1
fresh; run fail "nginx stream module missing" "nginx stream module missing" STUB_NO_MODULE=1
fresh; stub sudo '[ "$*" = "-n true" ] && exit 1; [ "$1" = -k ] && exit 0; case "$*" in *"nginx -t"*) exit 1;; esac; exit 0'; run fail "nginx config invalid" "nginx config invalid"
# self-test checks
fresh; run fail "sudo still works"          "self-test: sudo still works" STUB_SUDO_RC=0
fresh; run fail "a command-limited sudo rule is left" "self-test: sudo still lists rules for this user" STUB_SUDO_L_RC=0
fresh; run fail "Docker still reachable"    "self-test: Docker still reachable" STUB_DOCKER_RC=0
# Unix socket paths are limited to 108 bytes, so the sockets live in a short folder under /tmp.
fresh; SK=$(mktemp -d /tmp/s.XXXXXX); python3 -c 'import socket,sys; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1])' "$SK/sock"; run fail "Docker socket still there" "self-test: Docker still reachable" AGENT_LOCK_TEST_DOCKER_SOCK="$SK/sock"; rm -rf "$SK"
fresh; run fail "allowed host unreachable"  "self-test: allowed host api.github.com not reachable" STUB_ALLOWED_RC=7
fresh; run fail "blocked host reachable"    "self-test: blocked host example.com reachable" STUB_REACHABLE=https://example.com
fresh; run fail "gist reachable"            "self-test: gist.github.com reachable" STUB_REACHABLE=https://gist.github.com
fresh; run fail "uploads reachable"         "self-test: uploads.github.com reachable" STUB_REACHABLE=https://uploads.github.com
fresh; run fail "allowed IP under another name" "self-test: allowed IP reachable under another name (SNI)" STUB_REACHABLE=example.com:443:192.0.2.1
fresh; run fail "raw IP reachable"          "self-test: raw IP without a name reachable" STUB_REACHABLE=https://192.0.2.1
fresh; run fail "subdomain of an allowed name reachable" "self-test: a subdomain of an allowed name (x.github.com) is reachable" STUB_REACHABLE=https://x.github.com
fresh; run fail "subdomain of the npm registry reachable" "self-test: a subdomain of an allowed name (x.registry.npmjs.org) is reachable" STUB_REACHABLE=https://x.registry.npmjs.org
fresh; run fail "an allowed name resolves to a real address (dnsmasq forwarded the query)" "self-test: DNS for an allowed name does not answer the sink address" STUB_NPM_IP=1.2.3.4
fresh; run fail "plain HTTP reachable"      "self-test: plain HTTP (port 80) reachable" STUB_REACHABLE=http://registry.npmjs.org
fresh; run fail "allowed name does not resolve" "self-test: DNS for an allowed name does not resolve" STUB_NO_NPM_DNS=1
fresh; run fail "blocked name resolves"     "self-test: DNS for a blocked name resolves" STUB_DNS_LEAK_RC=0
fresh; run fail "outside DNS reachable"     "self-test: outside DNS server reachable" STUB_TCP_RC=0
fresh; G=$(id -gn); SK=$(mktemp -d /tmp/s.XXXXXX); python3 -c 'import socket,sys; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1])' "$SK/admin.sock"; chmod 660 "$SK/admin.sock"; run fail "group-writable admin socket still there" "group-writable admin socket still there" AGENT_LOCK_TEST_ADMIN_GROUPS="$G" AGENT_LOCK_TEST_RUN_DIRS="$SK"; rm -rf "$SK"
fresh; run ok "known open routes are printed" "Known open routes"
fresh; run fail "IPv6 reachable"            "self-test: IPv6 reachable" "STUB_REACHABLE=-6"
fresh; KEEP=1 run fail "deliberate break"   "self-test: deliberate break" AGENT_LOCK_SELFTEST_BREAK=1
check "the deliberate break is the only failed check in the failed-checks output (what the break-on-purpose job asserts)" \
  bash -c '[ "$(sed -n "/^failed-checks<<EOF_FAILED$/,/^EOF_FAILED$/p" "$1" | sed "1d;\$d")" = "deliberate break (AGENT_LOCK_SELFTEST_BREAK=1)" ] && ! grep -q "^claude-path=" "$1"' _ "$T/out"; rm -rf "$T"
fresh; KEEP=1 run fail "two failures are both listed"  "self-test: deliberate break" AGENT_LOCK_SELFTEST_BREAK=1 STUB_SUDO_RC=0
check "failed-checks lists every failed check, one per line" bash -c '[ "$(sed -n "/^failed-checks<<EOF_FAILED$/,/^EOF_FAILED$/p" "$1" | sed "1d;\$d" | wc -l)" = 2 ] && grep -q "^sudo still works$" "$1"' _ "$T/out"; rm -rf "$T"
fresh; KEEP=1 run ok "no failed-checks output when every check passes" "Agent egress lock on"
check "a passing lock writes no failed-checks" bash -c '! grep -q failed-checks "$1" && grep -q "^claude-path=" "$1"' _ "$T/out"; rm -rf "$T"
fresh; run fail "a failed self-test stops the job" "self-test failed; see errors above" STUB_SUDO_RC=0
fresh; run fail "bubblewrap cannot start"   "self-test: bubblewrap cannot start" STUB_BWRAP_RC=1
fresh; run fail "children of bubblewrap can create user namespaces" "self-test: a program started by bubblewrap can create user namespaces" STUB_CHILD_USERNS_RC=0
fresh; rm -f "$T/userns"; run ok "no AppArmor switch: the child check is skipped" "Agent egress lock on:" STUB_CHILD_USERNS_RC=0
fresh; echo 0 > "$T/userns"; run fail "user namespaces left unrestricted" "self-test: unprivileged user namespaces are not restricted"
fresh; run fail "fronting: content for another host" "self-test: domain fronting through registry.npmjs.org answers for another host (Host: example.com, HTTP 200" STUB_FRONT="registry.npmjs.org=200"
fresh; run fail "fronting: redirect to another host" "self-test: domain fronting through github.com answers for another host (Host: example.com, HTTP 302 https://example.com/" STUB_FRONT="github.com=302=https://example.com/x"
fresh; KEEP=1 run fail "fronting: every foreign Host value is tried on every name" "(Host: claude.ai, HTTP 200" STUB_FRONT="broker.actions.githubusercontent.com=200"
check "fronting probes: 5 Host values for each of the 7 names and 2 runner services" bash -c '[ "$(grep -c "Host: www.cloudflare.com" "$1")" = 9 ] && [ "$(grep -c "Host: pypi.org" "$1")" = 9 ] && [ "$(grep -c "Host: storage.googleapis.com" "$1")" = 9 ] && grep -q "Host: claude.ai.*https://api.anthropic.com/" "$1"' _ "$T/curl.log"; rm -rf "$T"
fresh; run ok   "fronting: redirect to the same host is fine" "Agent egress lock on:" STUB_FRONT="github.com=301=https://github.com/ api.github.com=400 api.anthropic.com=403"
# The OIDC host of a job with id-token: write is added exactly, and probed like every other name
OIDC='https://run-actions-2-azure-eastus.actions.githubusercontent.com/abc/idtoken/def?api-version=2.0'
fresh; KEEP=1 run ok "OIDC host added exactly" "Agent egress lock on: 7 allowed names + 3 runner services" "ACTIONS_ID_TOKEN_REQUEST_URL=$OIDC"
check "dnsmasq and nginx know only the exact OIDC host" bash -c 'grep -qx "address=/run-actions-2-azure-eastus.actions.githubusercontent.com/192.0.2.1" "$1" && grep -q "    run-actions-2-azure-eastus.actions.githubusercontent.com \$ssl_preread_server_name:443;" "$2" && ! grep -q "^    \.actions" "$2"' _ "$(conf_of "$T/sudo.log" /etc/agent-dnsmasq.conf)" "$(conf_of "$T/sudo.log" /etc/nginx/agent-egress.conf)"; rm -rf "$T"
fresh; run fail "OIDC host on another domain" "unexpected OIDC host: 'evil.example.com'" "ACTIONS_ID_TOKEN_REQUEST_URL=https://evil.example.com/x"
fresh; run fail "OIDC URL that is not https" "unexpected OIDC host" "ACTIONS_ID_TOKEN_REQUEST_URL=http://run-actions-2.actions.githubusercontent.com/x"
fresh; run fail "fronting through the OIDC host" "domain fronting through run-actions-2-azure-eastus.actions.githubusercontent.com answers for another host" "ACTIONS_ID_TOKEN_REQUEST_URL=$OIDC" STUB_FRONT="run-actions-2-azure-eastus.actions.githubusercontent.com=200"
fresh; run fail "bad Bun version"           "bad BUN_VERSION" BUN_VERSION='1.3; curl evil'
fresh; run fail "bad Bun sha256"            "bad BUN_SHA256" BUN_SHA256=abc
fresh; run fail "Bun download does not match" "Bun download does not match its pinned sha256" BUN_SHA256=$(printf '%064d' 0)
FAKE_BUN_VER=9.9.9 fresh; run fail "Bun reports another version" "Bun 1.3.14 not installed"
fresh; KEEP=1 run fail "failed self-test (kept for checks)" "self-test failed" STUB_SUDO_RC=0
check "no claude-path or bun-path output when the self-test fails" bash -c '! grep -qE "^(claude|bun)-path=" "$1"' _ "$T/out"; rm -rf "$T"
# Other AppArmor profiles that grant user namespaces are unloaded, and the self-test checks they are gone
aa() { printf 'abi <abi/4.0>,\nprofile chrome /opt/google/chrome/chrome flags=(unconfined) {\n  userns,\n}\n' > "$T/apparmor.d/chrome"
  printf 'profile unprivileged_userns {\n  audit deny capability,\n  userns,\n}\n' > "$T/apparmor.d/unprivileged_userns"
  printf 'profile quiet /usr/bin/quiet {\n  capability,\n}\n' > "$T/apparmor.d/quiet"; }
fresh; aa; KEEP=1 run ok "userns profiles unloaded" "Agent egress lock on:"
check "chrome's profile is unloaded" grep -qx -- "apparmor_parser -R $T/apparmor.d/chrome" "$T/sudo.log"
check "Ubuntu's unprivileged_userns and profiles without userns stay" bash -c '! grep -qE "apparmor_parser -R .*/(unprivileged_userns|quiet)$" "$1"' _ "$T/sudo.log"; rm -rf "$T"
fresh; aa; printf 'chrome (unconfined)\nquiet (enforce)\n' > "$T/aa-loaded"; run fail "a userns profile still loaded" "self-test: AppArmor profiles that allow user namespaces are still loaded: chrome"
fresh; aa; printf 'quiet (enforce)\nunprivileged_userns (enforce)\n' > "$T/aa-loaded"; run ok "only allowed profiles loaded" "Agent egress lock on:"
fresh; run fail "root in a user namespace outside bubblewrap" "self-test: a program outside bubblewrap can become root in a user namespace" STUB_UNSHARE_RC=0
fresh; run fail "Claude Code download fails" "could not download Claude Code" STUB_CLAUDE_DL_RC=22
fresh; run fail "Bun download fails" "could not download Bun" STUB_BUN_DL_RC=22
fresh; printf 'not a zip' > "$T/fake-bun.zip"; run fail "corrupt Bun zip (its sha matches, it does not unpack)" "the Bun archive did not unpack" "BUN_SHA256=$(sha256sum "$T/fake-bun.zip" | cut -d' ' -f1)"
fresh; KEEP=1 run fail "systemd starts a system service for this user" "self-test: systemd lets this user start a system service" STUB_SYSTEMCTL_RC=0
check "the service tried is one that is not masked (systemd-tmpfiles-clean.service), with --no-ask-password" grep -q "systemctl --no-ask-password start systemd-tmpfiles-clean.service" "$T/calls.log"; rm -rf "$T"
fresh; KEEP=1 run fail "systemd runs a transient unit as root for this user" "self-test: systemd lets this user run a transient unit as root" STUB_SYSTEMD_RUN_RC=0
check "the transient unit asked for User=root, --wait, no password prompt" grep -q "systemd-run --no-ask-password --wait --quiet -p User=root true" "$T/calls.log"; rm -rf "$T"
fresh; run fail "polkit runs commands as root" "self-test: polkit (pkexec) lets this user run commands as root" STUB_PKEXEC_RC=0
fresh; KEEP=1 run ok "Docker units masked before sudo goes" "Agent egress lock on"
check "systemctl mask of docker.socket, docker.service and containerd.service" grep -q "systemctl mask docker.socket docker.service containerd.service" "$T/sudo.log"; rm -rf "$T"
STUB_PODMAN=1 fresh; run fail "podman becomes root in a user namespace" "self-test: podman can still become root in a user namespace" STUB_PODMAN_RC=0 STUB_PODMAN_UID=0
STUB_PODMAN=1 fresh; run ok "podman blocked" "Agent egress lock on:"
STUB_PODMAN=1 fresh; run ok "podman runs but is not root" "Agent egress lock on:" STUB_PODMAN_RC=0 STUB_PODMAN_UID=1001
fresh; KEEP=1 run ok "newuidmap/newgidmap lose setuid" "Agent egress lock on:"
check "chmod u-s,g-s called for both helpers" bash -c 'grep -qx -- "chmod u-s,g-s $1/newuidmap" "$2" && grep -qx -- "chmod u-s,g-s $1/newgidmap" "$2"' _ "$T/setuid" "$T/sudo.log"
check "both helpers lost setuid and setgid" bash -c '[ ! -u "$1/newuidmap" ] && [ ! -g "$1/newuidmap" ] && [ ! -u "$1/newgidmap" ] && [ ! -g "$1/newgidmap" ]' _ "$T/setuid"; rm -rf "$T"
fresh; run fail "setuid removal fails" "could not remove setuid from $T/setuid/newuidmap" STUB_SUDO_FAIL="chmod u-s,g-s"
fresh; run fail "helper still setuid after the lock" "self-test: $T/setuid/newuidmap is still setuid/setgid" STUB_CHMOD_NOOP=1
fresh; rm -f "$T/setuid/newuidmap" "$T/setuid/newgidmap"; run ok "no setuid helpers installed" "Agent egress lock on:"
fresh; rm -f "$T/userns"; run ok "no AppArmor switch: userns checks skipped" "Agent egress lock on:" STUB_UNSHARE_RC=0
# Reachability: every allowed name must answer through the lock
fresh; run fail "an allowed name that does not answer" "self-test: allowed name codeload.github.com not reachable through the lock" STUB_UNREACHABLE=codeload.github.com
# AppArmor: which profiles count as granting user namespaces, and failed unloads
ab() { printf 'profile agent-bwrap /usr/bin/bwrap {\n  allow userns,\n}\n' > "$T/apparmor.d/agent-bwrap"
  printf 'profile a1 /a {\n  audit userns,\n}\n' > "$T/apparmor.d/a1"
  printf 'profile a2 /b {\n  allow userns create,\n}\n' > "$T/apparmor.d/a2"
  printf 'profile a3 /c {\n  audit allow userns,\n}\n' > "$T/apparmor.d/a3"
  printf 'profile a4 /d {\n  deny userns,\n  # userns,\n}\n' > "$T/apparmor.d/a4"; }
fresh; ab; KEEP=1 run ok "AppArmor: userns grant forms" "Agent egress lock on:"
check "AppArmor: the lock's own agent-bwrap profile is never unloaded" bash -c '! grep -q "apparmor_parser -R .*agent-bwrap" "$1"' _ "$T/sudo.log"
check "AppArmor: audit / allow / create forms are unloaded" bash -c 'for n in a1 a2 a3; do grep -qx -- "apparmor_parser -R $2/apparmor.d/$n" "$1" || exit 1; done' _ "$T/sudo.log" "$T"
check "AppArmor: deny and commented userns lines stay" bash -c '! grep -q "apparmor_parser -R .*/a4$" "$1"' _ "$T/sudo.log"; rm -rf "$T"
fresh; aa; run ok "AppArmor: an unload that fails for a profile that is not loaded does not stop the lock" "Agent egress lock on:" STUB_SUDO_FAIL="apparmor_parser -R"
fresh; aa; printf 'chrome (unconfined)\n' > "$T/aa-loaded"; run fail "AppArmor: unload fails and the profile stays loaded" "still loaded: chrome" STUB_SUDO_FAIL="apparmor_parser -R"
# OIDC host: only https://<one label>.actions.githubusercontent.com/
for u in 'https://a;b.actions.githubusercontent.com/x' 'https://x.y.actions.githubusercontent.com/x' 'https://actions.githubusercontent.com/x' \
         'https://u@run-1.actions.githubusercontent.com/x' 'https://run-1.actions.githubusercontent.com:8443/x' 'https://RUN-1.actions.githubusercontent.com/x'; do
  fresh; run fail "OIDC host refused: $u" "unexpected OIDC host" "ACTIONS_ID_TOKEN_REQUEST_URL=$u"
done
check "the real allow-domains.txt is exactly the 7 reviewed host names" bash -c 'diff <(sed -e "s/#.*//" -e "s/[[:space:]]//g" -e "/^$/d" "$1" | sort) <(printf "%s\n" api.anthropic.com api.github.com codeload.github.com github.com registry.npmjs.org registry.yarnpkg.com repo.yarnpkg.com | sort) >/dev/null' _ "$LOCK_DIR/allow-domains.txt"
# A bare "OK" health answer is not fronting; any other 2xx body is
fresh; run ok   "fronting: a bare OK health answer is fine" "Agent egress lock on:" STUB_FRONT="api.github.com=200" STUB_FRONT_BODY=" OK
"
fresh; run fail "fronting: another 2xx body fails" "self-test: domain fronting through api.github.com answers for another host (Host: example.com, HTTP 200" STUB_FRONT="api.github.com=200" STUB_FRONT_BODY="<h1>Example Domain</h1>"
summary
