#!/usr/bin/env bash
# Tests scripts/check-main-push.sh in a throwaway git repo (a bare "origin" plus a clone) with a stubbed gh.
set -uo pipefail
SCRIPT="$(cd "$(dirname "$0")" && pwd)/check-main-push.sh"
TMPROOT="${TMPDIR:-/tmp}"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-testlib.sh"
W=$(mktemp -d "$TMPROOT/mp.XXXXXX") || exit 2; trap 'rm -rf "$W"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null   # the test's local pushes must not pick up proxy/negotiation settings
mkdir -p "$W/nogit"; printf '#!/usr/bin/env bash\ncase "$1" in revert) [ "$2" = --abort ] && exit 0; exit 1;; esac; exec "%s" "$@"\n' "$(command -v git)" > "$W/nogit/git"; chmod +x "$W/nogit/git"
mkdir -p "$W/stub"; printf '#!/usr/bin/env bash\necho "gh $*" >> "$GH_LOG"; case "$1" in workflow) exit "${STUB_WF_RC:-0}";; issue) exit "${STUB_ISSUE_RC:-0}";; esac; exit 9\n' > "$W/stub/gh"; chmod +x "$W/stub/gh"
printf '111 founder-one founder\n222 founder-two founder\n333 agents-bot agent\n' > "$W/accounts"
fresh() { # a bare origin with main = base; a clone where the "pushed" commits are made and pushed to origin main
  rm -rf "$W/origin" "$W/clone"; git init -q --bare -b main "$W/origin"
  git clone -q "$W/origin" "$W/clone" 2>/dev/null; cd "$W/clone" && git checkout -q -b main 2>/dev/null
  git config user.email t@t && git config user.name t; echo base > f && git add f && git commit -qm base && git push -q origin main
  BASE=$(git rev-parse HEAD); : > "$W/gh.log"
}
push_commits() { for i in "$@"; do echo "$i" > "f$i" && git add "f$i" && git commit -qm "c$i"; done; git push -q origin main; HEAD=$(git rev-parse HEAD); }
run() { # run <ok|fail> <name> <message> <pusher> <before> <after> [VAR=value ...]
  local want=$1 name=$2 msg=$3 pusher=$4 before=$5 after=$6; shift 6
  out=$(cd "$W/clone" && env PATH="$W/stub:$PATH" GH_LOG="$W/gh.log" GH_REPO=owner/repo "$@" bash "$SCRIPT" "$pusher" "$before" "$after" "$W/accounts" 2>&1); rc=$?
  assert_result "$want" "$rc" "$name" "$msg" "$out"; }
Z=0000000000000000000000000000000000000000

fresh; push_commits 1; run ok "a founder's push is fine" "Push to main by founder 'founder-one' (ID 111): OK." 111 "$BASE" "$HEAD"
check "founder push: nothing reverted, nothing disabled, no issue" bash -c '! grep -q . "$1"' _ "$W/gh.log"
fresh; push_commits 1 2; run fail "an agent's push is reverted, the manager disabled, an issue opened" "Reverted 2 commit(s); disabled agent-manager.yml" 333 "$BASE" "$HEAD"
check "origin main now has the two reverts on top and the base content" bash -c 'cd "$1" && git fetch -q origin && [ "$(git rev-list --count origin/main)" = 5 ] && git show origin/main:f | grep -qx base && ! git ls-tree --name-only origin/main | grep -q "^f1$"' _ "$W/clone"
check "manager disabled and the issue labeled security + blocked" bash -c 'grep -q "gh workflow disable agent-manager.yml" "$1" && grep -q "gh issue create --title SECURITY: non-founder push to main by user ID 333 --label area:security --label blocked --label priority:1" "$1" && grep -q "@founder-one @founder-two" "$1"' _ "$W/gh.log"
fresh; push_commits 1; run fail "an unknown account's push" "not in $W/accounts, role unknown" 999 "$BASE" "$HEAD"
fresh; push_commits 1; run fail "a new-branch push (before = zeros) reverts up to 50 commits" "Reverted 2 commit(s)" 333 "$Z" "$HEAD"
fresh; cd "$W/clone" && git checkout -q -b side && echo s > s && git add s && git commit -qm side && git checkout -q main && git merge -q --no-ff -m merge side && git push -q origin main && HEAD=$(git rev-parse HEAD)
run fail "a merge commit is reverted against its first parent" "Reverted 1 commit(s)" 333 "$BASE" "$HEAD"
check "the merge's file is gone from origin main" bash -c 'cd "$1" && git fetch -q origin && ! git ls-tree --name-only origin/main | grep -q "^s$"' _ "$W/clone"
fresh; push_commits 1; run fail "disable fails: still reported, still exits 1" "could not disable agent-manager.yml; disable it by hand" 333 "$BASE" "$HEAD" STUB_WF_RC=1
fresh; push_commits 1; run fail "issue creation fails: the text goes to the log" "could not open the security issue; founders:" 333 "$BASE" "$HEAD" STUB_ISSUE_RC=1
fresh; push_commits 1; run fail "the pushed commits cannot be listed" "could not list the pushed commits" 333 "$(printf 'a%.0s' {1..40})" "$HEAD"
fresh; push_commits 1; run fail "revert conflict: aborted, the rest left to the founders" "did not apply cleanly" 333 "$BASE" "$HEAD" PATH="$W/nogit:$W/stub:$PATH"
check "revert conflict: nothing pushed, manager still disabled, issue still opened" bash -c 'cd "$1" && git fetch -q origin && [ "$(git rev-list --count origin/main)" = 2 ] && grep -q "gh workflow disable" "$2" && grep -q "Left to do" "$2"' _ "$W/clone" "$W/gh.log"
fresh; run fail "non-numeric pusher" "pusher id must be numeric" abc "$BASE" "$BASE"
fresh; run fail "bad sha" "before/after must be 40-hex" 333 "$BASE" nope
fresh; printf 'nonsense\n' > "$W/bad-accounts"; out=$(cd "$W/clone" && env PATH="$W/stub:$PATH" GH_LOG="$W/gh.log" GH_REPO=owner/repo bash "$SCRIPT" 333 "$BASE" "$BASE" "$W/bad-accounts" 2>&1); rc=$?
[ $rc = 1 ] && grep -q "bad line 1" <<<"$out" && t PASS "broken accounts file fails closed" || { t FAIL "broken accounts file ($rc)"; echo "$out"; }
out=$(cd "$W/clone" && env PATH="$W/stub:$PATH" GH_LOG="$W/gh.log" bash "$SCRIPT" 333 "$BASE" "$BASE" "$W/accounts" 2>&1); rc=$?
[ $rc != 0 ] && grep -q "GH_REPO" <<<"$out" && t PASS "GH_REPO required" || t FAIL "GH_REPO required ($rc)"
# main-guard.yml pins the script, its library and the accounts file: the pins must match the files (bump them in the same PR).
REPO_ROOT="$(cd "$(dirname "$SCRIPT")/.." && pwd)"
check "main-guard.yml's pins match scripts/check-main-push.sh, check-accounts-lib.sh and .github/accounts.txt" bash -c \
  'cd "$1" && sed -n "/sha256sum --check --strict <<.EOF./,/^ *EOF$/p" .github/workflows/main-guard.yml | grep -E "^ +[0-9a-f]{64}  " | sed "s/^ *//" | sha256sum --check --strict --quiet' _ "$REPO_ROOT"
summary
