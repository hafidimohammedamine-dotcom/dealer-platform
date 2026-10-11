# 2026-10-11 - the manager's tools are allowed by name

Founder change (`.github/workflows/agent-manager.yml`, pins).

- The first hosted shift after PR #30 (run 38095361132) ran 5 turns and did nothing: every `gh ...` and `git fetch`
  call was denied ("This command requires approval"). With Claude Code's subprocess isolation on
  (`CLAUDE_CODE_SUBPROCESS_ENV_SCRUB`), a Bash command that needs the network requires approval even under
  `--permission-mode bypassPermissions`, and a job has nobody to approve. Probe runs on 2026-10-11 (scratch branch
  `founder/probe-error`, run 38105755579): denied with the old flags; 0 denials with `--allowedTools` naming the tools.
- `--allowedTools "Bash,Read,Edit,MultiEdit,Write,Glob,Grep,TodoWrite,Agent,Task,Skill,NotebookEdit"` added. The deny
  list, the subprocess isolation, the network lock and the token scope are unchanged.
