#!/usr/bin/env bash
# Tests scripts/check-skill-deletions.py directly: upstream text + removed line numbers -> pass or fail.
set -uo pipefail
PY="$(cd "$(dirname "$0")" && pwd)/check-skill-deletions.py"
TMPROOT="${TMPDIR:-/tmp}"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-testlib.sh"
run() { # run <ok|fail> <name> <upstream text (printf)> <removed numbers> <message> [extra args]
  local want=$1 name=$2 text=$3 nums=$4 msg=$5; shift 5
  D=$(mktemp -d "$TMPROOT/sd.XXXXXX") || exit 2
  printf "$text" > "$D/up.md"
  out=$(printf '%s\n' $nums | python3 -I "$PY" "$D/up.md" "$@" 2>&1); rc=$?
  assert_result "$want" "$rc" "$name" "$msg" "$out"
  rm -rf "$D"; }
# Arguments and input
D0=$(mktemp -d "$TMPROOT/sd.XXXXXX"); out=$(python3 -I "$PY" 2>&1); rc=$?
if [ $rc = 2 ] && grep -q "usage:" <<<"$out"; then t PASS "usage error"; else t FAIL "usage error"; fi
out=$(python3 -I "$PY" a b 2>&1); rc=$?
if [ $rc = 2 ] && grep -q "usage:" <<<"$out"; then t PASS "two files is a usage error"; else t FAIL "two files"; fi
rm -rf "$D0"
run fail "removed line number not a number"  'a\nb\n' 'x' "bad removed line number 'x'"
run fail "removed line number past the end"  'a\nb\n' '3' "bad removed line number '3'"
run fail "removed line number zero"          'a\nb\n' '0' "bad removed line number '0'"
run ok   "nothing removed"                   'a\n' '' ''
# Units
run ok   "blank lines"                       'a\n\nb\n' '2' ''
run fail "prose line"                        'a\nb\n' '2' "not part of a whole section"
run ok   "heading's own body"                '# T\n## A\na\n## B\nb\n' '2 3' ''
run fail "heading without its body"          '# T\n## A\na\n## B\nb\n' '2' "upstream line 2"
run ok   "body up to a subheading (subsection kept)" '## A\na\n### A1\nx\n' '1 2' ''
run ok   "whole backtick block"                   'x\n```\ncode\n```\ny\n' '2 3 4' ''
run fail "part of a backtick block"               'x\n```\ncode\nmore\n```\n' '3' "part of a code block"
run ok   "whole tilde block with a backtick in its info string" 'x\n~~~ `js`\ncode\n~~~\n' '2 3 4' ''
run fail "part of a tilde block"               'x\n~~~\ncode\nmore\n~~~\n' '4' "part of a code block"
run fail "a 3-backtick line inside a 4-backtick block is not a fence" 'x\n````\n```\ncode\n```\nmore\n````\n' '6' "part of a code block"
run fail "unclosed fence runs to the end"    'x\n```\ncode\n## not a heading\n' '4' "part of a code block"
run ok   "whole unclosed fence"              'x\n```\ncode\n' '2 3' ''
run ok   "indented fence (up to 3 spaces)"   'x\n   ```\n   code\n   ```\n' '2 3 4' ''
run fail "indented code block line"          'x\n\n    code\n    more\n' '4' "not part of a whole section"
run fail "heading inside a fence at end of file is not a heading" '# T\n```\n# comment\n' '3' "part of a code block"
run ok   "CRLF file"                         '# T\r\n## A\r\na\r\n## B\r\n' '2 3' ''
# Table rows and list items
run ok   "plain list item"                   'x\n- one\n- two\n' '2' ''
run ok   "numbered list item"                'x\n1. one\n2. two\n' '2' ''
run fail "list item with a rule word"        'x\n- always set access\n' '2' "table row or list item with a warning or rule word"
run ok   "plain table row"                   '| a |\n|---|\n| b |\n' '3' ''
run fail "table row with a warning mark"     '| a |\n|---|\n| ❌ b |\n' '3' "warning or rule word"
run fail "a loose | line is not a table row"  'x\n| not a table\n' '2' "not part of a whole section, code block, table row or list item"
run fail "| rows without a separator row"     '| a |\n| b |\n' '2' "not part of a whole section"
run ok   "list item with its continuation lines" 'x\n- one\n  more of one\n- two\n' '2 3' ''
run fail "only the continuation line of a list item" 'x\n- one\n  more of one\n- two\n' '3' "part of a list item (lines 2-3; remove it whole)"
run fail "only the marker line of a list item" 'x\n- one\n  more of one\n- two\n' '2' "part of a list item"
run fail "rule word in a continuation line" 'x\n- one\n  you must not\n- two\n' '2 3' "warning or rule word"
run fail "bad argument next to --reviewed" 'a\n' '' "usage:" --reviewed /dev/null --bogus
# Whole units with warning words need a founder-reviewed entry
RV=$(mktemp -d "$TMPROOT/sd.XXXXXX"); printf 'ref/X.md:2  # reviewed: links only\n' > "$RV/rev"
run fail "section with a warning word, not reviewed" '# T\n## Security\nnever do x\n' '2 3' "not in the reviewed list (add 'ref/X.md:2'" --label ref/X.md
run ok   "section with a warning word, reviewed" '# T\n## Security\nnever do x\n' '2 3' "REVIEWED ref/X.md:2" --label ref/X.md --reviewed "$RV/rev"
run fail "code block with a warning word, not reviewed" 'x\n```\n// ❌ WRONG\n```\n' '2 3 4' "not in the reviewed list" --label ref/X.md
run ok   "code block with a warning word, reviewed" 'x\n```\n// ❌ WRONG\n```\n' '2 3 4' "REVIEWED ref/X.md:2" --label ref/X.md --reviewed "$RV/rev"
run fail "reviewed entry for another file does not count" '# T\n## Security\nnever\n' '2 3' "not in the reviewed list" --label ref/Y.md --reviewed "$RV/rev"
run fail "missing reviewed file"           'a\n' '' "cannot read" --reviewed /nonexistent/rev
rm -rf "$RV"
# Round 4: wider rule words, nested lists, whole tables, whole files
for w in forbidden prohibited cannot unless tenant PII SSN credentials encrypted sensitive should 'do not'; do
  run fail "list item with the rule word '$w'" "x\n- this is $w here\n" '2' "warning or rule word"
done
run fail "nested list item alone (part of its parent)" 'x\n- one\n  - nested\n- two\n' '3' "part of a list item (lines 2-3; remove it whole)"
run fail "parent without its nested item"   'x\n- one\n  - nested\n- two\n' '2' "part of a list item (lines 2-3"
run ok   "parent with its nested items"     'x\n- one\n  - nested\n    more\n- two\n' '2 3 4' ''
run fail "rule word only in a nested item"  'x\n- one\n  - never this\n- two\n' '2 3' "warning or rule word ('never')"
run fail "deeper item under a sibling is not part of the first item" 'x\n- one\n- two\n  - nested\n' '2 4' "part of a list item (lines 3-4"
run fail "table header row alone"           '| a |\n|---|\n| b |\n' '1' "header or separator row of a table (lines 1-3"
run fail "table separator row alone"        '| a |\n|---|\n| b |\n' '2' "header or separator row of a table"
run fail "header and separator without the body" '| a |\n|---|\n| b |\n' '1 2' "header or separator row"
run ok   "whole table without rule words"   'x\n| a |\n|:-:|\n| b |\ny\n' '2 3 4' ''
run fail "whole table with a rule word, not reviewed" 'x\n| a |\n|---|\n| must b |\n' '2 3 4' "not in the reviewed list (add 'up.md:2'" --label up.md
RV2=$(mktemp -d "$TMPROOT/sd.XXXXXX"); printf 'up.md:2\nup.md:0\n' > "$RV2/rev"
run ok   "whole table with a rule word, reviewed" 'x\n| a |\n|---|\n| must b |\n' '2 3 4' "REVIEWED up.md:2" --label up.md --reviewed "$RV2/rev"
run fail "body row with a rule word"        '| a |\n|---|\n| b |\n| never c |\n' '4' "warning or rule word"
run fail "pipe lines without a separator are not a table (and not a unit)" 'x\n| a\n| b\n' '2' "not part of a whole section"
run ok   "whole file without rule words"    'just text\n' '' '' --whole-file
run fail "whole file with a rule word, not reviewed" 'text\nmust do\n' '' "add 'up.md:0' to the reviewed list" --whole-file --label up.md
run ok   "whole file with a rule word, reviewed" 'text\nmust do\n' '' "REVIEWED up.md:0" --whole-file --label up.md --reviewed "$RV2/rev"
run ok   "empty whole file"                 '' '' '' --whole-file
out=$(python3 -I "$PY" /nonexistent/up.md </dev/null 2>&1); rc=$?
if [ $rc = 2 ] && grep -q "cannot read /nonexistent/up.md" <<<"$out"; then t PASS "missing upstream file"; else t FAIL "missing upstream file"; echo "$out"; fi
run fail "lazy continuation line (not indented) is not part of the item" 'x\n- one\nlazy text\n- two\n' '2 3' "not part of a whole section, code block, table row or list item"
run fail "heading indented 4 spaces is not a heading" '# T\n    ## not a heading\ntext\n' '2' "not part of a whole section"
run ok   "section that holds a code fence counts as one reviewed unit" '# T\n## Sec\n```\nnever x\n```\n## B\nb\n' '2 3 4 5' "REVIEWED up.md:2" --label up.md --reviewed "$RV2/rev"
run fail "the fence inside a reviewed section still needs the whole section" '# T\n## Sec\nkeep\n```\nnever x\n```\n## B\n' '4 5 6' "not in the reviewed list (add 'up.md:4'" --label up.md --reviewed "$RV2/rev"
rm -rf "$RV2"
summary
