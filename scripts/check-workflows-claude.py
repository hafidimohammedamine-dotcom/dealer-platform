"""Rules for jobs with a claude-code-action step (founder-owned). Loaded by scripts/check-workflows.py after
scripts/check-workflows-lib.py (policy values, err(), secrets_problems(), is_claude()). Rules and messages:
docs/runbooks/workflow-checker.md."""
import json
import re
import shlex

import check_workflows_lib as core  # loaded into sys.modules by check-workflows.py before this module

LOCK_OUTPUTS = {"path_to_claude_code_executable": "claude-path", "path_to_bun_executable": "bun-path"}   # action input -> lock output
LOCK_OUT_RE = {key: re.compile(r"^\$\{\{\s*steps\.([A-Za-z0-9_-]+)\.outputs\." + out + r"\s*\}\}$") for key, out in LOCK_OUTPUTS.items()}
PR_DATA = re.compile(r"/tmp/pr(?![\w-])|pull_request\.head|head_ref|merge_commit_sha|refs/pull/|\bpull/|gh\s+pr\s+checkout|"
                     r"event\.issue\.number")
GIT_MOVE = re.compile(r"\bgit\b(?:\s+-{1,2}[\w-]+(?:[= ]\S+)?)*\s+(fetch|checkout|switch|worktree|pull|clone|reset|restore|"
                      r"submodule)\b")
LATE_IF = re.compile(r"always\(\)|failure\(\)|cancelled\(\)")


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
    for key, val in P["claude_inputs_required"].items():  # e.g. no post-session step of the action may hold a token
        if str(w.get(key, "")) != val:
            core.err(f"{where}: input {key!r} must be {val!r} (the action's 'Post buffered inline comments' step would otherwise run after the session with the GitHub token)")
    for key, rx in LOCK_OUT_RE.items():  # the binaries the lock installed and checked, never a download inside the action
        m = rx.match(str(w.get(key, "")))
        if not m or (lock_id and m.group(1) != lock_id):
            core.err(f"{where}: {key} must be ${{{{ steps.{lock_id or '<lock id>'}.outputs.{LOCK_OUTPUTS[key]} }}}}")


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
    want_token = P["claude_github_token"].get(fname, P["claude_github_token"]["default"])
    if str(w.get("github_token", "")) != want_token:
        core.err(f"{where}: github_token must be exactly {want_token} (without it the action swaps the job's OIDC token for "
                 f"an app token the job's permissions do not limit)")
    have = parse_claude_args(fname, where, str(w.get("claude_args", "")))
    if have is None:
        return
    for n in sorted(required):
        if f"Skill({n})" not in have:
            core.err(f"{where}: --disallowedTools does not deny Skill({n})")
    for d in P["claude_denies"]:   # every Claude step: no web tools, no reads of process/runner internals
        if d not in have:
            core.err(f"{where}: --disallowedTools does not deny {d} (every claude step must)")
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


def is_main_head_step(step):
    """The pinned check that the default branch's head passed the main guard (only name and run)."""
    return isinstance(step, dict) and str(step.get("run", "")).strip() == core.P["main_head_guard"] and not (set(step) - {"name", "run"})


def check_job_start(fname, jw, steps):
    """Checkout of the default (or base) branch without credentials, the pin step, the main-head check (the checked-out
    head passed the main guard: no unchecked push runs next to a Claude token), then the bare lock step. Returns the lock id."""
    first = steps[0] if steps and isinstance(steps[0], dict) else {}
    pins = steps[1] if len(steps) > 1 and isinstance(steps[1], dict) else {}
    head = steps[2] if len(steps) > 2 and isinstance(steps[2], dict) else {}
    second = steps[3] if len(steps) > 3 and isinstance(steps[3], dict) else {}
    if (not str(first.get("uses", "")).startswith("actions/checkout@") or not core.is_pins_step(pins, fname)
            or not is_main_head_step(head) or second.get("uses") != core.P["lock_action"]):
        core.err(f"{jw}: a job with a claude step must start with actions/checkout, the pin step, '{core.P['main_head_guard']}' "
                 f"(name and run only), then {core.P['lock_action']}")
        return None
    extra = set(second) - {"id", "uses", "name"}
    if extra:
        core.err(f"{jw}: the {core.P['lock_action']} step may only have id/uses/name (found {', '.join(sorted(extra))})")
    if not second.get("id"):
        core.err(f"{jw}: the {core.P['lock_action']} step needs an id")
    return second.get("id")


def check_job_settings(fname, jw, job):
    """Env allow-list with the subprocess scrub on, runner, no defaults."""
    P = core.P
    env = job.get("env") if isinstance(job.get("env"), dict) else {}
    for k in env:
        if k not in P["job_env"]:
            core.err(f"{jw}: env {k!r} not allowed in a job with a claude step (allowed: {', '.join(sorted(P['job_env']))})")
    if str(env.get("CLAUDE_CODE_SUBPROCESS_ENV_SCRUB", "")) != "1":
        core.err(f'{jw}: needs env CLAUDE_CODE_SUBPROCESS_ENV_SCRUB: "1" (tool subprocesses must not see the Claude token)')
    if fname == P["manager"]:
        for k, v in P["manager_env_required"].items():   # no dependency lifecycle script next to the agents' token
            if str(env.get(k, "")) != v:
                core.err(f'{jw}: needs env {k}: "{v}" (a PR\'s .yarnrc.yml must not turn lifecycle scripts back on next to the agents\' token)')
    if job.get("runs-on") != P["runs_on"]:
        core.err(f"{jw}: runs-on must be {P['runs_on']}")
    if "defaults" in job:
        core.err(f"{jw}: 'defaults' not allowed in a job with a claude step")


def check_other_steps(jw, steps, claude_at, ok_refs):
    """Steps around the claude step: pinned actions, default-branch checkouts, PR data only in the reviewed prepare step,
    and post steps that check their pinned files before running repo scripts."""
    P = core.P
    for i, step in enumerate(steps, 1):
        if not isinstance(step, dict) or core.is_claude(step) or i <= 4:
            continue
        sw = f"{jw} step {i}"
        uses = str(step.get("uses", ""))
        core.require_pinned(sw, uses)
        if claude_at and i < claude_at:
            check_pre_claude_step(sw, step)
        if uses.startswith("actions/checkout@"):
            check_checkout(sw, step, ok_refs)
        for key in ("working-directory", "shell"):
            if key in step:
                # After the claude step one shell is allowed: the hardened one from the policy (an absolute bash that reads
                # no profile or rc file), so a step's own shell is not found through a PATH the claude step could prepend.
                if key == "shell" and claude_at and i > claude_at and step.get("shell") == P["post_claude_shell"]:
                    continue
                core.err(f"{sw}: '{key}' not allowed in a job with a claude step"
                         + (f" (after the claude step only shell: {P['post_claude_shell']})" if key == "shell" and claude_at and i > claude_at else ""))
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


def check_pre_claude_step(sw, step):
    """Between the lock and the claude step nothing free-form runs: a `run` is one line calling a pinned scripts/check-*.sh
    (the pin step proved those files), and a `uses` is one of the policy's pre_claude_actions with only its listed inputs
    (a downloaded artifact is data). So no repository or third-party code runs next to a Claude token before the lock's
    self-test and the pinned guards have had their say, and nothing can write $GITHUB_ENV or $GITHUB_PATH for the step."""
    P = core.P
    uses = str(step.get("uses", ""))
    if uses:
        allowed = P["pre_claude_actions"].get(uses)
        if allowed is None:
            core.err(f"{sw}: before the claude step only {', '.join(P['pre_claude_actions'])} may be used (found {uses})")
        else:
            w = step.get("with") if isinstance(step.get("with"), dict) else {}
            extra = sorted(set(w) - set(allowed))
            if extra or (set(step) - {"name", "if", "uses", "with", "id"}):
                core.err(f"{sw}: {uses} may only have name/if/id/with and the inputs {', '.join(allowed)} (found {', '.join(extra) or 'other keys'})")
        return
    run = str(step.get("run", "")).strip()
    for sub in P["pre_claude_run_allowed_substitutions"]:   # the one computed argument the policy allows (the events window)
        run = run.replace(sub, "SUBST")
    if not re.match(P["pre_claude_run"], run):
        core.err(f"{sw}: a run step before the claude step must be one line 'bash scripts/check-<name>.sh ...' (a pinned guard), not: {run[:80]!r}")
    if set(step) - {"name", "if", "id", "run", "env"}:
        core.err(f"{sw}: a run step before the claude step may only have name/if/id/run/env")


def check_job(fname, jw, job, steps, required, triggers):
    """All rules for a job that has a claude step. Returns the number of claude steps."""
    P = core.P
    ok_refs = set(P["default_refs"]) | ({P["base_ref"]} if triggers == {"pull_request_target"} else set())
    lock_id = check_job_start(fname, jw, steps)
    if lock_id is not None:
        check_checkout(f"{jw} step 1", steps[0], ok_refs)
        core.require_pinned(f"{jw} step 1", steps[0].get("uses"))
    check_job_settings(fname, jw, job)
    claude_at = next((i for i, s in enumerate(steps, 1) if isinstance(s, dict) and core.is_claude(s)), 0)
    check_other_steps(jw, steps, claude_at, ok_refs)
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
