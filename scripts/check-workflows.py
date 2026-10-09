#!/usr/bin/env python3
"""Checks the agent workflows; fails closed. Rules and messages: docs/runbooks/ci-guards.md, "Workflow denies OK"."""
import glob
import importlib.util
import json
import os
import re
import shlex
import sys

try:
    import yaml
except ImportError:  # fail closed
    print("ERROR: python3 PyYAML is required (python3 -m pip install pyyaml==6.0.2)")
    sys.exit(1)

HERE = os.path.dirname(os.path.abspath(__file__))
try:  # founder-owned policy data next to this file
    with open(os.path.join(HERE, "check-workflows-policy.json"), encoding="utf-8") as fh:
        P = json.load(fh)
except (OSError, ValueError) as e:
    print(f"ERROR: cannot read check-workflows-policy.json ({e})")
    sys.exit(1)
LOCAL_ACTIONS, MANAGER = set(P["local_actions"]), P["manager"]
SECRETS_TOKEN = re.compile(r"\bsecrets\b(\s*\.\s*([A-Za-z_][A-Za-z0-9_]*))?")
CLAUDE_NAME = re.compile(r"claude|anthropic", re.I)
CRED_ENV = re.compile(r"ANTHROPIC_API_KEY|CLAUDE_CODE_OAUTH_TOKEN")
CLI_RE = re.compile(r"(^|[\s;&|(`$\"'/=])claude(\s|$|\")|claude-code|@anthropic-ai/|outputs\.claude-path|\.local/bin/claude", re.M)


class UniqueKeyLoader(yaml.SafeLoader):
    """Rejects duplicate keys (a second `with:` or `claude_args:` could hide the first)."""


def _construct_mapping(loader, node, deep=False):
    seen = set()
    for key_node, _ in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in seen:
            raise yaml.constructor.ConstructorError(None, None, f"duplicate key {key!r}", key_node.start_mark)
        seen.add(key)
    return yaml.SafeLoader.construct_mapping(loader, node, deep)


UniqueKeyLoader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, _construct_mapping)
errors = []
_spec = importlib.util.spec_from_file_location("check_workflows_claude", os.path.join(HERE, "check-workflows-claude.py"))
CLAUDE = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(CLAUDE)
CLAUDE.core = sys.modules[__name__]


def err(msg):
    errors.append(msg)


def third_party(manifests):
    """Skill names to deny: always_denied_skills plus every third-party skill in the manifests (same rules as
    manifest_lines in scripts/check-skills-lib.sh: blank and # lines skipped, name then kind)."""
    names = set(P["always_denied_skills"])
    for m in manifests:
        with open(m, encoding="utf-8") as fh:
            for line in fh:
                parts = line.split()
                if len(parts) >= 2 and not parts[0].startswith("#") and parts[1] == "third-party":
                    names.add(parts[0])
    return names


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


def check_other(where, obj):
    """Any part of a workflow that is not a claude step."""
    for p in sorted(set(secrets_problems(json.dumps(obj)))):
        err(f"{where}: {p} outside a claude step's claude_code_oauth_token")
    if not isinstance(obj, dict):
        return
    if "run" in obj and CLI_RE.search(str(obj["run"])):
        err(f"{where}: runs Claude outside the pinned claude-code-action")
    if "uses" in obj:
        u = str(obj["uses"])
        if "anthropic" in u.lower():
            err(f"{where}: runs Claude outside the pinned claude-code-action ({u})")
        if u.startswith("./") and u not in LOCAL_ACTIONS:
            err(f"{where}: local action not on the allow-list: {u}")
        if "/.github/workflows/" in u or u.startswith("docker://"):
            err(f"{where}: not allowed: {u}")


def check_job(fname, jname, job, required, triggers):
    """Checks one job; returns its number of claude steps."""
    jw = f"{fname} job {jname}"
    if not isinstance(job, dict):
        err(f"{jw}: not a mapping")
        return 0
    if "uses" in job:
        err(f"{jw}: reusable workflow not allowed: {job['uses']}")
    for key in ("container", "services"):
        if key in job:
            err(f"{jw}: '{key}' not allowed")
    for key, val in job.items():
        if key != "steps":
            check_other(f"{jw} {key}", val)
    steps = job.get("steps") or []
    if not isinstance(steps, list):
        err(f"{jw}: steps must be a list")
        return 0
    for i, step in enumerate(steps, 1):
        if not isinstance(step, dict):
            err(f"{jw} step {i}: not a mapping")
        elif not is_claude(step):
            check_other(f"{jw} step {i}", step)
    if any(isinstance(s, dict) and is_claude(s) for s in steps):
        return CLAUDE.check_job(fname, jw, job, steps, required, triggers)
    return 0


def check_actions(root):
    """Composite actions in .github/actions: same rules as other steps, and every remote action pinned by SHA."""
    for path in sorted(glob.glob(os.path.join(root, ".github", "actions", "*", "action.y*ml"))):
        name = os.path.relpath(path, root)
        doc = load_yaml(path, name)
        steps = ((doc or {}).get("runs") or {}).get("steps") if isinstance(doc, dict) else None
        if not isinstance(steps, list):
            err(f"{name}: not a composite action with steps")
            continue
        for i, step in enumerate(steps, 1):
            check_other(f"{name} step {i}", step)
            u = str(step.get("uses", "")) if isinstance(step, dict) else ""
            if u and not u.startswith("./") and not CLAUDE.PINNED.match(u):
                err(f"{name} step {i}: action must be pinned to a full commit SHA: {u}")


def load_yaml(path, name):
    try:
        with open(path, encoding="utf-8") as fh:
            return yaml.load(fh, Loader=UniqueKeyLoader)
    except yaml.YAMLError as e:
        err(f"{name}: not valid YAML or has duplicate keys ({str(e).splitlines()[0]})")
        return None


def triggers_of(doc):
    on = doc.get("on", doc.get(True))  # PyYAML reads a bare `on:` key as True
    if isinstance(on, str):
        return {on}
    if isinstance(on, list):
        return {str(x) for x in on}
    if isinstance(on, dict):
        return {str(k) for k in on}
    return set()


def check_file(path, required):
    name = os.path.basename(path)
    doc = load_yaml(path, name)
    if doc is None:
        return 0
    if not isinstance(doc, dict) or not isinstance(doc.get("jobs"), dict):
        err(f"{name}: no jobs mapping")
        return 0
    for key, val in doc.items():
        if key != "jobs":
            check_other(f"{name} {key}", val)
    triggers = triggers_of(doc)
    count = sum(check_job(name, jn, job, required, triggers) for jn, job in doc["jobs"].items())
    if count and doc.get("env"):
        err(f"{name}: no workflow-level env in a workflow with a claude step (use the job's env)")
    if count and triggers & {"pull_request"}:
        err(f"{name}: a workflow with a claude step must not run on pull_request (PR code next to a Claude token)")
    return count


def parse_args(argv):
    root, manifests, rest = None, [], list(argv)
    while rest:
        a = rest.pop(0)
        if a == "--manifest":
            if not rest:
                return None, None, "--manifest needs a file"
            manifests.append(rest.pop(0))
        elif root is None and not a.startswith("--"):
            root = a
        else:
            return None, None, f"bad argument {a!r}"
    return root, manifests, None


def main(argv):
    root, manifests, problem = parse_args(argv)
    if problem:
        print(f"ERROR: {problem}")
        return 1
    missing = [m for m in manifests if not os.path.isfile(m)]
    if missing:
        print(f"ERROR: manifest not found: {', '.join(missing)}")
        return 1
    root = root or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    d = os.path.join(root, ".github", "workflows")
    if not os.path.isdir(d):
        print(f"ERROR: no workflows folder {d}")
        return 1
    files = sorted(glob.glob(os.path.join(d, "*.yml")) + glob.glob(os.path.join(d, "*.yaml")))
    if not files:
        print(f"ERROR: no workflow files in {d}")
        return 1
    own = os.path.join(root, ".claude", "skills", "manifest.txt")
    required = third_party(manifests + ([own] if os.path.isfile(own) else []))
    counts = {os.path.basename(f): check_file(f, required) for f in files}
    check_actions(root)
    if counts.get(MANAGER, 0) != 1:
        err(f"expected exactly one claude step in {MANAGER} (found {counts.get(MANAGER, 0)})")
    for e in errors:
        print(f"ERROR: {e}")
    if errors:
        return 1
    print(f"Workflow denies OK (Skill denies: {', '.join(sorted(required))})")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
