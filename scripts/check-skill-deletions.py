#!/usr/bin/env python3
"""Checks that the lines removed from one upstream Markdown file are whole, safe units (founder-owned).

Usage: scripts/check-skill-deletions.py <upstream-file> [--label REL] [--reviewed FILE] [--whole-file] < removed-line-numbers
(1-based; nothing is read from stdin with --whole-file).
A removed (non-blank) line passes only if it belongs to one of these, removed completely:
  - a heading's own body: the heading line and every line up to the next heading of any level (outside code);
  - a fenced code block (``` or ~~~, 3 or more, CommonMark rules; an unclosed fence runs to the end of the file);
  - a whole table (header, separator and every row);
  - a single body row of a table (never its header or separator row alone), or a whole list item (its marker line and
    every deeper-indented line after it, nested list items included), outside code, with no warning or rule word (WARN_RE).
A removed section, code block or table that contains a warning or rule word also needs a founder's review: its entry
"<REL>:<upstream line of the heading, opening fence or header row>" must be in the --reviewed file. With --whole-file the
whole upstream file was deleted: if it contains a warning or rule word, the entry "<REL>:0" must be in the --reviewed file. Each one is printed as
"REVIEWED <REL>:<line> ..." (or reported as an error), so the guards log shows every such deletion.
Everything else - prose, part of a code block, part of a section, an indented code line - fails.
Blank lines may be removed anywhere.
"""
import re
import sys

USAGE = "usage: check-skill-deletions.py <upstream-file> [--label REL] [--reviewed FILE] [--whole-file] < removed-line-numbers"

WARN_RE = re.compile(
    r"❌|⚠|✅|🚫|\b(wrong|security|secure|insecure|unsafe|bug|never|must|not|don'?t|avoid|warning|danger|caution|"
    r"important|critical|required|require|always|only|bypass|override|overrideAccess|access|auth\w*|secret|password|"
    r"token|permission\w*|deny|denied|risk|careful|note|forbidden|forbid|prohibited|cannot|can'?t|unless|tenant\w*|pii|ssn|"
    r"credential\w*|encrypt\w*|sensitive|private|leak\w*|vulnerab\w*|cve|ghsa|inject\w*|xss|csrf|sanitiz\w*|escap\w*|"
    r"validat\w*|verify|role\w*|admin|limit\w*|should|do not)\b", re.I)
FENCE_OPEN = re.compile(r"^ {0,3}(`{3,}|~{3,})(.*)$")
HEADING = re.compile(r"^ {0,3}#{1,6}(\s|$)")
TABLE_ROW = re.compile(r"^ {0,3}\|")
TABLE_SEP = re.compile(r"^ {0,3}\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$")
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


def args(argv):
    """Returns (path, label, reviewed entries, whole_file, problem)."""
    path, label, reviewed, whole = None, None, set(), False
    rest = list(argv)
    while rest:
        a = rest.pop(0)
        if a == "--whole-file":
            whole = True
        elif a in ("--label", "--reviewed") and rest:
            v = rest.pop(0)
            if a == "--label":
                label = v
                continue
            try:
                with open(v, encoding="utf-8") as fh:
                    text = fh.read()
            except OSError as e:
                return None, None, None, False, f"cannot read {v} ({e.strerror})"
            reviewed.update(x for x in (ln.split("#", 1)[0].strip() for ln in text.splitlines()) if x)
        elif path is None and not a.startswith("--"):
            path = a
        else:
            return None, None, None, False, USAGE
    return (path, label or path, reviewed, whole, None) if path else (None, None, None, False, USAGE)


def list_items(lines, fence_of):
    """Maps each line of a list item (outside code) to (first line, last line) of the whole item: the marker line plus the
    following lines indented deeper than the marker, up to a blank line."""
    item_of = {}
    for i, text in enumerate(lines):
        if fence_of[i] is not None or not LIST_ITEM.match(text) or i in item_of:  # nested items belong to the outer item
            continue
        indent = len(text) - len(text.lstrip())
        j = i + 1
        while (j < len(lines) and lines[j].strip() and fence_of[j] is None and not HEADING.match(lines[j])
               and len(lines[j]) - len(lines[j].lstrip()) > indent):
            j += 1
        for k in range(i, j):
            item_of[k] = (i, j - 1)
    return item_of


def tables(lines, fence_of):
    """Maps each table line (outside code) to (first line, last line) of its table: consecutive '|' rows whose second
    row is a separator row."""
    table_of, i = {}, 0
    while i < len(lines):
        if fence_of[i] is None and TABLE_ROW.match(lines[i]):
            j = i
            while j + 1 < len(lines) and fence_of[j + 1] is None and TABLE_ROW.match(lines[j + 1]):
                j += 1
            if j > i and TABLE_SEP.match(lines[i + 1]):
                for k in range(i, j + 1):
                    table_of[k] = (i, j)
            i = j + 1
        else:
            i += 1
    return table_of


def first_warn(lines, a, b):
    return next((m for m in (WARN_RE.search(lines[k]) for k in range(a, b + 1)) if m), None)


def whole_units(lines, removed, fences, headings, table_of, label, reviewed):
    """Finds the whole sections, code blocks and tables removed. Returns (whole fence ids, lines in whole sections or
    tables, problems): a removed unit with a warning or rule word is a problem unless "<label>:<first line>" is in
    `reviewed`."""
    whole_fence = {fid for fid, (a, b) in enumerate(fences) if all(k in removed for k in range(a, b + 1))}
    in_whole_section = set()
    units = []  # (start line, end line) of every whole section or code block removed
    bounds = headings + [len(lines)]
    for h, nxt in zip(headings, bounds[1:]):
        if all(k in removed for k in range(h, nxt)):
            in_whole_section.update(range(h, nxt))
            units.append((h, nxt - 1))
    units += [fences[fid] for fid in sorted(whole_fence) if fences[fid][0] not in in_whole_section]
    for a, b in sorted(set(table_of.values())):
        if a not in in_whole_section and all(k in removed for k in range(a, b + 1)):
            in_whole_section.update(range(a, b + 1))
            units.append((a, b))
    bad = []
    for a, b in sorted(units):
        w = first_warn(lines, a, b)
        if not w:
            continue
        key = f"{label}:{a + 1}"
        if key in reviewed:
            print(f"REVIEWED {key} ({lines[a][:80]!r}, contains {w.group(0)!r})")
        else:
            bad.append((a, f"a section, code block or table with a warning or rule word ({w.group(0)!r}) that is not in the "
                           f"reviewed list (add '{key}' after a founder review)"))
    return whole_fence, in_whole_section, bad


def whole_file(lines, label, reviewed):
    """The whole upstream file was deleted: one with a warning or rule word needs the reviewed entry "<label>:0"."""
    w = first_warn(lines, 0, len(lines) - 1) if lines else None
    key = f"{label}:0"
    if not w:
        return 0
    if key in reviewed:
        print(f"REVIEWED {key} (whole file deleted, contains {w.group(0)!r})")
        return 0
    print(f"ERROR: whole file deleted that has a warning or rule word ({w.group(0)!r}); add '{key}' to the reviewed list "
          "after a founder review")
    return 1


def main():
    path, label, reviewed, whole, problem = args(sys.argv[1:])
    if problem:
        print(f"ERROR: {problem}")
        return 2
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            lines = fh.read().replace("\r\n", "\n").split("\n")
    except OSError as e:
        print(f"ERROR: cannot read {path} ({e.strerror})")
        return 2
    if lines and lines[-1] == "":
        lines.pop()
    if whole:
        return whole_file(lines, label, reviewed)
    removed = set()
    for tok in sys.stdin.read().split():
        if not tok.isdigit() or not 1 <= int(tok) <= len(lines):
            print(f"ERROR: bad removed line number {tok!r}")
            return 2
        removed.add(int(tok) - 1)
    fence_of, fences, headings = parse(lines)
    table_of = tables(lines, fence_of)
    whole_fence, in_whole_section, bad = whole_units(lines, removed, fences, headings, table_of, label, reviewed)
    item_of = list_items(lines, fence_of)
    for k in sorted(removed):
        if not lines[k].strip() or k in in_whole_section:
            continue
        if fence_of[k] is not None:
            if fence_of[k] not in whole_fence:
                bad.append((k, "part of a code block (keep it whole or remove it whole)"))
        elif k in item_of:
            a, b = item_of[k]
            w = first_warn(lines, a, b)
            if any(x not in removed for x in range(a, b + 1)):
                bad.append((k, f"part of a list item (lines {a + 1}-{b + 1}; remove it whole)"))
            elif w and k == a:
                bad.append((k, f"a table row or list item with a warning or rule word ({w.group(0)!r})"))
        elif k in table_of and k <= table_of[k][0] + 1:
            bad.append((k, f"the header or separator row of a table (lines {table_of[k][0] + 1}-{table_of[k][1] + 1}; "
                           "remove the whole table)"))
        elif k in table_of:   # a body row of a real table; a loose '|' line is not a unit and falls through
            w = WARN_RE.search(lines[k])
            if w:
                bad.append((k, f"a table row or list item with a warning or rule word ({w.group(0)!r})"))
        else:
            bad.append((k, "not part of a whole section, code block, table row or list item"))
    for k, why in bad[:10]:
        print(f"ERROR: upstream line {k + 1}: removed line is {why}: {lines[k][:120]}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
