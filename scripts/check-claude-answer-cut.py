#!/usr/bin/env python3
"""The hand-off cut (founder-owned; run by scripts/check-claude-answer.sh, pinned): reads an agent's answer on stdin and
writes the text to hand to the post job on stdout.

- Bytes that are not UTF-8 become U+FFFD (never dropped) and NUL bytes are removed (a job output cannot carry them),
  BEFORE the size is measured. Trailing newlines are not kept.
- At most LIMIT bytes: the post job receives the text as one environment variable, and Linux rejects one over 128 KiB.
- A longer answer is cut at the last line break or blank before the cap, so a single-word token is never handed over in
  part, and never inside a -----BEGIN ... -----END block: blocks are paired in order (each BEGIN is closed by the next
  whole END line after it, markers matched without regard to case), and the kept text stops before the first BEGIN
  still open at the cut.
- When nothing before the cap is safe to keep, the text is withheld and WITHHELD is handed over instead.
- Every cut ends with MARK, a fixed ASCII line, so the reader can see the end is missing.
"""
import re
import sys

LIMIT = 120000
MARK = b"\n\n(truncated)"
WITHHELD = b"(answer withheld: no line break or blank before the %d-byte limit)" % LIMIT
BEGIN = re.compile(rb"-----BEGIN", re.IGNORECASE)
END_LINE = re.compile(rb"-----END[^\n]*-----", re.IGNORECASE)


def cut(b: bytes) -> bytes:
    b = b.decode("utf-8", "replace").encode("utf-8").replace(b"\0", b"").rstrip(b"\n")
    if len(b) <= LIMIT:
        return b
    keep = LIMIT - len(MARK)
    at = max(b.rfind(b"\n", 0, keep + 1), b.rfind(b" ", 0, keep + 1), b.rfind(b"\t", 0, keep + 1))
    if at >= 0:
        # Blocks in order: each BEGIN is closed by the next whole END line after it (both before the cut). The kept text
        # stops before the first BEGIN still open at the cut: an earlier block with no END, or the one the cap falls in.
        pos = 0
        while (m := BEGIN.search(b, pos, at)) is not None:
            e = END_LINE.search(b, m.end(), at)
            if e is None:
                at = b.rfind(b"\n", 0, m.start())
                break
            pos = e.end()
    if at < 0:
        return WITHHELD + MARK
    return b[:at].rstrip(b"\n") + MARK


if __name__ == "__main__":
    sys.stdout.buffer.write(cut(sys.stdin.buffer.read()))
