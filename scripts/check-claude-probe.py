#!/usr/bin/env python3
"""Decides pass/fail for the probes in .github/workflows/egress-lock-claude.yml (founder-owned), from the claude-code-action's
execution file. Prints only short results, never a token.

Usage: check-claude-probe.py skill-deny <execution-file>
         Claude answered under the lock (EGRESS-LOCK-OK), did not load the probe skill (no PROBE-LOADED), and the Skill call
         for 'payload' is among the permission denials.
       check-claude-probe.py scrub <execution-file>
         A Bash tool result holds "SCRUB-PROBE env-tokens=0 proc-tokens=0 pid=<n>" (scripts/check-scrub-probe.sh).
Exit 0 = pass, 1 = fail, 2 = usage or unreadable file.
"""
import json
import re
import sys

SCRUB = re.compile(r"SCRUB-PROBE env-tokens=(\d+) proc-tokens=(\d+) pid=(\d+)")


def messages(path):
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    return [m for m in data if isinstance(m, dict)] if isinstance(data, list) else []


def skill_deny(msgs):
    results = [m for m in msgs if m.get("type") == "result"]
    last = results[-1] if results else {}
    text = str(last.get("result") or "")
    denials = last.get("permission_denials") or []
    print("result:", text[:200])
    print("denials:", json.dumps(denials)[:300])
    denied = any(isinstance(x, dict) and x.get("tool_name") == "Skill" and (x.get("tool_input") or {}).get("skill") == "payload"
                 for x in denials)
    return "EGRESS-LOCK-OK" in text and "PROBE-LOADED" not in text and denied


def scrub(msgs):
    outs = " ".join(str(c.get("content")) for m in msgs if m.get("type") == "user"
                    for c in ((m.get("message") or {}).get("content") or []) if isinstance(c, dict) and c.get("type") == "tool_result")
    m = SCRUB.search(outs)
    print("probe:", m.group(0) if m else "did not run")
    return bool(m) and m.group(1) == "0" and m.group(2) == "0"


def main(argv):
    if len(argv) != 2 or argv[0] not in ("skill-deny", "scrub"):
        print("usage: check-claude-probe.py skill-deny|scrub <execution-file>")
        return 2
    try:
        msgs = messages(argv[1])
    except (OSError, ValueError) as e:
        print(f"ERROR: cannot read the execution file ({e.__class__.__name__})")
        return 2
    ok = skill_deny(msgs) if argv[0] == "skill-deny" else scrub(msgs)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
