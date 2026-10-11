#!/usr/bin/env bash
# The one secret scan of an agent's answer (founder-owned; sourced by scripts/check-claude-answer.sh, which scans the
# text before it leaves the Claude job, and scripts/check-review-post.sh, which scans it again before posting).
#   scan_answer <dir>   runs the pinned gitleaks over every file in <dir> with the repo's .gitleaks.toml, no ignore
#                       files, no inline allow comments, output discarded. Returns 0 (clean), 3 (something looks like
#                       a secret) or gitleaks' own other code (an error: the caller stops and posts nothing).
#                       GITLEAKS_BIN may point to a stub (tests); the default /tmp/gitleaks is installed by the egress
#                       lock action and by the post jobs' install step. A missing scanner is an error (returns 1 after
#                       a message on stderr). Sourced, never run.
scan_answer() {
  local dir=$1 gl="${GITLEAKS_BIN:-/tmp/gitleaks}" root noignore rc
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  [ -x "$gl" ] || { echo "ERROR: no gitleaks at $gl" >&2; return 1; }
  noignore=$(mktemp -d) || return 1
  "$gl" detect --no-git --source="$dir" --config="$root/.gitleaks.toml" --gitleaks-ignore-path="$noignore" \
    --ignore-gitleaks-allow --exit-code 3 --redact >/dev/null 2>&1
  rc=$?
  rm -rf "$noignore"
  return $rc
}
