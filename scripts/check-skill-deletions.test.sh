#!/usr/bin/env bash
# Tests scripts/check-skill-deletions.py directly: upstream text + removed line numbers -> pass or fail.
set -uo pipefail
PY="$(cd "$(dirname "$0")" && pwd)/check-skill-deletions.py"
TMPROOT="${TMPDIR:-/tmp}"
pass=0; failed=0
run() { # run <ok|fail> <name> <upstream text (printf)> <removed numbers> <message> [extra args]
  local want=$1 name=$2 text=$3 nums=$4 msg=$5; shift 5
  D=$(mktemp -d "$TMPROOT/sd.XXXXXX") || exit 2
  printf "$text" > "$D/up.md"
  out=$(printf '%s\n' $nums | python3 -I "$PY" "$D/up.md" "$@" 2>&1); rc=$?
  got=$([ $rc = 0 ] && echo ok || echo fail)
  if [ "$got" = "$want" ] && grep -qF -- "$msg" <<<"$out"; then pass=$((pass+1)); echo "PASS  $name"
  else failed=$((failed+1)); echo "FAIL  $name ($got, rc=$rc)"; echo "$out"; fi
  rm -rf "$D"; }
# Arguments and input
D0=$(mktemp -d "$TMPROOT/sd.XXXXXX"); out=$(python3 -I "$PY" 2>&1); rc=$?
if [ $rc = 2 ] && grep -q "usage:" <<<"$out"; then pass=$((pass+1)); echo "PASS  usage error"; else failed=$((failed+1)); echo "FAIL  usage error"; fi
out=$(python3 -I "$PY" a b 2>&1); rc=$?
if [ $rc = 2 ] && grep -q "usage:" <<<"$out"; then pass=$((pass+1)); echo "PASS  two files is a usage error"; else failed=$((failed+1)); echo "FAIL  two files"; fi
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
echo "$pass passed, $failed failed"
[ "$failed" = 0 ]
