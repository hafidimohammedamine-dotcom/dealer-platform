# 2026-10-09 - Agent permissions tuned from the first live runs

- **Manager shift** runs builders with full permissions again, plus a deny list (no npx/npm/curl/wget/sudo, no printing the
  environment, no force-push, merge, API deletes, secrets or auth commands, no reading runner internals). The allow-list blocked
  normal builder work such as `cd <worktree> && git status` and loops. Builders use `yarn` for everything.
- **Review team** may use read-only shell tools on the PR copy (`git -C /tmp/pr grep/ls-tree/status`, `cat`, `head`, `grep`,
  `ls`, `wc`, `sort`, `find /tmp/pr`). It still cannot run the PR's code, edit files, use the web or post anything itself.
