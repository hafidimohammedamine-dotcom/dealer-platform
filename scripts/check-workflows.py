#!/usr/bin/env python3
"""Checks the agent workflows (founder-owned). Parses every workflow as YAML and fails closed.

Rules:
  1. Claude runs only through the pinned claude-code-action (CLAUDE_ACTIONS). No other step may run the claude CLI or
     @anthropic-ai/claude-code, and no reusable workflow, container job or local action outside LOCAL_ACTIONS is used.
  2. Claude credentials (secrets.*CLAUDE*/*ANTHROPIC*, secrets['...'], toJSON(secrets), ANTHROPIC_API_KEY,
     CLAUDE_CODE_OAUTH_TOKEN) appear only in a claude step's `claude_code_oauth_token` input.
  3. A claude step only uses the inputs in CLAUDE_INPUTS, and its `claude_args` only the flags in CLAUDE_FLAGS, with exactly
     one --disallowedTools whose comma list holds Skill(<name>) for `payload` and every third-party skill in the manifests.
  4. A job with a claude step starts with: actions/checkout, then the agent egress lock (LOCK_ACTION); the claude step
     passes `path_to_claude_code_executable: ${{ steps.<lock id>.outputs.claude-path }}`.
  5. agent-manager.yml has exactly one claude step, and it keeps every deny in MANAGER_DENIES.
Usage: scripts/check-workflows.py [repo-root] [--manifest FILE ...]
"""
import glob
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

CLAUDE_ACTIONS = {"anthropics/claude-code-action@2dca132ff0e0c4094ce6048b422c6915a071210b"}
LOCK_ACTION = "./.github/actions/agent-egress-lock"
LOCAL_ACTIONS = {"./.github/actions/install-gitleaks", LOCK_ACTION}
CLAUDE_INPUTS = {"claude_code_oauth_token", "github_token", "prompt", "claude_args", "path_to_claude_code_executable"}
CLAUDE_FLAGS = {"--model", "--max-turns", "--permission-mode", "--allowedTools", "--disallowedTools", "--add-dir"}
MANAGER_DENIES = (
    "Skill(payload),Bash(npx:*),Bash(npm:*),Bash(yarn dlx:*),Bash(yarn create:*),Bash(node -e:*),Bash(node --eval:*),"
    "Bash(node -p:*),Bash(node --print:*),Bash(curl:*),Bash(wget:*),Bash(sudo:*),Bash(env:*),Bash(printenv:*),"
    "Bash(git push --force:*),Bash(git push -f:*),Bash(gh pr merge:*),Bash(gh api -X DELETE:*),Bash(gh secret:*),"
    "Bash(gh auth:*),Read(//proc/**),Read(//sys/**),Read(//home/runner/work/_temp/**),Read(//home/runner/.*/**),Read(//etc/**)"
).split(",")
CRED_RE = re.compile(
    r"secrets\s*(\.\s*|\[\s*['\"])[A-Za-z0-9_]*(claude|anthropic)|toJSON\s*\(\s*secrets\s*\)|ANTHROPIC_API_KEY|CLAUDE_CODE_OAUTH_TOKEN",
    re.I)
CLI_RE = re.compile(r"(^|[\s;&|(`$\"'/=])claude(\s|$|\")|claude-code|@anthropic-ai/", re.M)
LOCK_OUT_RE = re.compile(r"^\$\{\{\s*steps\.([A-Za-z0-9_-]+)\.outputs\.claude-path\s*\}\}$")


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


def err(msg):
    errors.append(msg)


def third_party(manifests):
    names = {"payload"}
    for m in manifests:
        if not os.path.isfile(m):
            continue
        for line in open(m, encoding="utf-8"):
            parts = line.split()
            if len(parts) >= 2 and not parts[0].startswith("#") and parts[1] == "third-party":
                names.add(parts[0])
    return names


def is_claude(step):
    return "claude-code" in str(step.get("uses", ""))


def check_claude_step(where, step, required, manager):
    uses = step.get("uses")
    if uses not in CLAUDE_ACTIONS:
        err(f"{where}: claude action must be one of {sorted(CLAUDE_ACTIONS)}, got {uses!r}")
    for key in step:
        if key not in {"id", "name", "uses", "with", "if", "env", "timeout-minutes", "continue-on-error"}:
            err(f"{where}: key {key!r} not allowed on a claude step")
    if CRED_RE.search(json.dumps(step.get("env", {}))):
        err(f"{where}: Claude/Anthropic credential in the claude step's env (use claude_code_oauth_token)")
    w = step.get("with") or {}
    if not isinstance(w, dict):
        err(f"{where}: 'with' must be a mapping")
        return
    for key, val in w.items():
        if key not in CLAUDE_INPUTS:
            err(f"{where}: input {key!r} not allowed (allowed: {', '.join(sorted(CLAUDE_INPUTS))})")
        if key != "claude_code_oauth_token" and CRED_RE.search(str(val)):
            err(f"{where}: Claude/Anthropic credential in input {key!r}")
    try:
        args = shlex.split(str(w.get("claude_args", "")))
    except ValueError as e:
        err(f"{where}: claude_args cannot be parsed ({e})")
        return
    flags, i, denies = [], 0, []
    while i < len(args):
        a = args[i]
        if a not in CLAUDE_FLAGS:
            err(f"{where}: claude_args flag {a!r} not allowed (allowed: {', '.join(sorted(CLAUDE_FLAGS))})")
            i += 1
            continue
        if i + 1 >= len(args) or args[i + 1].startswith("--"):
            err(f"{where}: claude_args flag {a} needs a value")
            i += 1
            continue
        flags.append(a)
        if a == "--disallowedTools":
            denies.append([x.strip() for x in args[i + 1].split(",")])
        i += 2
    if len(denies) != 1:
        err(f"{where}: needs exactly one --disallowedTools (found {len(denies)})")
        return
    have = set(denies[0])
    for n in sorted(required):
        if f"Skill({n})" not in have:
            err(f"{where}: --disallowedTools does not deny Skill({n})")
    if manager:
        for d in MANAGER_DENIES:
            if d not in have:
                err(f"agent-manager.yml: missing deny {d}")


def check_other(where, obj):
    text = json.dumps(obj)
    if CRED_RE.search(text):
        err(f"{where}: Claude/Anthropic credential outside a claude step's claude_code_oauth_token")
    if isinstance(obj, dict):
        run = obj.get("run")
        if run is not None and CLI_RE.search(str(run)):
            err(f"{where}: runs Claude outside the pinned claude-code-action")
        uses = obj.get("uses")
        if uses is not None:
            u = str(uses)
            if "claude-code" in u or "anthropic" in u.lower():
                err(f"{where}: runs Claude outside the pinned claude-code-action ({u})")
            if u.startswith("./") and u not in LOCAL_ACTIONS:
                err(f"{where}: local action not on the allow-list: {u}")
            if "/.github/workflows/" in u or u.startswith("docker://"):
                err(f"{where}: not allowed: {u}")


def check_file(path, required):
    name = os.path.basename(path)
    try:
        doc = yaml.load(open(path, encoding="utf-8"), Loader=UniqueKeyLoader)
    except yaml.YAMLError as e:
        err(f"{name}: not valid YAML or has duplicate keys ({str(e).splitlines()[0]})")
        return 0
    if not isinstance(doc, dict) or not isinstance(doc.get("jobs"), dict):
        err(f"{name}: no jobs mapping")
        return 0
    for key, val in doc.items():
        if key != "jobs":
            check_other(f"{name} {key}", val)
    claude_steps = 0
    for jname, job in doc["jobs"].items():
        jw = f"{name} job {jname}"
        if not isinstance(job, dict):
            err(f"{jw}: not a mapping")
            continue
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
            continue
        has_claude = any(isinstance(s, dict) and is_claude(s) for s in steps)
        lock_id = None
        if has_claude:
            ok = (len(steps) >= 2 and isinstance(steps[0], dict) and str(steps[0].get("uses", "")).startswith("actions/checkout@")
                  and isinstance(steps[1], dict) and steps[1].get("uses") == LOCK_ACTION)
            if not ok:
                err(f"{jw}: a job with a claude step must start with actions/checkout, then {LOCK_ACTION}")
            else:
                lock_id = steps[1].get("id")
                if not lock_id:
                    err(f"{jw}: the {LOCK_ACTION} step needs an id")
                if steps[1].get("if") is not None or steps[1].get("continue-on-error"):
                    err(f"{jw}: the {LOCK_ACTION} step may not have 'if' or 'continue-on-error'")
        for i, step in enumerate(steps, 1):
            sw = f"{jw} step {i}"
            if not isinstance(step, dict):
                err(f"{sw}: not a mapping")
                continue
            if is_claude(step):
                claude_steps += 1
                check_claude_step(sw, step, required, name == "agent-manager.yml")
                p = (step.get("with") or {}).get("path_to_claude_code_executable") if isinstance(step.get("with"), dict) else None
                m = LOCK_OUT_RE.match(str(p or ""))
                if not m or (lock_id and m.group(1) != lock_id):
                    err(f"{sw}: path_to_claude_code_executable must be ${{{{ steps.{lock_id or '<lock id>'}.outputs.claude-path }}}}")
            else:
                check_other(sw, step)
    return claude_steps


def main(argv):
    root, manifests, rest = None, [], list(argv)
    while rest:
        a = rest.pop(0)
        if a == "--manifest" and rest:
            manifests.append(rest.pop(0))
        elif root is None and not a.startswith("--"):
            root = a
        else:
            print(f"ERROR: bad argument {a!r}")
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
    manifests.append(os.path.join(root, ".claude", "skills", "manifest.txt"))
    required = third_party(manifests)
    counts = {os.path.basename(f): check_file(f, required) for f in files}
    if counts.get("agent-manager.yml", 0) != 1:
        err(f"expected exactly one claude step in agent-manager.yml (found {counts.get('agent-manager.yml', 0)})")
    for e in errors:
        print(f"ERROR: {e}")
    if errors:
        return 1
    print(f"Workflow denies OK (Skill denies: {', '.join(sorted(required))})")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
