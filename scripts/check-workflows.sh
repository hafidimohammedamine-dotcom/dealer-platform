#!/usr/bin/env bash
# Checks the agent workflows (rules in scripts/check-workflows.py, which parses them as YAML and fails closed).
# Usage: scripts/check-workflows.sh [repo-root] [--manifest FILE ...]
set -euo pipefail
exec python3 -I "$(cd "$(dirname "$0")" && pwd)/check-workflows.py" "$@"
