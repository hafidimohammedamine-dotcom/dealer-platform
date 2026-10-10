#!/usr/bin/env bash
# Entrypoint of the agent runner container (founder-owned file). Two modes:
#   run   (default): read a registration token on stdin, register as an ephemeral runner, run ONE job, exit.
#   check: no registration; run the network lock mounted at /lock in container mode and its self-test, then exit 0.
# Settings come from the environment: RUNNER_URL (repository URL), RUNNER_NAME, RUNNER_LABELS (comma-separated).
set -euo pipefail
MODE="${1:-run}"
case "$MODE" in
  check)
    [ -x /lock/lock.sh ] || { echo "check: mount the lock action at /lock (read-only)"; exit 2; }
    export GITHUB_OUTPUT=/tmp/gh-output GITHUB_ENV=/tmp/gh-env; : > "$GITHUB_OUTPUT"; : > "$GITHUB_ENV"
    # Same steps as the composite action before lock.sh: Node is not needed for the check, gitleaks is.
    bash /lock/lock.sh
    grep -q '^claude-path=' "$GITHUB_OUTPUT" || { echo "check: the lock did not publish claude-path"; exit 1; }
    # What the agents' jobs need after the lock, as in egress-lock-test.yml.
    if sudo -n true 2>/dev/null; then echo "check: sudo still works"; exit 1; fi
    bwrap --unshare-user --unshare-pid --ro-bind / / --dev /dev --proc /proc --tmpfs /tmp bash -c 'git --version >/dev/null && python3 -c 1' \
      || { echo "check: tools do not work inside bubblewrap (user namespaces; see docs/runbooks/agent-runner.md)"; exit 1; }
    curl -fsS -o /dev/null --max-time 20 https://api.github.com/zen || { echo "check: api.github.com not reachable through the lock"; exit 1; }
    echo "check OK: the lock works in this container"
    ;;
  run)
    : "${RUNNER_URL:?RUNNER_URL (https://github.com/<owner>/<repo>)}"; : "${RUNNER_NAME:?RUNNER_NAME}"; : "${RUNNER_LABELS:?RUNNER_LABELS}"
    TOKEN=$(head -c 200 | tr -d '[:space:]')   # from stdin, never from the environment or the command line
    [ -n "$TOKEN" ] || { echo "run: no registration token on stdin"; exit 2; }
    cd /actions-runner
    ./config.sh --unattended --ephemeral --disableupdate --replace \
      --url "$RUNNER_URL" --token "$TOKEN" --name "$RUNNER_NAME" --labels "$RUNNER_LABELS" --work _work >/dev/null
    unset TOKEN
    exec ./run.sh
    ;;
  *) echo "usage: agent-runner-entrypoint [run|check]"; exit 2;;
esac
