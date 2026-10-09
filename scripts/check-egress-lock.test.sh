#!/usr/bin/env bash
# Unit tests for .github/actions/agent-egress-lock/lock.sh with stubbed system commands (no root, no network).
# Covers every `die` branch and every self-test check; the real-runner proof is .github/workflows/egress-lock-test.yml.
set -uo pipefail
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
  stub sudo '[ "$*" = "-n true" ] && exit "${STUB_SUDO_RC:-1}"; [ "$1" = -k ] && exit 0; exit 0'
  stub docker 'exit "${STUB_DOCKER_RC:-1}"'
  stub id 'case "$*" in "-u dnsmasq") echo 999;; "-u www-data") echo 33;; *) [ "${STUB_NO_WWW:-}" = 1 ] && [ "$1" = www-data ] && exit 1; exit 0;; esac'
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
esac
for r in ${STUB_REACHABLE:-}; do case " $* " in *"$r"*) exit 0;; esac; done
exit 7
EOF
  chmod +x "$S/curl"
}
run() { # run <ok|fail> <name> <message> [VAR=value ...]
  local want=$1 name=$2 msg=$3; shift 3
  out=$(cd "$T" && env -i PATH="$S:/usr/bin:/bin" HOME="$T/home" USER=runner GITHUB_OUTPUT="$T/out" GITHUB_ENV="$T/env" \
        CLAUDE_CODE_VERSION="$GOOD_VER" CLAUDE_CODE_SHA256="$SHA" STUB_BINARY="$T/fake-claude" TMPDIR="$T" \
        AGENT_LOCK_TEST_DOCKER_SOCK="$T/no-docker.sock" AGENT_LOCK_TEST_RUN_DIRS="$T/run" "$@" \
        bash "$T/action/lock.sh" 2>&1); rc=$?
  got=$([ $rc = 0 ] && echo ok || echo fail)
  if [ "$got" = "$want" ] && grep -qF -- "$msg" <<<"$out"; then pass=$((pass+1)); echo "PASS  $name"
  else failed=$((failed+1)); echo "FAIL  $name ($got)"; echo "$out" | tail -n 8; fi
  rm -rf "$T"; }

fresh; run ok   "all stubs healthy: lock on" "Agent egress lock on:"
fresh; out=$(cd "$T" && env -i PATH="$S:/usr/bin:/bin" HOME="$T/home" USER=runner GITHUB_OUTPUT="$T/out" GITHUB_ENV="$T/env" CLAUDE_CODE_VERSION="$GOOD_VER" CLAUDE_CODE_SHA256="$SHA" STUB_BINARY="$T/fake-claude" TMPDIR="$T" AGENT_LOCK_TEST_DOCKER_SOCK="$T/no-docker.sock" AGENT_LOCK_TEST_RUN_DIRS="$T/run" bash "$T/action/lock.sh" 2>&1)
if grep -qx "claude-path=$T/home/.local/bin/claude" "$T/out" && grep -qx "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1" "$T/env"; then pass=$((pass+1)); echo "PASS  outputs and env"; else failed=$((failed+1)); echo "FAIL  outputs and env"; cat "$T/out" "$T/env"; fi; rm -rf "$T"
# die branches
fresh; run fail "non-Linux runner"          "Linux x64 runners only" STUB_OS=Darwin
fresh; run fail "non-x64 runner"            "Linux x64 runners only" STUB_ARCH=aarch64
fresh; out=$(env -i PATH="$S:/usr/bin:/bin" HOME="$T/home" CLAUDE_CODE_VERSION=1.2.3 CLAUDE_CODE_SHA256="$SHA" bash "$T/action/lock.sh" 2>&1)
if grep -q "must run inside GitHub Actions" <<<"$out"; then pass=$((pass+1)); echo "PASS  outside GitHub Actions"; else failed=$((failed+1)); echo "FAIL  outside Actions"; echo "$out"; fi; rm -rf "$T"
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
echo "$pass passed, $failed failed"
[ "$failed" = 0 ]
