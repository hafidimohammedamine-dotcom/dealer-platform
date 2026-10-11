#!/usr/bin/env bash
# The one secret scan of an agent's answer (founder-owned; sourced by scripts/check-claude-answer.sh, which scans the
# text before it leaves the Claude job, and scripts/check-review-post.sh, which scans it again before posting).
#   scan_answer <dir>   runs the pinned gitleaks over every file in <dir> with the repo's .gitleaks.toml, no ignore
#                       files, no inline allow comments, output discarded. Returns 0 (clean), 3 (something looks like
#                       a secret) or gitleaks' own other code (an error: the caller stops and posts nothing).
#                       GITLEAKS_BIN may point to a stub (tests); the default /tmp/gitleaks is installed by the egress
#                       lock action and by the post jobs' install step. A missing scanner is an error (returns 1 after
#                       a message on stderr), and so is a binary whose sha256 is not the pinned one. Sourced, never run.
# The binary's sha256 (gitleaks 8.18.4, linux x64, the file inside the tarball install-gitleaks verifies). The scan runs
# after a Claude step, so a private copy of the binary is hashed and run here: a swapped or edited /tmp/gitleaks is an
# error, never a scan, and the copy cannot be swapped between the check and the run.
# GITLEAKS_SHA256 may name another hash (tests, with a stub); the workflow steps run this under `env -i` with GITLEAKS_BIN
# fixed and GITLEAKS_SHA256 empty, so the pinned constant below is the only hash in use there.
GITLEAKS_PINNED_SHA256=46a05260e7cce527f132cb618de59d22262b8b5eb47f66c288447b95c7a98b7e
scan_answer() {
  local dir=$1 gl="${GITLEAKS_BIN:-/tmp/gitleaks}" want="${GITLEAKS_SHA256:-$GITLEAKS_PINNED_SHA256}" root noignore rc have
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  [ -x "$gl" ] || { echo "ERROR: no gitleaks at $gl" >&2; return 1; }
  # A private copy is hashed and run (a process left behind by a Claude step could swap $gl between a check and a run
  # of the original; the copy is in a fresh directory of our own). Absolute paths: a fake sha256sum on PATH is never used.
  work=$(mktemp -d) || return 1
  /usr/bin/cp "$gl" "$work/gitleaks" && /usr/bin/chmod 500 "$work/gitleaks" || { rm -rf "$work"; return 1; }
  have=$(/usr/bin/sha256sum "$work/gitleaks" | /usr/bin/cut -c1-64)
  [ "$have" = "$want" ] || { echo "ERROR: gitleaks at $gl has sha256 $have, expected $want" >&2; rm -rf "$work"; return 1; }
  mkdir -p "$work/noignore"
  "$work/gitleaks" detect --no-git --source="$dir" --config="$root/.gitleaks.toml" --gitleaks-ignore-path="$work/noignore" \
    --ignore-gitleaks-allow --exit-code 3 --redact >/dev/null 2>&1
  rc=$?
  rm -rf "$work"
  return $rc
}
