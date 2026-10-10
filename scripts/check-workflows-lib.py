"""Shared state and helpers for scripts/check-workflows.py and scripts/check-workflows-claude.py (founder-owned): the
policy lists, the accounts list, the error list, and the secrets and claude-step tests. Rules and messages:
docs/runbooks/workflow-checker.md."""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
try:  # founder-owned policy data next to this file
    with open(os.path.join(HERE, "check-workflows-policy.json"), encoding="utf-8") as fh:
        P = json.load(fh)
except (OSError, ValueError) as e:
    print(f"ERROR: cannot read check-workflows-policy.json ({e})")
    sys.exit(1)
SECRETS_TOKEN = re.compile(r"\bsecrets\b(\s*\.\s*([A-Za-z_][A-Za-z0-9_]*))?")
CLAUDE_NAME = re.compile(r"claude|anthropic", re.I)
CRED_ENV = re.compile(r"ANTHROPIC_API_KEY|CLAUDE_CODE_OAUTH_TOKEN")
PINNED = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@[0-9a-f]{40}$")
errors = []


def err(msg):
    errors.append(msg)


def is_claude(step):
    return "claude-code" in str(step.get("uses", ""))


def secrets_problems(text, allow_claude=False):
    """Returns a list of problems with how `secrets` is used in text."""
    out = []
    for m in SECRETS_TOKEN.finditer(text):
        name = m.group(2)
        if not name:
            out.append("secrets used other than as secrets.<NAME>")
        elif CLAUDE_NAME.search(name) and not allow_claude:
            out.append(f"Claude/Anthropic credential secrets.{name}")
    if not allow_claude and CRED_ENV.search(text):
        out.append("Claude/Anthropic credential variable")
    return out


ACCOUNT_LINE = re.compile(r"^(\d+)\s+([A-Za-z0-9-]+)\s+(founder|agent)$")


def read_accounts(path):
    """Reads .github/accounts.txt ("<id> <login> founder|agent" per line, same rules as scripts/check-accounts-lib.sh).
    Returns {id: (login, role)}; reports a missing file, a bad line or no founder as errors (an empty result)."""
    try:
        with open(path, encoding="utf-8") as fh:
            lines = fh.read().splitlines()
    except OSError:
        err(f"accounts file not found: {path}")
        return {}
    out = {}
    for n, raw in enumerate(lines, 1):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        m = ACCOUNT_LINE.match(line)
        if not m:
            err(f"bad line {n} in {path} (want '<id> <login> founder|agent'): {line}")
            return {}
        out[m.group(1)] = (m.group(2), m.group(3))
    if not any(role == "founder" for _, role in out.values()):
        err(f"no founder listed in {path}")
        return {}
    return out
