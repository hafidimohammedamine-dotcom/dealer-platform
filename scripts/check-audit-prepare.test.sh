#!/usr/bin/env bash
# Tests scripts/check-audit-prepare.sh in a throwaway git repository.
set -uo pipefail
SCRIPT="$(cd "$(dirname "$0")" && pwd)/check-audit-prepare.sh"
TMPROOT="${TMPDIR:-/tmp}"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-testlib.sh"
T=$(mktemp -d "$TMPROOT/ap.XXXXXX") || exit 2; trap 'rm -rf "$T"' EXIT
git init -q -b main "$T/r" && cd "$T/r" && git config user.email t@t && git config user.name t && echo a > a.txt && mkdir d && echo b > d/b.txt && git add -A && git commit -qm first && echo c > a.txt && git commit -qam second
out=$(bash "$SCRIPT" "$T/meta" 2>&1); rc=$?
assert_result ok "$rc" "writes the history files" "Audit data in $T/meta: " "$out"
check "log.txt holds both commits with stats" bash -c 'grep -q "second" "$1/log.txt" && grep -q "first" "$1/log.txt" && grep -q "a.txt" "$1/log.txt"' _ "$T/meta"
check "files.txt lists every tracked file" bash -c '[ "$(sort "$1/files.txt" | tr "\n" " ")" = "a.txt d/b.txt " ]' _ "$T/meta"
check "date.txt is an ISO-8601 UTC time" bash -c 'grep -qE "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$" "$1/date.txt"' _ "$T/meta"
check "no delivered audit: a placeholder line" grep -q "no dependency audit was delivered" "$T/meta/npm-audit.json"
mkdir -p "$T/meta2" && printf '{"advisories":{}}\n' > "$T/meta2/npm-audit.json"
out=$(bash "$SCRIPT" "$T/meta2" 2>&1); rc=$?
assert_result ok "$rc" "a delivered audit file is kept as is" "npm-audit.json 18 bytes" "$out"
check "the delivered audit was not replaced" grep -q '"advisories"' "$T/meta2/npm-audit.json"
out=$(cd "$T" && bash "$SCRIPT" "$T/meta3" 2>&1); rc=$?
assert_result fail "$rc" "outside a git repository it fails" "" "$out"
summary
