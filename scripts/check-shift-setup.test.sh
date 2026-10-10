#!/usr/bin/env bash
# Tests scripts/check-shift-setup.sh with stubbed corepack and gh in a throwaway git repository.
set -uo pipefail
SCRIPT="$(cd "$(dirname "$0")" && pwd)/check-shift-setup.sh"
TMPROOT="${TMPDIR:-/tmp}"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-testlib.sh"
T=$(mktemp -d "$TMPROOT/ss.XXXXXX") || exit 2; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"; printf '#!/usr/bin/env bash\necho "corepack $*" >> "%s/log"; exit "${STUB_COREPACK_RC:-0}"\n' "$T" > "$T/bin/corepack"
printf '#!/usr/bin/env bash\necho "gh $*" >> "%s/log"; exit "${STUB_GH_RC:-0}"\n' "$T" > "$T/bin/gh"; chmod +x "$T/bin/corepack" "$T/bin/gh"
git init -q -b main "$T/r"
run() { : > "$T/log"; out=$(cd "$T/r" && env PATH="$T/bin:$PATH" GIT_CONFIG_GLOBAL=/dev/null "$@" bash "$SCRIPT" 2>&1); rc=$?; }
run; assert_result ok "$rc" "sets up corepack, the identity and gh for git" "Shift setup OK" "$out"
check "corepack enabled and gh auth setup-git called, in that order" bash -c '[ "$(tr "\n" " " < "$1")" = "corepack enable gh auth setup-git " ]' _ "$T/log"
check "the agents' git identity is set in the repository" bash -c '[ "$(git -C "$1" config user.name)" = agent-manager ] && [ "$(git -C "$1" config user.email)" = agents@users.noreply.github.com ]' _ "$T/r"
run STUB_COREPACK_RC=1; assert_result fail "$rc" "corepack failing stops the setup" "" "$out"
check "nothing after a failed corepack" bash -c '[ "$(cat "$1")" = "corepack enable" ]' _ "$T/log"
run STUB_GH_RC=1; assert_result fail "$rc" "gh auth setup-git failing stops the setup" "" "$out"
summary
