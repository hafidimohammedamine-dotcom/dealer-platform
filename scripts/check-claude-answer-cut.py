#!/usr/bin/env python3
"""The hand-off cut (founder-owned; run by scripts/check-claude-answer.sh, pinned): reads an agent's answer on stdin and
writes the text to hand to the post job on stdout.

- Bytes that are not UTF-8 become U+FFFD (never dropped) and NUL bytes are removed (a job output cannot carry them),
  BEFORE the size is measured. Trailing newlines are not kept.
- At most LIMIT bytes: the post job receives the text as one environment variable, and Linux rejects one over 128 KiB.
- A longer answer is cut at the last line break or blank before the cap, so a single-word token is never handed over in
  part, and never inside a -----BEGIN ... -----END block (markers matched without regard to case, and a block counts as
  closed only when its whole END line is before the cut): the cut moves to before the BEGIN line instead.
- When nothing before the cap is safe to keep, the text is withheld and WITHHELD is handed over instead.
- Every cut ends with MARK, a fixed ASCII line, so the reader can see the end is missing.
"""
import re
import sys

LIMIT = 120000
MARK = b"\n\n(truncated)"
WITHHELD = b"(answer withheld: no line break or blank before the 120000-byte limit)"
BEGIN = re.compile(rb"-----BEGIN", re.IGNORECASE)
END_LINE = re.compile(rb"-----END[^\n]*-----", re.IGNORECASE)


def cut(b: bytes) -> bytes:
    b = b.decode("utf-8", "replace").encode("utf-8").replace(b"\0", b"").rstrip(b"\n")
    if len(b) <= LIMIT:
        return b
    keep = LIMIT - len(MARK)
    at = max(b.rfind(b"\n", 0, keep + 1), b.rfind(b" ", 0, keep + 1), b.rfind(b"\t", 0, keep + 1))
    if at >= 0:
        begins = [m.start() for m in BEGIN.finditer(b, 0, at)]
        ends = [m.end() for m in END_LINE.finditer(b, 0, at)]   # whole END lines that end before the cut
        if begins and (not ends or begins[-1] > ends[-1]):      # a block open at the cut
            at = b.rfind(b"\n", 0, begins[-1])
    if at < 0:
        return WITHHELD + MARK
    return b[:at].rstrip(b"\n") + MARK


if __name__ == "__main__":
    sys.stdout.buffer.write(cut(sys.stdin.buffer.read()))
