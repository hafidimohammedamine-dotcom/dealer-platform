#!/usr/bin/env python3
"""Checks the agent workflows; fails closed. Rules and messages: docs/runbooks/ci-guards.md, "Workflow denies OK"."""
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

try:  # founder-owned policy data next to this file
    P = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "check-workflows-policy.json"), encoding="utf-8"))
except (OSError, ValueError) as e:
    print(f"ERROR: cannot read check-workflows-policy.json ({e})")
    sys.exit(1)
CLAUDE_ACTIONS, LOCK_ACTION, LOCAL_ACTIONS = set(P["claude_actions"]), P["lock_action"], set(P["local_actions"])
CLAUDE_INPUTS, ALLOWED_BOTS, CLAUDE_FLAGS = set(P["claude_inputs"]), P["allowed_bots"], set(P["claude_flags"])
CLAUDE_STEP_KEYS, DEFAULT_REFS, BASE_REF, MANAGER = set(P["claude_step_keys"]), set(P["default_refs"]), P["base_ref"], P["manager"]
READ_ONLY_TOOLS, READ_ONLY_BASH, ADD_DIRS = set(P["read_only_tools"]), set(P["read_only_bash"]), P["add_dirs"]
JOB_ENV, MANAGER_DENIES = set(P["job_env"]), P["manager_denies"]
PR_CODE = re.compile(r"github\.event\.pull_request\.head|github\.head_ref|(cd|--cwd|-C)\s+/tmp/pr\b|/tmp/pr/\S+\.(sh|js|mjs|cjs|ts|py)\b")
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


def check_flag_value(fname, where, flag, value):
    """Per-workflow limits on what claude_args may grant."""
    if flag == "--permission-mode" and not (value == "bypassPermissions" and fname == MANAGER):
        err(f"{where}: --permission-mode {value} not allowed (only bypassPermissions, only in {MANAGER})")
    if flag == "--add-dir" and ADD_DIRS.get(fname) != value:
        err(f"{where}: --add-dir {value} not allowed (allowed: {ADD_DIRS})")
    if flag == "--allowedTools" and fname != MANAGER:
        for t in (x.strip() for x in value.split(",")):
            if t not in READ_ONLY_TOOLS and t not in READ_ONLY_BASH:
                err(f"{where}: --allowedTools item {t!r} not allowed outside {MANAGER} (read-only tools only)")


def parse_claude_args(fname, where, text):
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
            check_flag_value(fname, where, a, args[i + 1])
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
    if step.get("env"):
        err(f"{where}: env not allowed on a claude step (job env names: {', '.join(sorted(JOB_ENV))})")
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
    have = parse_claude_args(fname, where, str(w.get("claude_args", "")))
    if have is None:
        return
    for n in sorted(required):
        if f"Skill({n})" not in have:
            err(f"{where}: --disallowedTools does not deny Skill({n})")
    if fname == MANAGER:
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


def check_claude_job_rules(jw, job, steps):
    """Env allow-list, subprocess scrub on, no PR code, extra checkouts only of the default branch."""
    env = job.get("env") if isinstance(job.get("env"), dict) else {}
    for k in env:
        if k not in JOB_ENV:
            err(f"{jw}: env {k!r} not allowed in a job with a claude step (allowed: {', '.join(sorted(JOB_ENV))})")
    if str(env.get("CLAUDE_CODE_SUBPROCESS_ENV_SCRUB", "")) != "1":
        err(f'{jw}: needs env CLAUDE_CODE_SUBPROCESS_ENV_SCRUB: "1" (tool subprocesses must not see the Claude token)')
    for i, step in enumerate(steps[2:], 3):
        if not isinstance(step, dict) or is_claude(step):
            continue
        if str(step.get("uses", "")).startswith("actions/checkout@"):
            ref = str((step.get("with") or {}).get("ref", "")) if isinstance(step.get("with"), dict) else ""
            if ref not in DEFAULT_REFS:
                err(f"{jw} step {i}: a later checkout in a claude job must also use the default branch")
        if PR_CODE.search(json.dumps([step.get("run"), step.get("with")])):
            err(f"{jw} step {i}: runs or checks out PR code in a job with a claude step")


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
    if has_claude:
        check_claude_job_rules(jw, job, steps)
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
