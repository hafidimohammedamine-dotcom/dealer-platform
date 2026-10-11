#!/usr/bin/env python3
"""The hand-off cut (founder-owned; run by scripts/check-claude-answer.sh, pinned): reads an agent's answer on stdin and
writes the text to hand to the post job on stdout.

- Bytes that are not UTF-8 become U+FFFD (never dropped) and NUL bytes are removed (a job output cannot carry them),
  BEFORE the size is measured. Trailing newlines are not kept.
- At most LIMIT bytes: the post job receives the text as one environment variable, and Linux rejects one over 128 KiB.
- A longer answer is cut at the last line break, space or tab before the cap, so a single-word token is never handed
  over in part, and never inside a -----BEGIN ... -----END block: blocks are paired like brackets (an END line closes
  the nearest open BEGIN, markers matched without regard to case), and the kept text stops before the first BEGIN left
  open.
- When nothing before the cap is safe to keep, the text is withheld and WITHHELD is handed over instead; nothing of
  the answer is kept, not even its first line, so the post job posts FAIL: a PASS whose findings cannot be shown must
  never label a PR ready-to-merge (the founders accept losing that result; the review is simply re-run).
- Every cut ends with MARK, a fixed ASCII line, so the reader can see the end is missing.
"""
import re
import sys

LIMIT = 120000
MARK = b"\n\n(truncated)"
WITHHELD = b"(answer withheld: nothing before the %d-byte limit was safe to keep)" % LIMIT
BEGIN = re.compile(rb"-----BEGIN", re.IGNORECASE)
END_LINE = re.compile(rb"-----END[^\n]*-----", re.IGNORECASE)


def cut(b: bytes) -> bytes:
    b = b.decode("utf-8", "replace").encode("utf-8").replace(b"\0", b"").rstrip(b"\n")
    if len(b) <= LIMIT:
        return b
    keep = LIMIT - len(MARK)
    at = max(b.rfind(b"\n", 0, keep + 1), b.rfind(b" ", 0, keep + 1), b.rfind(b"\t", 0, keep + 1))
    if at >= 0:
        # Blocks before the cut, paired like brackets: a BEGIN opens, an END line closes the nearest open BEGIN. The kept
        # text stops before the first BEGIN left open (an earlier block with no END of its own, a stray END that closed
        # the wrong block, or the block the cap falls in).
        marks = sorted([(m.start(), 1) for m in BEGIN.finditer(b, 0, at)]
                       + [(m.start(), 0) for m in END_LINE.finditer(b, 0, at)])
        open_begins = []
        for start, is_begin in marks:
            if is_begin:
                open_begins.append(start)
            elif open_begins:
                open_begins.pop()
        if open_begins:
            at = b.rfind(b"\n", 0, open_begins[0])
    if at < 0:
        return WITHHELD + MARK
    return b[:at].rstrip(b"\n") + MARK


if __name__ == "__main__":
    sys.stdout.buffer.write(cut(sys.stdin.buffer.read()))
