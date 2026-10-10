#!/usr/bin/env python3
"""Checks the agent workflows and local actions; fails closed. Shared state: scripts/check-workflows-lib.py; rules for jobs
with a claude step: scripts/check-workflows-claude.py; identity rules: scripts/check-workflows-people.py. Rules and messages:
docs/runbooks/workflow-checker.md."""
import glob
import importlib.util
import json
import os
import re
import sys

try:
    import yaml
except ImportError:  # fail closed
    print("ERROR: PyYAML is missing; run through the venv from scripts/check-python-deps.sh (pinned in scripts/check-python-requirements.txt)")
    sys.exit(1)

HERE = os.path.dirname(os.path.abspath(__file__))


def _load(name, filename):
    """Loads a founder-owned module that sits next to this file (python3 -I does not add this folder to sys.path)."""
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, filename))
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


LIB = _load("check_workflows_lib", "check-workflows-lib.py")
CLAUDE = _load("check_workflows_claude", "check-workflows-claude.py")
PEOPLE = _load("check_workflows_people", "check-workflows-people.py")
P, err, errors, is_claude, secrets_problems = LIB.P, LIB.err, LIB.errors, LIB.is_claude, LIB.secrets_problems
LOCAL_ACTIONS, MANAGER = set(P["local_actions"]), P["manager"]
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


def third_party(csv):
    """Skill names to deny: always_denied_skills plus the third-party skill names check-workflows.sh read from the
    manifests with scripts/check-skills-lib.sh (CW_THIRD_PARTY, comma-separated)."""
    return set(P["always_denied_skills"]) | {n for n in csv.split(",") if n}


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


def check_pins_position(fname, jw, steps):
    """Every job outside pins_exempt runs the exact pin step right after its first checkout (before the lock, before any
    repo script): a push that changed a pinned file fails the job before any secret or sudo is used."""
    if fname in P["pins_exempt"] or not isinstance(steps, list):
        return
    at = next((i for i, st in enumerate(steps) if isinstance(st, dict) and str(st.get("uses", "")).startswith("actions/checkout@")), None)
    if at is None:
        err(f"{jw}: no actions/checkout step (every job outside pins_exempt checks out and pins the files it runs)")
        return
    nxt = steps[at + 1] if at + 1 < len(steps) else None
    if not LIB.names_pins_step(nxt):
        err(f"{jw}: the step after the checkout must be the pin step '{P['pins_step_name']}'")
        return
    LIB.check_pins_step(fname, f"{jw} step {at + 2}", nxt)


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
    LIB.check_permissions(fname, jw, job.get("permissions"), triggers)
    check_pins_position(fname, jw, job.get("steps") or [])
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
    PEOPLE.check_token_guard(fname, jw, job, steps)
    if any(isinstance(s, dict) and is_claude(s) for s in steps):
        return CLAUDE.check_job(fname, jw, job, steps, required, triggers)
    return 0


def check_stop_list(root, files):
    """The workflows the main guard cancels and disables after a bad push (policy `stop_workflows`) are every workflow
    but main-guard.yml that holds a secret or a write scope, and both copies of that list - the `for w in ...` line of
    main-guard.yml's fallback step and the MAIN_GUARD_WORKFLOWS default in scripts/check-main-push.sh - say exactly that."""
    want = P["stop_workflows"]
    skip = {"main-guard.yml", *P["checker_test_fixtures"]}   # the fixtures scripts/check-workflows*.test.sh add next to the real files
    holding = sorted(os.path.basename(f) for f in files if os.path.basename(f) not in skip
                     and re.search(r"secrets\.|:\s*write\b", open(f, encoding="utf-8").read()))
    if sorted(want) != holding:
        err(f"stop_workflows in the policy must be every workflow holding a secret or a write scope (except main-guard.yml): "
            f"policy {sorted(want)}, workflows {holding}")
    joined = " ".join(want)
    wf = os.path.join(root, ".github", "workflows", "main-guard.yml")
    if os.path.isfile(wf):
        with open(wf, encoding="utf-8") as fh:
            m = re.search(r"for w in ([^;\n]+); do", fh.read())
        if not m or m.group(1).split() != want:
            err(f"main-guard.yml: the fallback step's 'for w in ...' list must be exactly the policy's stop_workflows ({joined})")
    sc = os.path.join(root, "scripts", "check-main-push.sh")
    if os.path.isfile(sc):
        with open(sc, encoding="utf-8") as fh:
            m = re.search(r"MAIN_GUARD_WORKFLOWS:-([^}]+)\}", fh.read())
        if not m or m.group(1).split() != want:
            err(f"scripts/check-main-push.sh: the MAIN_GUARD_WORKFLOWS default must be exactly the policy's stop_workflows ({joined})")


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
            LIB.require_pinned(f"{name} step {i}", u)


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


def check_file(path, required, accounts):
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
    PEOPLE.check_workflow_env(name, doc)
    PEOPLE.check_file_ifs(name, doc, accounts)
    PEOPLE.check_after_shift(name, doc)
    PEOPLE.check_rerun_guard(name, doc)
    triggers = triggers_of(doc)
    LIB.check_permissions(name, name, doc.get("permissions"), triggers)
    count = sum(check_job(name, jn, job, required, triggers) for jn, job in doc["jobs"].items())
    if count and doc.get("env"):
        err(f"{name}: no workflow-level env in a workflow with a claude step (use the job's env)")
    for t in sorted(triggers & {"pull_request", "workflow_run", "push"}) if count else []:
        err(f"{name}: a workflow with a claude step must not run on {t} (PR code, its artifacts or a fresh push next to a Claude token)")
    return count


def main(argv):
    """argv: [repo-root]; the manifests and accounts come pre-parsed from scripts/check-workflows.sh (environment)."""
    bad = [a for a in argv if a.startswith("--")] or argv[1:]
    if bad:
        print(f"ERROR: bad argument {bad[0]!r} (run through scripts/check-workflows.sh)")
        return 1
    if "CW_ACCOUNT_ROWS" not in os.environ or "CW_THIRD_PARTY" not in os.environ:
        print("ERROR: run through scripts/check-workflows.sh (it reads the manifests and .github/accounts.txt)")
        return 1
    root = argv[0] if argv else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    d = os.path.join(root, ".github", "workflows")
    if not os.path.isdir(d):
        print(f"ERROR: no workflows folder {d}")
        return 1
    files = sorted(glob.glob(os.path.join(d, "*.yml")) + glob.glob(os.path.join(d, "*.yaml")))
    if not files:
        print(f"ERROR: no workflow files in {d}")
        return 1
    LIB.check_pins_file(root)
    required = third_party(os.environ["CW_THIRD_PARTY"])
    accounts = LIB.accounts_from_rows(os.environ["CW_ACCOUNT_ROWS"])
    counts = {os.path.basename(f): check_file(f, required, accounts) for f in files}
    check_actions(root)
    check_stop_list(root, files)
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
