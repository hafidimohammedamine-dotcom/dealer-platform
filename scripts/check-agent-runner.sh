#!/usr/bin/env bash
# Checks the agent runner files in .github/agent-runner (founder-owned): the seccomp profile is exactly what make-seccomp.py
# derives from Docker's default, the image is pinned (base digest, runner version and sha256) and runs as the runner user in
# container mode, the scripts parse, and the third-party notice is there. Run by guards and CI; fails closed.
# Usage: scripts/check-agent-runner.sh [folder]   (default .github/agent-runner next to this script's repo root)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DIR="${1:-$HERE/../.github/agent-runner}"
fail=0; bad() { echo "ERROR: $*"; fail=1; }
for f in Dockerfile entrypoint.sh agent-runner.sh make-seccomp.py seccomp.json docker-default-seccomp.json NOTICE.md; do
  [ -f "$DIR/$f" ] || { echo "ERROR: missing $DIR/$f"; exit 1; }
done

# 1. seccomp.json is derived, never hand-edited.
W=$(mktemp -d "${TMPDIR:-/tmp}/ar.XXXXXX"); trap 'rm -rf "$W"' EXIT
python3 -I "$DIR/make-seccomp.py" "$DIR/docker-default-seccomp.json" "$W/seccomp.json" || bad "make-seccomp.py failed"
cmp -s "$W/seccomp.json" "$DIR/seccomp.json" || bad "seccomp.json differs from make-seccomp.py's output: regenerate it (python3 -I make-seccomp.py docker-default-seccomp.json seccomp.json)"
python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["defaultAction"]=="SCMP_ACT_ERRNO"' "$DIR/seccomp.json" 2>/dev/null \
  || bad "seccomp.json must deny by default (defaultAction SCMP_ACT_ERRNO)"

# 2. The image is pinned and runs the job as a non-root user in container mode.
D="$DIR/Dockerfile"
grep -qE '^FROM ubuntu:[0-9]+\.[0-9]+@sha256:[0-9a-f]{64}$' "$D" || bad "Dockerfile: FROM must be ubuntu:<version>@sha256:<digest>"
[ "$(grep -c '^FROM ' "$D")" = 1 ] || bad "Dockerfile: exactly one FROM"
grep -qE '^ARG RUNNER_VERSION=[0-9]+\.[0-9]+\.[0-9]+$' "$D" || bad "Dockerfile: ARG RUNNER_VERSION=<x.y.z>"
grep -qE '^ARG RUNNER_SHA256=[0-9a-f]{64}$' "$D" || bad "Dockerfile: ARG RUNNER_SHA256=<64 hex>"
grep -qE '"\$\{RUNNER_SHA256\}  runner.tgz" \| sha256sum --check' "$D" || bad "Dockerfile: the runner download must be checked against RUNNER_SHA256"
grep -qE '^ENV AGENT_LOCK_CONTAINER=1( |$)' "$D" || bad "Dockerfile: ENV AGENT_LOCK_CONTAINER=1 (the lock's container mode)"
grep -qx 'USER runner' "$D" || bad "Dockerfile: USER runner (jobs never run as root)"
grep -qE 'rm -f /usr/bin/newuidmap /usr/bin/newgidmap' "$D" || bad "Dockerfile: remove the setuid helpers newuidmap/newgidmap"
if grep -nE '(curl|wget)[[:space:]]+(-|http)' "$D" | grep -vE 'curl -fsSL -o runner.tgz "https://github.com/actions/runner/releases/download/v\$\{RUNNER_VERSION\}/' >/dev/null; then
  bad "Dockerfile: only the pinned runner download may use curl/wget"
fi
grep -qE ':latest|--pull' "$D" && bad "Dockerfile: no :latest tags" || true

# 3. Scripts parse; the host script never puts a token in the environment or on a command line.
bash -n "$DIR/entrypoint.sh" || bad "entrypoint.sh does not parse"
bash -n "$DIR/agent-runner.sh" || bad "agent-runner.sh does not parse"
grep -qE '<<<"\$token"' "$DIR/agent-runner.sh" || bad "agent-runner.sh: the registration token must go to the container on stdin"
grep -qE -- '--cap-drop ALL' "$DIR/agent-runner.sh" || bad "agent-runner.sh: containers must start with --cap-drop ALL"
grep -qE 'seccomp=\$HERE/seccomp.json' "$DIR/agent-runner.sh" || bad "agent-runner.sh: containers must use seccomp.json"
grep -qE -- '--cap-add SYS_ADMIN|--privileged' "$DIR/agent-runner.sh" && bad "agent-runner.sh: no SYS_ADMIN or --privileged" || true
grep -qE 'TOKEN=\$\(head' "$DIR/entrypoint.sh" || bad "entrypoint.sh: the registration token must be read from stdin"

# 4. Third-party notice for the copied Docker profile.
grep -q 'docker-default-seccomp.json' "$DIR/NOTICE.md" && grep -qi 'Apache' "$DIR/NOTICE.md" || bad "NOTICE.md must name docker-default-seccomp.json and its Apache-2.0 license"

[ "$fail" = 0 ] || exit 1
echo "Agent runner files OK"
