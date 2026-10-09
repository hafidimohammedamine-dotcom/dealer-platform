#!/usr/bin/env python3
"""Checks the agent workflows (founder-owned). Parses every workflow as YAML and fails closed.

Rules:
  1. Claude runs only through the pinned claude-code-action (CLAUDE_ACTIONS). No other step may run the claude CLI, the
     pre-installed binary (outputs.claude-path, .local/bin/claude) or @anthropic-ai/..., and no reusable workflow,
     container or service job, Docker action or local action outside LOCAL_ACTIONS is used.
  2. `secrets` is only ever used as `secrets.<NAME>` (no secrets[...], toJSON(secrets) or the whole object), and a
     Claude/Anthropic credential (a secret named *CLAUDE*/*ANTHROPIC*, ANTHROPIC_API_KEY, CLAUDE_CODE_OAUTH_TOKEN) appears
     only in a claude step's `claude_code_oauth_token`.
  3. A claude step uses only the inputs in CLAUDE_INPUTS (allowed_bots only as in ALLOWED_BOTS), and `claude_args` only the
     flags in CLAUDE_FLAGS, with exactly one --disallowedTools holding Skill(<name>) for `payload` and every third-party
     skill in the manifests.
  4. A workflow with a claude step is never triggered by pull_request (PR code must not run next to a Claude token). Its
     claude jobs start with actions/checkout of the default branch (`ref:` main or the default-branch expression; the base
     branch for pull_request_target) with persist-credentials: false, then the agent egress lock (LOCK_ACTION, with an id
     and nothing else), and the claude step runs `${{ steps.<lock id>.outputs.claude-path }}`.
  5. agent-manager.yml has exactly one claude step, and it keeps every deny in MANAGER_DENIES.
Usage: scripts/check-workflows.py [repo-root] [--manifest FILE ...]   (an explicit --manifest must exist)
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
CLAUDE_INPUTS = {"claude_code_oauth_token", "github_token", "prompt", "claude_args", "path_to_claude_code_executable",
                 "allowed_bots"}
ALLOWED_BOTS = {"agent-manager.yml": "github-actions"}  # instant fix rounds from review.yml; GitHub's own bot only
CLAUDE_FLAGS = {"--model", "--max-turns", "--permission-mode", "--allowedTools", "--disallowedTools", "--add-dir"}
CLAUDE_STEP_KEYS = {"id", "name", "uses", "with", "if", "env", "timeout-minutes", "continue-on-error"}
DEFAULT_REFS = {"main", "${{ github.event.repository.default_branch }}"}
BASE_REF = "${{ github.base_ref }}"
MANAGER_DENIES = (
    "Skill(payload),Bash(npx:*),Bash(npm:*),Bash(yarn dlx:*),Bash(yarn create:*),Bash(node -e:*),Bash(node --eval:*),"
    "Bash(node -p:*),Bash(node --print:*),Bash(curl:*),Bash(wget:*),Bash(sudo:*),Bash(env:*),Bash(printenv:*),"
    "Bash(git push --force:*),Bash(git push -f:*),Bash(gh pr merge:*),Bash(gh api -X DELETE:*),Bash(gh secret:*),"
    "Bash(gh auth:*),Read(//proc/**),Read(//sys/**),Read(//home/runner/work/_temp/**),Read(//home/runner/.*/**),Read(//etc/**)"
).split(",")
SECRETS_TOKEN = re.compile(r"\bsecrets\b(\s*\.\s*([A-Za-z_][A-Za-z0-9_]*))?")
CLAUDE_NAME = re.compile(r"claude|anthropic", re.I)
CRED_ENV = re.compile(r"ANTHROPIC_API_KEY|CLAUDE_CODE_OAUTH_TOKEN")
CLI_RE = re.compile(r"(^|[\s;&|(`$\"'/=])claude(\s|$|\")|claude-code|@anthropic-ai/|outputs\.claude-path|\.local/bin/claude", re.M)
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
        for line in open(m, encoding="utf-8"):
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


def parse_claude_args(where, text):
    """Returns the --disallowedTools items, or None after reporting an error."""
    try:
        args = shlex.split(text)
    except ValueError as e:
        err(f"{where}: claude_args cannot be parsed ({e})")
        return None
    denies, i = [], 0
    while i < len(args):
        a = args[i]
        if a not in CLAUDE_FLAGS:
            err(f"{where}: claude_args flag {a!r} not allowed (allowed: {', '.join(sorted(CLAUDE_FLAGS))})")
            i += 1
        elif i + 1 >= len(args) or args[i + 1].startswith("--"):
            err(f"{where}: claude_args flag {a} needs a value")
            i += 1
        else:
            if a == "--disallowedTools":
                denies.append([x.strip() for x in args[i + 1].split(",")])
            i += 2
    if len(denies) != 1:
        err(f"{where}: needs exactly one --disallowedTools (found {len(denies)})")
        return None
    return set(denies[0])


def check_claude_step(fname, where, step, required, lock_id):
    if step.get("uses") not in CLAUDE_ACTIONS:
        err(f"{where}: claude action must be one of {sorted(CLAUDE_ACTIONS)}, got {step.get('uses')!r}")
    for key in step:
        if key not in CLAUDE_STEP_KEYS:
            err(f"{where}: key {key!r} not allowed on a claude step")
    for p in sorted(set(secrets_problems(json.dumps(step.get("env", {}))))):
        err(f"{where}: {p} in the claude step's env (use claude_code_oauth_token)")
    w = step.get("with") or {}
    if not isinstance(w, dict):
        err(f"{where}: 'with' must be a mapping")
        return
    for key, val in w.items():
        if key not in CLAUDE_INPUTS:
            err(f"{where}: input {key!r} not allowed (allowed: {', '.join(sorted(CLAUDE_INPUTS))})")
        elif key == "allowed_bots" and ALLOWED_BOTS.get(fname) != str(val):
            err(f"{where}: allowed_bots may only be {ALLOWED_BOTS} (this file: {val!r})")
        for p in sorted(set(secrets_problems(str(val), allow_claude=(key == "claude_code_oauth_token")))):
            err(f"{where}: {p} in input {key!r}")
    m = LOCK_OUT_RE.match(str(w.get("path_to_claude_code_executable", "")))
    if not m or (lock_id and m.group(1) != lock_id):
        err(f"{where}: path_to_claude_code_executable must be ${{{{ steps.{lock_id or '<lock id>'}.outputs.claude-path }}}}")
    have = parse_claude_args(where, str(w.get("claude_args", "")))
    if have is None:
        return
    for n in sorted(required):
        if f"Skill({n})" not in have:
            err(f"{where}: --disallowedTools does not deny Skill({n})")
    if fname == "agent-manager.yml":
        for d in MANAGER_DENIES:
            if d not in have:
                err(f"agent-manager.yml: missing deny {d}")


def check_claude_job_start(jw, steps, triggers):
    """Rule 4: checkout of the default (or base) branch without credentials, then the lock. Returns the lock id."""
    first = steps[0] if steps and isinstance(steps[0], dict) else {}
    second = steps[1] if len(steps) > 1 and isinstance(steps[1], dict) else {}
    if not str(first.get("uses", "")).startswith("actions/checkout@") or second.get("uses") != LOCK_ACTION:
        err(f"{jw}: a job with a claude step must start with actions/checkout, then {LOCK_ACTION}")
        return None
    w = first.get("with") if isinstance(first.get("with"), dict) else {}
    ok_refs = DEFAULT_REFS | ({BASE_REF} if triggers == {"pull_request_target"} else set())
    if str(w.get("ref", "")) not in ok_refs:
        err(f"{jw}: the checkout needs an explicit ref of the default branch ({' or '.join(sorted(ok_refs))}), never the PR's code")
    if w.get("persist-credentials") is not False:
        err(f"{jw}: the checkout needs persist-credentials: false")
    extra = set(second) - {"id", "uses", "name"}
    if extra:
        err(f"{jw}: the {LOCK_ACTION} step may only have id/uses/name (found {', '.join(sorted(extra))})")
    if not second.get("id"):
        err(f"{jw}: the {LOCK_ACTION} step needs an id")
    return second.get("id")


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
    has_claude = any(isinstance(s, dict) and is_claude(s) for s in steps)
    lock_id = check_claude_job_start(jw, steps, triggers) if has_claude else None
    if has_claude and any(str(k).startswith("AGENT_LOCK_") for k in (job.get("env") or {}) if isinstance(job.get("env"), dict)):
        err(f"{jw}: AGENT_LOCK_* variables (lock test hooks) are not allowed in a job with a claude step")
    count = 0
    for i, step in enumerate(steps, 1):
        sw = f"{jw} step {i}"
        if not isinstance(step, dict):
            err(f"{sw}: not a mapping")
        elif is_claude(step):
            count += 1
            check_claude_step(fname, sw, step, required, lock_id)
        else:
            check_other(sw, step)
    return count


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
    triggers = triggers_of(doc)
    wenv = doc.get("env") if isinstance(doc.get("env"), dict) else {}
    if any(str(k).startswith("AGENT_LOCK_") for k in wenv):
        err(f"{name}: AGENT_LOCK_* variables (lock test hooks) are not allowed at workflow level")
    count = sum(check_job(name, jn, job, required, triggers) for jn, job in doc["jobs"].items())
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
