"""Shared state and helpers for scripts/check-workflows.py, check-workflows-claude.py and check-workflows-people.py (founder-owned): the
policy lists, the accounts list, the error list, and the secrets and claude-step tests. Rules and messages:
docs/runbooks/workflow-checker.md."""
import glob
import hashlib
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


def require_pinned(where, uses):
    """A remote action must be pinned to a full commit SHA (local ./ actions are checked by name elsewhere)."""
    u = str(uses or "")
    if u and not u.startswith("./") and not PINNED.match(u):
        err(f"{where}: action must be pinned to a full commit SHA: {u}")


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


PR_TRIGGERS = ("pull_request", "pull_request_target")
PINS_HASH = None   # sha256 of <root>/.github/pins.txt, set by check_pins_file


def _sha256(path):
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


def pinned_paths(root):
    """The repo-relative files .github/pins.txt must list (same rule as scripts/check-pins.sh)."""
    req = P["pins_required"]
    out = set()
    for d in req["dirs"]:
        for dp, _, fns in os.walk(os.path.join(root, d)):
            for fn in fns:
                out.add(os.path.relpath(os.path.join(dp, fn), root))
    for g in req["globs"]:
        for f in glob.glob(os.path.join(root, g)):
            if os.path.isfile(f) and not any(f.endswith(x) for x in req["exclude_suffixes"]):
                out.add(os.path.relpath(f, root))
    for f in req["files"]:
        if os.path.isfile(os.path.join(root, f)):
            out.add(f)
    return out


def check_pins_file(root):
    """pins.txt lists exactly the required files with their current sha256; remembers its own hash for the pin steps."""
    global PINS_HASH
    path = os.path.join(root, P["pins_file"])
    if not os.path.isfile(path):
        err(f"{P['pins_file']} is missing; run: bash scripts/check-pins.sh update")
        return
    PINS_HASH = _sha256(path)
    listed = {}
    for n, line in enumerate(open(path, encoding="utf-8"), 1):
        m = re.match(r"^([0-9a-f]{64})  (\S.*)$", line.rstrip("\n"))
        if not m:
            err(f"{P['pins_file']} line {n}: want '<sha256>  <path>'")
            continue
        listed[m.group(2)] = m.group(1)
    want = pinned_paths(root)
    for f in sorted(want - set(listed)):
        err(f"{P['pins_file']} does not list {f}; run: bash scripts/check-pins.sh update")
    for f in sorted(set(listed) - want):
        err(f"{P['pins_file']} lists {f}, which is not a pinned file (or no longer exists); run: bash scripts/check-pins.sh update")
    for f in sorted(want & set(listed)):
        if _sha256(os.path.join(root, f)) != listed[f]:
            err(f"{P['pins_file']}: {f} changed but its pin did not; run: bash scripts/check-pins.sh update")


def is_pins_step(step):
    """The exact pin step: name and run from the policy, env PINS_SHA256 equal to pins.txt's current hash, nothing else
    but an optional id."""
    if not isinstance(step, dict) or step.get("name") != P["pins_step_name"]:
        return False
    return True


def check_pins_step(fname, where, step):
    """Errors for a pin step that is not exactly right (called when is_pins_step matched the name). A workflow in
    pins_default_branch_workflows runs on a pushed branch but checks out the default branch, so its step takes the expected
    hash from the default branch's own guards.yml (which the agents' token cannot change) instead of its env."""
    if fname in P["pins_default_branch_workflows"]:
        if str(step.get("run", "")) != P["pins_step_run_default_branch"]:
            err(f"{where}: the pin step's run must be exactly the policy's pins_step_run_default_branch")
        if set(step) - {"name", "run", "id"}:
            err(f"{where}: the pin step may only have name, run and id (the hash comes from the default branch's guards.yml)")
        return
    if str(step.get("run", "")) != P["pins_step_run"]:
        err(f"{where}: the pin step's run must be exactly the policy's pins_step_run")
    env = step.get("env") if isinstance(step.get("env"), dict) else {}
    got = str(env.get("PINS_SHA256", ""))
    if PINS_HASH and got != PINS_HASH:
        err(f"{where}: PINS_SHA256 is {got or 'missing'} but {P['pins_file']} is {PINS_HASH}; run: bash scripts/check-pins.sh update")
    extra = set(step) - {"name", "env", "run", "id"}
    if extra or set(env) != {"PINS_SHA256"}:
        err(f"{where}: the pin step may only have name, env (PINS_SHA256), run and id")


def check_permissions(fname, where, perms, triggers):
    """The permissions allow-list for any job or workflow: only the policy's scopes (plus per-file ones), read/write/none,
    and never id-token: write in a workflow that runs on pull_request or pull_request_target (a PR could trade the OIDC
    token for cloud access)."""
    if perms is None:
        return
    if not isinstance(perms, dict):
        err(f"{where}: permissions must be a mapping of scopes (no read-all/write-all)")
        return
    for k, v in perms.items():
        scope_ok = k in P["permission_scopes"] or fname in P["per_file_permission_scopes"].get(k, [])
        if not scope_ok or v not in P["permission_values"]:
            err(f"{where}: permission {k}: {v} not allowed (scopes {', '.join(P['permission_scopes'])}; "
                f"per file {P['per_file_permission_scopes']}; read/write/none)")
        if k == "id-token" and v == "write" and any(t in PR_TRIGGERS for t in triggers):
            err(f"{where}: id-token: write is not allowed in a workflow that runs on pull_request/pull_request_target")


def accounts_from_rows(rows):
    """The validated rows of .github/accounts.txt ("<id> <login> <role>" per line) that scripts/check-workflows.sh read with
    scripts/check-accounts-lib.sh, the one parser of that file. Returns {id: (login, role)}."""
    out = {}
    for line in rows.splitlines():
        parts = line.split()
        if len(parts) == 3:
            out[parts[0]] = (parts[1], parts[2])
    return out
