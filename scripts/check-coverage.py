#!/usr/bin/env python3
"""Line coverage of the bash guard scripts from an xtrace log (founder-owned). Used by scripts/check-coverage.sh.

Usage: check-coverage.py [--alias REGEX=SCRIPT]... <trace-file> <min-percent> <script.sh>...
--alias: traced files whose path matches REGEX count for SCRIPT (tests that run a temp copy of a script).
The trace has lines "+<file>:<line>: <command>" (PS4 set by the BASH_ENV hook in check-coverage.sh). Bash reports a
command that spans several lines at its LAST line, so each script is split into commands (start..end lines: backslash and
pipe/and/or continuations, open quotes and $( ), here-document bodies skipped) and a command counts as run if any of its
lines appears in the trace. Lines with no command of their own (then/else/fi/do/done/esac/{/}, ;;, a bare case pattern,
a function header) are not counted. Prints one line per script; exits 1 if any script is below <min-percent>.
"""
import os
import re
import sys

STRUCTURAL = re.compile(
    r"^(then|else|fi|do|done|esac|;;|\{|\}|\)|\(|"
    r"[A-Za-z_][A-Za-z0-9_]*\s*\(\)\s*\{?|"            # function header
    r"(done|fi|esac|\})(\s*[<>|].*)?|"                  # end of a block with a redirection: counted at its start line
    r"[^()\s]+\)\s*(;;)?|"                              # case pattern with no command
    r"\)\s*;;)$")
HEREDOC = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")
TRACE = re.compile(r"^\++(.+?):(\d+): ")


def scan(line, stack, heredocs):
    """Updates the open-context stack (quotes, $( ), ( )) for one line and collects here-document tags. Returns the line
    with any comment removed."""
    k = 0
    while k < len(line):
        c, top = line[k], (stack[-1] if stack else None)
        if top == "'":
            if c == "'":
                stack.pop()
        elif c == "\\":
            k += 1
        elif top == '"':
            if c == '"':
                stack.pop()
            elif line.startswith("$(", k):
                stack.append("$(")
                k += 1
        elif c in "'\"":
            stack.append(c)
        elif c == "#" and (k == 0 or line[k - 1] in " \t;(|&"):
            return line[:k]
        elif line.startswith("$(", k) or (c == "(" and k > 0 and line[k - 1] == "=") or (c == "(" and top == "$("):
            stack.append("$(" if c == "$" else "(")
            k += 1 if c == "$" else 0
        elif c == ")" and top in ("$(", "("):
            stack.pop()
        elif line.startswith("<<", k) and not line.startswith("<<<", k):
            m = HEREDOC.match(line, k)
            if m:
                heredocs.append(m.group(2))
                k = m.end() - 1
        k += 1
    return line


def commands(lines):
    """Returns a list of (start, end) 1-based line ranges, one per command, skipping comments and here-document bodies."""
    out, i, n = [], 0, len(lines)
    while i < n:
        start, stack, cont = i, [], True
        while cont and i < n:
            heredocs = []
            code = scan(lines[i], stack, heredocs).rstrip()
            i += 1
            for tag in heredocs:  # skip each here-document body
                while i < n and lines[i].strip() != tag:
                    i += 1
                i += 1
            cont = bool(stack) or code.endswith(("\\", "|", "&&", "||"))
        text = "\n".join(lines[start:i]).strip()
        bare = re.sub(r"\s#.*$", "", text).strip() if start + 1 == i else text  # a one-line command without its comment
        if text and not text.startswith("#") and not STRUCTURAL.match(bare):
            out.append((start + 1, i))
    return out


def hits(trace, aliases):
    seen = {}
    with open(trace, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            m = TRACE.match(line)
            if m:
                f = next((p for rx, p in aliases if rx.fullmatch(m.group(1))), m.group(1))
                seen.setdefault(os.path.realpath(f), set()).add(int(m.group(2)))
    return seen


def main(argv):
    argv, aliases = list(argv), []
    while len(argv) > 1 and argv[0] == "--alias" and "=" in argv[1]:
        rx, path = argv[1].split("=", 1)
        aliases.append((re.compile(rx), path))
        argv = argv[2:]
    if len(argv) < 3 or argv[0].startswith("--") or not re.fullmatch(r"\d+(\.\d+)?", argv[1]):
        print("usage: check-coverage.py [--alias REGEX=SCRIPT]... <trace-file> <min-percent> <script.sh>...")
        return 2
    trace, minimum, scripts = argv[0], float(argv[1]), argv[2:]
    seen, low = hits(trace, aliases), []
    for s in scripts:
        with open(s, encoding="utf-8") as fh:
            lines = fh.read().split("\n")
        cmds = commands(lines)
        ran = seen.get(os.path.realpath(s), set())
        missed = [(a, b) for a, b in cmds if not any(x in ran for x in range(a, b + 1))]
        pct = 100.0 * (len(cmds) - len(missed)) / len(cmds) if cmds else 100.0
        flag = "" if pct >= minimum else "  <-- below minimum"
        print(f"{pct:6.1f}%  {len(cmds) - len(missed):4d}/{len(cmds):<4d} {s}{flag}")
        if pct < minimum:
            low.append(s)
            for a, b in missed[:15]:
                print(f"         not run: line {a}{'-' + str(b) if b != a else ''}: {lines[a - 1].strip()[:90]}")
    return 1 if low else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
