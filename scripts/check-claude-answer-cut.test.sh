#!/usr/bin/env bash
# Direct unit tests of scripts/check-claude-answer-cut.py (cut(), imported, no shell hand-off in between). The shell
# tests in check-claude-answer.test.sh cover the same script through the hand-off; these pin the function itself.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/check-testlib.sh"
out=$(python3 -I - "$HERE/check-claude-answer-cut.py" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("cutmod", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
cut, LIMIT, MARK, WITHHELD = m.cut, m.LIMIT, m.MARK, m.WITHHELD
W = WITHHELD + MARK
def case(name, got, want): print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else " (got %r)" % got[:80]))
case("empty input stays empty", cut(b""), b"")
case("only newlines: empty (nothing to hand over)", cut(b"\n\n\n"), b"")
case("exactly LIMIT bytes pass whole", cut(b"a" * LIMIT), b"a" * LIMIT)
case("LIMIT + 1 bytes with no break: withheld", cut(b"a" * (LIMIT + 1)), W)
case("a line break at index 0 then no break: withheld, not an empty answer", cut(b"\n" + b"a" * LIMIT), W)
case("a lone CR is not a break (CR is kept as text)", cut(b"a" * 1000 + b"\r" + b"b" * LIMIT), W)
case("CRLF: the LF is the break, the CR stays", cut(b"head\r\n" + b"a" * 100 + b"\n" + b"b" * LIMIT), b"head\r\n" + b"a" * 100 + MARK)
case("the cut is at the last break before LIMIT - len(MARK)", cut(b"x" * 100 + b"\n" + b"y" * (LIMIT - len(MARK) - 101) + b"\n" + b"z" * 100), b"x" * 100 + b"\n" + b"y" * (LIMIT - len(MARK) - 101) + MARK)
blk = b"-----BEGIN T-----\nbody\n-----END T-----\n"
case("a closed block before the cut is kept", cut(b"h\n" + blk + b"q" * 1000 + b"\n" + b"r" * LIMIT), b"h\n" + blk + b"q" * 1000 + MARK)
case("an open block at the cut: the cut moves before its BEGIN", cut(b"h\n" + b"-----BEGIN T-----\n" + b"q" * LIMIT), b"h" + MARK)
case("two BEGINs then one END: the first stays open (brackets)", cut(b"h\n-----BEGIN A-----\n-----BEGIN B-----\n-----END B-----\n" + b"q" * 100 + b"\n" + b"r" * LIMIT), b"h" + MARK)
case("markers match in any case", cut(b"h\n-----begin t-----\n" + b"q" * LIMIT), b"h" + MARK)
case("an END that closes nothing is ignored", cut(b"h\n-----END T-----\n" + b"q" * 100 + b"\n" + b"r" * LIMIT), b"h\n-----END T-----\n" + b"q" * 100 + MARK)
case("bad UTF-8 becomes U+FFFD before the cap is measured", cut(b"\xff" * 30000 + b"\n" + b"a" * LIMIT), "\ufffd".encode() * 30000 + MARK)
case("NUL bytes are removed", cut(b"a\x00b"), b"ab")
case("a cut text is never over LIMIT bytes", len(cut(b"\xff" * LIMIT)) <= LIMIT, True)
PY
); rc=$?
[ "$rc" = 0 ] || { echo "ERROR: the python harness failed ($rc)"; echo "$out"; exit 1; }
while IFS= read -r line; do case "$line" in PASS\ *) t PASS "${line#PASS }";; FAIL\ *) t FAIL "${line#FAIL }";; *) echo "$line";; esac; done <<<"$out"
summary
