#!/usr/bin/env python3
"""Writes seccomp.json for the agent runner containers (founder-owned file).

Start: docker-default-seccomp.json, Docker's default profile (moby/moby v28.3.3, profiles/seccomp/default.json, Apache-2.0;
see NOTICE.md). Change: the user-namespace system calls that bubblewrap needs (Claude Code's subprocess isolation) are
allowed without CAP_SYS_ADMIN. Docker's default allows them only with that capability, which the containers do not get.
Everything else stays as Docker ships it. `scripts/check-agent-runner.sh` fails if seccomp.json differs from this output.

Usage: python3 -I make-seccomp.py <docker-default-seccomp.json> <seccomp.json>
"""
import json
import sys

USERNS_CALLS = ["clone", "clone3", "mount", "pivot_root", "setns", "umount2", "unshare"]


def build(default):
    prof = json.loads(json.dumps(default))  # deep copy
    # The default profile denies clone3 outright (so libc falls back to clone, whose namespace flags it filters) and allows
    # the others only with CAP_SYS_ADMIN. Drop those entries for our calls and add one unconditional allow.
    kept = []
    for rule in prof["syscalls"]:
        names = [n for n in rule["names"] if n not in USERNS_CALLS]
        if names:
            rule = dict(rule, names=names)
            kept.append(rule)
    kept.append({
        "names": USERNS_CALLS,
        "action": "SCMP_ACT_ALLOW",
        "comment": "agent runner: user namespaces for bubblewrap (Claude Code subprocess isolation); no capability needed",
    })
    prof["syscalls"] = kept
    return prof


def main(argv):
    if len(argv) != 3:
        print("usage: make-seccomp.py <docker-default-seccomp.json> <seccomp.json>", file=sys.stderr)
        return 2
    with open(argv[1], encoding="utf-8") as f:
        default = json.load(f)
    with open(argv[2], "w", encoding="utf-8") as f:
        json.dump(build(default), f, indent="\t")
        f.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
