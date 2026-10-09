#!/usr/bin/env python3
"""Checks that the lines removed from one upstream Markdown file are whole, safe units (founder-owned).

Usage: scripts/check-skill-deletions.py <upstream-file> < removed-line-numbers (1-based, one per line)
A removed (non-blank) line passes only if it belongs to one of these, removed completely:
  - a heading's own body: the heading line and every line up to the next heading of any level (outside code);
  - a fenced code block (``` or ~~~, 3 or more, CommonMark rules; an unclosed fence runs to the end of the file);
  - a single table row or list item outside code that has no warning or rule word (WARN_RE).
Everything else - prose, part of a code block, part of a section, an indented code line - fails.
Blank lines may be removed anywhere. Whole-file removals are handled by the caller.
"""
import re
import sys

WARN_RE = re.compile(
    r"❌|⚠|✅|🚫|\b(wrong|security|secure|insecure|unsafe|bug|never|must|not|don'?t|avoid|warning|danger|caution|"
    r"important|critical|required|require|always|only|bypass|override|overrideAccess|access|auth\w*|secret|password|"
    r"token|permission\w*|deny|denied|risk|careful|note)\b", re.I)
FENCE_OPEN = re.compile(r"^ {0,3}(`{3,}|~{3,})(.*)$")
HEADING = re.compile(r"^ {0,3}#{1,6}(\s|$)")
TABLE_ROW = re.compile(r"^ {0,3}\|")
LIST_ITEM = re.compile(r"^ {0,7}([-*+]|\d{1,9}[.)])\s+\S")


def parse(lines):
    """Returns (fence_id per line or None, list of fence ranges, heading line indexes outside fences)."""
    n = len(lines)
    fence_of = [None] * n
    fences, headings = [], []
    i = 0
    while i < n:
        m = FENCE_OPEN.match(lines[i])
        if m and not (m.group(1)[0] == "`" and "`" in m.group(2)):
            ch, ln = m.group(1)[0], len(m.group(1))
            close = re.compile(r"^ {0,3}" + re.escape(ch) + "{" + str(ln) + r",}\s*$")
            j = i + 1
            while j < n and not close.match(lines[j]):
                j += 1
            end = min(j, n - 1)  # unclosed: runs to end of file
            fid = len(fences)
            fences.append((i, end))
            for k in range(i, end + 1):
                fence_of[k] = fid
            i = end + 1
            continue
        if HEADING.match(lines[i]):
            headings.append(i)
        i += 1
    return fence_of, fences, headings


def main():
    if len(sys.argv) != 2:
        print("ERROR: usage: check-skill-deletions.py <upstream-file> < removed-line-numbers")
        return 2
    lines = open(sys.argv[1], encoding="utf-8", errors="replace").read().split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    removed = set()
    for tok in sys.stdin.read().split():
        if not tok.isdigit() or not 1 <= int(tok) <= len(lines):
            print(f"ERROR: bad removed line number {tok!r}")
            return 2
        removed.add(int(tok) - 1)
    fence_of, fences, headings = parse(lines)
    whole_fence = {fid for fid, (a, b) in enumerate(fences) if all(k in removed for k in range(a, b + 1))}
    in_whole_section = set()
    bounds = headings + [len(lines)]
    for h, nxt in zip(headings, bounds[1:]):
        if all(k in removed for k in range(h, nxt)):
            in_whole_section.update(range(h, nxt))
    bad = []
    for k in sorted(removed):
        text = lines[k]
        if not text.strip() or k in in_whole_section:
            continue
        if fence_of[k] is not None:
            if fence_of[k] in whole_fence:
                continue
            bad.append((k, "part of a code block (keep it whole or remove it whole)"))
            continue
        if TABLE_ROW.match(text) or LIST_ITEM.match(text):
            w = WARN_RE.search(text)
            if w:
                bad.append((k, f"a table row or list item with a warning or rule word ({w.group(0)!r})"))
            continue
        bad.append((k, "not part of a whole section, code block, table row or list item"))
    for k, why in bad[:10]:
        print(f"ERROR: upstream line {k + 1}: removed line is {why}: {lines[k][:120]}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
