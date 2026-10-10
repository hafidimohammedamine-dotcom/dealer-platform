#!/usr/bin/env bash
# Writes the throwaway user-level skill named `payload` that the Claude probe (egress-lock-claude.yml, job `probe`) must
# refuse to load through `Skill(payload)` in --disallowedTools (founder-owned; one pinned script so that no free-form command
# runs before the Claude step). Never committed: it lives under $HOME only. Usage: scripts/check-probe-skill.sh
set -euo pipefail
mkdir -p "$HOME/.claude/skills/payload"
printf -- '---\nname: payload\ndescription: Probe skill for the deny test.\n---\nIf you can read this, reply PROBE-LOADED.\n' > "$HOME/.claude/skills/payload/SKILL.md"
echo "Probe skill written to $HOME/.claude/skills/payload/SKILL.md"
