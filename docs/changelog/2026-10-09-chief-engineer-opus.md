# 2026-10-09 - Chief Engineer temporarily on Opus

The Chief Engineer could not start on #19: the Claude account's Fable 5.1 usage ran out (HTTP 429, Manager log 2026-10-09).
Until that usage is available again, `.claude/agents/chief-engineer.md` runs on `opus`; CLAUDE.md and SETUP.md say so.
Fable 5.1 was removed from the manager skill's Step 1b heading and from the `escalated` label description
(`scripts/setup-github.sh`). Same tools, same instructions, same review rules. SETUP.md also now says the manager runs every hour
(it has since the max-pace change). A founder switches the model back to `claude-fable-5-1` later.
