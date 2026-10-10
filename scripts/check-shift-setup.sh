#!/usr/bin/env bash
# The manager shift's setup, as one pinned script so that no free-form command runs before the Claude step (founder-owned):
# corepack for yarn, the git identity the agents commit with, and git pushes through gh (the agents' token in GH_TOKEN;
# the checkout stored no credentials). Usage: scripts/check-shift-setup.sh
set -euo pipefail
corepack enable
git config user.name "agent-manager"
git config user.email "agents@users.noreply.github.com"
gh auth setup-git
echo "Shift setup OK: corepack enabled, git identity agent-manager, git pushes through gh"
