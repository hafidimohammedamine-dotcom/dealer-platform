#!/usr/bin/env bash
# Git settings shared by the guards that check out other people's files as data (founder-owned):
# scripts/check-review-prepare.sh (a PR's tree) and scripts/check-skills-upstream-all.sh (a third-party skill's upstream).
# While those files are written, no git filter and no hook may run: a .gitattributes/.lfsconfig in the fetched tree could
# otherwise make git-lfs (if installed on the runner) fetch from a URL the tree chose, and a hook would run its code.
# Use: `git "${NOFILTER[@]}" fetch ...` / `git "${NOFILTER[@]}" worktree add ...` / `git "${NOFILTER[@]}" checkout ...`.
# Pinned in .github/pins.txt. Tests: through the two scripts' own tests (an LFS-filtered file stays a pointer, a
# post-checkout hook does not run).
NOFILTER=(-c core.hooksPath=/dev/null -c filter.lfs.smudge= -c filter.lfs.process= -c filter.lfs.required=false -c filter.lfs.clean=)
export GIT_LFS_SKIP_SMUDGE=1
