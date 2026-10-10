#!/usr/bin/env bash
# Git settings shared by the guards that read other people's trees as data (founder-owned):
# scripts/check-review-prepare.sh (a PR's worktree and history), scripts/check-pr-archive.sh (a PR's tree unpacked for
# the guards) and scripts/check-skills-upstream-all.sh (a third-party skill's upstream).
# - NOFILTER: while those files are written, no git filter and no hook may run: a .gitattributes/.lfsconfig in the fetched
#   tree could otherwise make git-lfs (if installed on the runner) fetch from a URL the tree chose, and a hook would run
#   its code. Use: `git "${NOFILTER[@]}" fetch ...` / `git "${NOFILTER[@]}" worktree add ...` / `... checkout ...`.
# - git_no_attributes <git-dir>: the tree's own .gitattributes must not change what the guards see either - `export-ignore`
#   would drop a file from `git archive` (a skill or workflow the checks never see but the merge brings), `export-subst`,
#   `ident`, `eol`/`text` and `working-tree-encoding` would rewrite file contents. $GIT_DIR/info/attributes outranks every
#   in-tree .gitattributes, so one line there turns all of that off for every path.
# Pinned in .github/pins.txt. Tests: through the scripts' own tests (an LFS-filtered file stays a pointer, a post-checkout
# hook does not run, an export-ignored file is still unpacked).
NOFILTER=(-c core.hooksPath=/dev/null -c filter.lfs.smudge= -c filter.lfs.process= -c filter.lfs.required=false -c filter.lfs.clean=)
export GIT_LFS_SKIP_SMUDGE=1
git_no_attributes() {
  local dir=$1
  [ -d "$dir" ] || { echo "ERROR: not a git directory: $dir"; return 1; }
  mkdir -p "$dir/info"
  echo '* -export-ignore -export-subst -ident -text -eol -working-tree-encoding -filter' > "$dir/info/attributes"
}
