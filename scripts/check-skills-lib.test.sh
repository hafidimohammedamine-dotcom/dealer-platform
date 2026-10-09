#!/usr/bin/env bash
# Tests scripts/check-skills-lib.sh (manifest and SKILLS-LOCK.md parsing shared by the skill guards).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/check-skills-lib.sh
. "$HERE/check-skills-lib.sh"
TMPROOT="${TMPDIR:-/tmp}"
pass=0; failed=0
W=$(mktemp -d "$TMPROOT/sl.XXXXXX") || exit 2
trap 'rm -rf "$W"' EXIT
check() { local name=$1; shift; if "$@"; then pass=$((pass+1)); echo "PASS  $name"; else failed=$((failed+1)); echo "FAIL  $name"; fi; }
eq() { [ "$1" = "$2" ] || { echo "  got:      $(printf '%q' "$1")"; echo "  expected: $(printf '%q' "$2")"; return 1; }; }
SHA=0123456789abcdef0123456789abcdef01234567

# manifest_lines / manifest_entries
printf '# comment\n\nalpha third-party requires=beta requires=gamma\n  # indented comment\nbeta own\ngamma\tthird-party  x=1\nlone\n' > "$W/m.txt"
check "manifest_lines skips blank and # lines, splits name/kind/rest" eq "$(manifest_lines "$W/m.txt")" \
  "$(printf 'alpha\tthird-party\trequires=beta requires=gamma\nbeta\town\t\ngamma\tthird-party\tx=1\nlone\t\t')"
check "manifest_entries: first requires= wins, empty when none" eq "$(manifest_entries "$W/m.txt")" \
  "$(printf 'alpha third-party beta\nbeta own \ngamma third-party \nlone  ')"
check "the Python parser (check-workflows.py third_party) reads the same third-party names" eq \
  "$(python3 -I - "$HERE/check-workflows.py" "$W/m.txt" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("cw", sys.argv[1]); cw = importlib.util.module_from_spec(spec)
sys.modules["cw"] = cw; spec.loader.exec_module(cw); cw.P["always_denied_skills"] = []
print(" ".join(sorted(cw.third_party([sys.argv[2]]))))
PY
)" "$(manifest_entries "$W/m.txt" | awk '$2=="third-party"{print $1}' | sort | xargs)"
check "the real manifest parses the same way in both (third-party names)" eq \
  "$(python3 -I - "$HERE/check-workflows.py" "$HERE/../.claude/skills/manifest.txt" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("cw", sys.argv[1]); cw = importlib.util.module_from_spec(spec)
sys.modules["cw"] = cw; spec.loader.exec_module(cw); cw.P["always_denied_skills"] = []
print(" ".join(sorted(cw.third_party([sys.argv[2]]))))
PY
)" "$(manifest_entries "$HERE/../.claude/skills/manifest.txt" | awk '$2=="third-party"{print $1}' | sort | xargs)"

# valid_skill_name
for n in a payload my-skill-2; do check "valid name $n" valid_skill_name "$n"; done
for n in "" -x Upper "a b" "a/b" "../x" "a_b"; do check "invalid name '$n'" bash -c '. "$1"; ! valid_skill_name "$2"' _ "$HERE/check-skills-lib.sh" "$n"; done

# lock_parse
check "lock_parse: good row" bash -c '. "$1"; lock_parse "| demo | acme/tools \`skills/demo\`, MIT | $2 | x |" && [ "$LOCK_REPO|$LOCK_PATH|$LOCK_SHA" = "acme/tools|skills/demo|$2" ]' _ "$HERE/check-skills-lib.sh" "$SHA"
for bad in "| demo | acme \`skills/demo\` | $SHA |" "| demo | acme/tools skills/demo | $SHA |" "| demo | acme/tools \`skills/demo\` | ${SHA:0:12} |" \
           "| demo | acme/tools \`skills/demo\` | ${SHA^^} |" "| demo | acme/tools \`/etc\` | $SHA |" "| demo | acme/tools \`a/../b\` | $SHA |" \
           "| demo | x acme/tools \`p\` | $SHA |" "| demo | acme/tools \`p\` | $SHA extra |"; do
  check "lock_parse rejects: $bad" bash -c '. "$1"; ! lock_parse "$2"' _ "$HERE/check-skills-lib.sh" "$bad"
done

# lock_rows / lock_row_one return codes
printf '| Skill | Source | Commit |\n|---|---|---|\n| demo | acme/tools `skills/demo` | %s |\n| two | a/b `p` | %s |\n| two | a/b `q` | %s |\n| broken | nope | %s |\n| demo, x | a/b `p` | %s |\n' "$SHA" "$SHA" "$SHA" "$SHA" "$SHA" > "$W/LOCK.md"
rc_of() { local rc=0; lock_row_one "$1" "$2" || rc=$?; echo "$rc"; }
check "lock_row_one: one good row -> 0"    eq "$(rc_of "$W/LOCK.md" demo)" 0
check "lock_row_one: missing file -> 1"     eq "$(rc_of "$W/none.md" demo)" 1
check "lock_row_one: no row -> 2"           eq "$(rc_of "$W/LOCK.md" nosuch)" 2
check "lock_row_one: two rows -> 3"         eq "$(rc_of "$W/LOCK.md" two)" 3
check "lock_row_one: bad shape -> 4"        eq "$(rc_of "$W/LOCK.md" broken)" 4
check "lock_rows: exact first-cell match only" eq "$(lock_rows "$W/LOCK.md" demo | wc -l | tr -d ' ')" 1
check "lock_rows: a name inside another cell does not match" eq "$(lock_rows "$W/LOCK.md" x)" ""

# lock_row_error: one message per code
check "lock_row_error 1" eq "$(lock_row_error 1 demo)" "third-party skill 'demo' has no row in SKILLS-LOCK.md (no SKILLS-LOCK.md file)"
check "lock_row_error 2" eq "$(lock_row_error 2 demo)" "third-party skill 'demo' has no row in SKILLS-LOCK.md"
check "lock_row_error 3" eq "$(lock_row_error 3 demo)" "skill 'demo' has more than one row in SKILLS-LOCK.md"
check "lock_row_error 4" eq "$(lock_row_error 4 demo)" "SKILLS-LOCK.md row for 'demo' must read '| demo | owner/repo \`path\`, ... | <40-hex commit, lower case> | ...'"
echo "$pass passed, $failed failed"
[ "$failed" = 0 ]
