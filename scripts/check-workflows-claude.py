"""Rules for jobs with a claude-code-action step (founder-owned). Loaded by scripts/check-workflows.py after
scripts/check-workflows-lib.py (policy values, err(), secrets_problems(), is_claude()). Rules and messages:
docs/runbooks/ci-guards.md."""
import json
import re
import shlex

import check_workflows_lib as core  # noqa: E402 - loaded into sys.modules by check-workflows.py before this module

LOCK_OUT_RE = {key: re.compile(r"^\$\{\{\s*steps\.([A-Za-z0-9_-]+)\.outputs\." + out + r"\s*\}\}$")
               for key, out in (("path_to_claude_code_executable", "claude-path"), ("path_to_bun_executable", "bun-path"))}
PR_DATA = re.compile(r"/tmp/pr(?![\w-])|pull_request\.head|head_ref|merge_commit_sha|refs/pull/|\bpull/|gh\s+pr\s+checkout|"
                     r"event\.issue\.number")
GIT_MOVE = re.compile(r"\bgit\b(?:\s+-{1,2}[\w-]+(?:[= ]\S+)?)*\s+(fetch|checkout|switch|worktree|pull|clone|reset|restore|"
                      r"submodule)\b")
LATE_IF = re.compile(r"always\(\)|failure\(\)|cancelled\(\)")
PINNED = core.PINNED


def check_flag_value(fname, where, flag, value):
    P = core.P
    if flag == "--permission-mode" and not (value == "bypassPermissions" and fname == P["manager"]):
        core.err(f"{where}: --permission-mode {value} not allowed (only bypassPermissions, only in {P['manager']})")
    if flag == "--add-dir" and value not in P["add_dirs"].get(fname, []):
        core.err(f"{where}: --add-dir {value} not allowed (allowed: {P['add_dirs']})")
    if flag == "--allowedTools" and fname != P["manager"]:
        ok = set(P["read_only_tools"]) | set(P["read_only_bash"]) | set(P["extra_tools"].get(fname, []))
        for t in (x.strip() for x in value.split(",")):
            if t not in ok:
                core.err(f"{where}: --allowedTools item {t!r} not allowed outside {P['manager']} (read-only tools only)")


def parse_claude_args(fname, where, text):
    """Returns the --disallowedTools items, or None after reporting an error."""
    try:
        args = shlex.split(text)
    except ValueError as e:
        core.err(f"{where}: claude_args cannot be parsed ({e})")
        return None
    denies, i = [], 0
    while i < len(args):
        a = args[i]
        if a not in core.P["claude_flags"]:
            core.err(f"{where}: claude_args flag {a!r} not allowed (allowed: {', '.join(sorted(core.P['claude_flags']))})")
            i += 1
        elif i + 1 >= len(args) or args[i + 1].startswith("--"):
            core.err(f"{where}: claude_args flag {a} needs a value")
            i += 1
        else:
            check_flag_value(fname, where, a, args[i + 1])
            if a == "--disallowedTools":
                denies.append([x.strip() for x in args[i + 1].split(",")])
            i += 2
    if len(denies) != 1:
        core.err(f"{where}: needs exactly one --disallowedTools (found {len(denies)})")
        return None
    return set(denies[0])


def check_inputs(fname, where, w, lock_id):
    P = core.P
    for key, val in w.items():
        if key not in P["claude_inputs"]:
            core.err(f"{where}: input {key!r} not allowed (allowed: {', '.join(sorted(P['claude_inputs']))})")
        elif key == "allowed_bots" and P["allowed_bots"].get(fname) != str(val):
            core.err(f"{where}: allowed_bots may only be {P['allowed_bots']} (this file: {val!r})")
        for p in sorted(set(core.secrets_problems(str(val), allow_claude=(key == "claude_code_oauth_token")))):
            core.err(f"{where}: {p} in input {key!r}")
    for key, rx in LOCK_OUT_RE.items():  # the binaries the lock installed and checked, never a download inside the action
        m = rx.match(str(w.get(key, "")))
        if not m or (lock_id and m.group(1) != lock_id):
            out = "claude-path" if "claude" in key else "bun-path"
            core.err(f"{where}: {key} must be ${{{{ steps.{lock_id or '<lock id>'}.outputs.{out} }}}}")


def check_claude_step(fname, where, step, required, lock_id):
    P = core.P
    if step.get("uses") not in P["claude_actions"]:
        core.err(f"{where}: claude action must be one of {sorted(P['claude_actions'])}, got {step.get('uses')!r}")
    for key in step:
        if key not in P["claude_step_keys"]:
            core.err(f"{where}: key {key!r} not allowed on a claude step")
    if step.get("env"):
        core.err(f"{where}: env not allowed on a claude step (job env names: {', '.join(sorted(P['job_env']))})")
    if LATE_IF.search(str(step.get("if", ""))):
        core.err(f"{where}: a claude step may not run after a failure (no always()/failure()/cancelled() in its if)")
    w = step.get("with") or {}
    if not isinstance(w, dict):
        core.err(f"{where}: 'with' must be a mapping")
        return
    check_inputs(fname, where, w, lock_id)
    have = parse_claude_args(fname, where, str(w.get("claude_args", "")))
    if have is None:
        return
    for n in sorted(required):
        if f"Skill({n})" not in have:
            core.err(f"{where}: --disallowedTools does not deny Skill({n})")
    if fname == P["manager"]:
        for d in P["manager_denies"]:
            if d not in have:
                core.err(f"{fname}: missing deny {d}")


def check_checkout(where, step, ok_refs):
    w = step.get("with") if isinstance(step.get("with"), dict) else {}
    extra = set(w) - set(core.P["checkout_keys"])
    if extra:
        core.err(f"{where}: checkout input(s) {', '.join(sorted(extra))} not allowed in a claude job (only {', '.join(core.P['checkout_keys'])})")
    if str(w.get("ref", "")) not in ok_refs:
        core.err(f"{where}: the checkout needs an explicit ref of the default branch ({' or '.join(sorted(ok_refs))}), never the PR's code")
    if w.get("persist-credentials") is not False:
        core.err(f"{where}: the checkout needs persist-credentials: false")


def check_job_start(jw, steps, ok_refs):
    """Checkout of the default (or base) branch without credentials, then the bare lock step. Returns the lock id."""
    first = steps[0] if steps and isinstance(steps[0], dict) else {}
    second = steps[1] if len(steps) > 1 and isinstance(steps[1], dict) else {}
    if not str(first.get("uses", "")).startswith("actions/checkout@") or second.get("uses") != core.P["lock_action"]:
        core.err(f"{jw}: a job with a claude step must start with actions/checkout, then {core.P['lock_action']}")
        return None
    extra = set(second) - {"id", "uses", "name"}
    if extra:
        core.err(f"{jw}: the {core.P['lock_action']} step may only have id/uses/name (found {', '.join(sorted(extra))})")
    if not second.get("id"):
        core.err(f"{jw}: the {core.P['lock_action']} step needs an id")
    return second.get("id")


def check_job_settings(fname, jw, job):
    """Env allow-list with the subprocess scrub on, permissions allow-list (some scopes only in listed files), runner, no
    defaults."""
    P = core.P
    env = job.get("env") if isinstance(job.get("env"), dict) else {}
    for k in env:
        if k not in P["job_env"]:
            core.err(f"{jw}: env {k!r} not allowed in a job with a claude step (allowed: {', '.join(sorted(P['job_env']))})")
    if str(env.get("CLAUDE_CODE_SUBPROCESS_ENV_SCRUB", "")) != "1":
        core.err(f'{jw}: needs env CLAUDE_CODE_SUBPROCESS_ENV_SCRUB: "1" (tool subprocesses must not see the Claude token)')
    if job.get("runs-on") != P["runs_on"]:
        core.err(f"{jw}: runs-on must be {P['runs_on']}")
    if "defaults" in job:
        core.err(f"{jw}: 'defaults' not allowed in a job with a claude step")
    perms = job.get("permissions", {})
    if not isinstance(perms, dict):
        core.err(f"{jw}: permissions must be a mapping of scopes (no read-all/write-all)")
        perms = {}
    for k, v in perms.items():
        scope_ok = k in P["permission_scopes"] or fname in P["per_file_permission_scopes"].get(k, [])
        if not scope_ok or v not in P["permission_values"]:
            core.err(f"{jw}: permission {k}: {v} not allowed (scopes {', '.join(P['permission_scopes'])}; "
                     f"per file {P['per_file_permission_scopes']}; read/write/none)")


def check_other_steps(jw, steps, claude_at, ok_refs):
    """Steps around the claude step: pinned actions, default-branch checkouts, PR data only in the reviewed prepare step,
    and post steps that check their pinned files before running repo scripts."""
    P = core.P
    for i, step in enumerate(steps, 1):
        if not isinstance(step, dict) or core.is_claude(step) or i <= 2:
            continue
        sw = f"{jw} step {i}"
        uses = str(step.get("uses", ""))
        if uses and not uses.startswith("./") and not PINNED.match(uses):
            core.err(f"{sw}: action must be pinned to a full commit SHA: {uses}")
        if uses.startswith("actions/checkout@"):
            check_checkout(sw, step, ok_refs)
        for key in ("working-directory", "shell"):
            if key in step:
                core.err(f"{sw}: '{key}' not allowed in a job with a claude step")
        body = json.dumps({k: v for k, v in step.items() if k not in ("if", "name")})
        reviewed = str(step.get("run", "")).strip() in P["pr_data_runs"]
        if PR_DATA.search(body) and not reviewed:
            core.err(f"{sw}: runs or checks out PR code in a job with a claude step (only the reviewed prepare step may touch /tmp/pr)")
        m = GIT_MOVE.search(str(step.get("run", "")))
        if m and not reviewed:
            core.err(f"{sw}: 'git {m.group(1)}' not allowed in a job with a claude step (the checkout must stay on the default branch)")
        if claude_at and i > claude_at:
            run = str(step.get("run", ""))
            if uses.startswith("./"):
                core.err(f"{sw}: no local action after the claude step (its files could have changed)")
            m = re.search(r"scripts/|/tmp/gitleaks", run)
            if m and P["post_pin_check"] not in run[:m.start()]:
                core.err(f"{sw}: a step after the claude step must check its pinned files ({P['post_pin_check']}) before running repo scripts")


def check_job(fname, jw, job, steps, required, triggers):
    """All rules for a job that has a claude step. Returns the number of claude steps."""
    P = core.P
    ok_refs = set(P["default_refs"]) | ({P["base_ref"]} if triggers == {"pull_request_target"} else set())
    lock_id = check_job_start(jw, steps, ok_refs)
    if lock_id is not None:
        check_checkout(f"{jw} step 1", steps[0], ok_refs)
        if not PINNED.match(str(steps[0].get("uses", ""))):
            core.err(f"{jw} step 1: action must be pinned to a full commit SHA: {steps[0].get('uses')}")
    check_job_settings(fname, jw, job)
    claude_at = next((i for i, s in enumerate(steps, 1) if isinstance(s, dict) and core.is_claude(s)), 0)
    check_other_steps(jw, steps, claude_at, ok_refs)
    if fname == P["manager"]:
        guard = [i for i, s in enumerate(steps, 1) if isinstance(s, dict) and str(s.get("run", "")).startswith(P["manager_token_guard"])]
        if not guard or guard[0] > claude_at:
            core.err(f"{jw}: needs a step running '{P['manager_token_guard']} ...' before the claude step")
    count = 0
    for i, step in enumerate(steps, 1):
        if isinstance(step, dict) and core.is_claude(step):
            count += 1
            check_claude_step(fname, f"{jw} step {i}", step, required, lock_id)
            check_tag_mode(f"{jw} step {i}", job, step, triggers)
    return count


def check_tag_mode(where, job, step, triggers):
    """A claude step without a prompt runs in tag mode, which checks out an open PR's head itself; the action restores only
    the top-level CLAUDE.md/.claude/.mcp.json from the base branch, so nested rule files of the PR would load. Tag mode is
    allowed only on issue events, with the job skipping comments on PRs."""
    w = step.get("with") if isinstance(step.get("with"), dict) else {}
    if "prompt" in w:
        return
    extra = triggers - set(core.P["tag_mode_triggers"])
    if extra:
        core.err(f"{where}: a claude step without a prompt (tag mode) may run only on {', '.join(core.P['tag_mode_triggers'])} "
                 f"(found {', '.join(sorted(extra))})")
    if core.P["tag_mode_job_if"] not in str(job.get("if", "")):
        core.err(f"{where}: a claude step without a prompt (tag mode) needs the job if to contain "
                 f"'{core.P['tag_mode_job_if']}' (it would check out the PR's code)")
