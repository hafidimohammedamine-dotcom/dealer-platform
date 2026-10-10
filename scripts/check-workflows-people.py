"""Who may start what (founder-owned): people are matched by numeric user ID, never by login (a login can be renamed and
re-registered), and every job that holds the agents' token checks that token first. Loaded by scripts/check-workflows.py
after scripts/check-workflows-lib.py. Rules and messages: docs/runbooks/workflow-checker.md."""
import json
import re

import check_workflows_lib as core  # loaded into sys.modules by check-workflows.py before this module

BRACKET = re.compile(r"\[\s*'([a-z_]+)'\s*\]")  # github['actor'] -> github.actor (expressions ignore case)
EXPR = r"[a-z_][a-z0-9_.\-]*"
BOT_CMP = re.compile(rf"{EXPR}\s*[!=]=\s*'[^']*\[bot\]'|'[^']*\[bot\]'\s*[!=]=\s*{EXPR}")  # bot names cannot be registered
LOGIN_REF = re.compile(r"github\.(?:triggering_)?actor\b(?!_id)|\.login\b")
ID_REF = r"(?:github\.(?:triggering_)?actor_id|[a-z0-9_.]*\b(?:user|sender|author|owner|actor)\.id)\b"
ID_CMP = re.compile(rf"{ID_REF}\s*[!=]=\s*'?(\d+)'?|'?(\d+)'?\s*[!=]=\s*{ID_REF}")
ID_LEFT = re.compile(ID_REF)


def normalise(text):
    return BRACKET.sub(r".\1", text.lower())


def check_if(where, text, accounts):
    """Returns the roles of the account IDs this `if` compares; reports login comparisons and IDs used any other way."""
    t = normalise(text)
    if LOGIN_REF.search(BOT_CMP.sub(" ", t)):
        core.err(f"{where}: refers to a login in 'if' (logins can be re-registered); compare the numeric user ID")
    roles = set()
    for m in ID_CMP.finditer(t):
        i = m.group(1) or m.group(2)
        if i not in accounts:
            core.err(f"{where}: user ID {i} is not in .github/accounts.txt")
        else:
            roles.add(accounts[i][1])
    if ID_LEFT.search(ID_CMP.sub(" ", t)):
        core.err(f"{where}: compare user IDs only as '<user id> == <number>' (no contains/fromJSON/variables)")
    return roles


def check_file_ifs(name, doc, accounts):
    """Every job and step `if` of a workflow; a gated workflow must compare at least one ID of its role."""
    roles = set()
    for jn, job in (doc.get("jobs") or {}).items():
        if not isinstance(job, dict):
            continue
        roles |= check_if(f"{name} job {jn}", str(job.get("if", "")), accounts)
        for i, st in enumerate(job.get("steps") or [], 1):
            if isinstance(st, dict):
                roles |= check_if(f"{name} job {jn} step {i}", str(st.get("if", "")), accounts)
    need = core.P["id_gated"].get(name)
    if need and need not in roles:
        art = "an" if need[0] in "aeiou" else "a"
        core.err(f"{name}: must let only {art} {need} account start it (an 'if' comparing a {need}'s user ID from "
                 ".github/accounts.txt)")


def check_token_guard(fname, jw, job, steps):
    """A job that mentions the agents' token (any case) runs the token check first: right after checkout, the pin step and
    the lock, as a plain step (only name and run)."""
    P = core.P
    uses = P["agent_token_secret"].lower() in json.dumps(job).lower()
    if not uses and fname not in P["agent_token_required_in"]:
        return
    lead = 0
    while lead < len(steps) and isinstance(steps[lead], dict) and (
            str(steps[lead].get("uses", "")).startswith("actions/checkout@") or steps[lead].get("uses") == P["lock_action"]
            or core.is_pins_step(steps[lead], fname) or str(steps[lead].get("run", "")).strip() == P["main_head_guard"]):
        lead += 1
    guard = steps[lead] if lead < len(steps) and isinstance(steps[lead], dict) else {}
    if str(guard.get("run", "")).strip() != P["agent_token_guard"]:
        core.err(f"{jw}: holds the agents' token, so its first step after checkout and the lock must run "
                 f"'{P['agent_token_guard']}'")
    elif set(guard) - {"name", "run"}:
        core.err(f"{jw}: the agents' token check step may only have name and run (found {', '.join(sorted(set(guard) - {'name', 'run'}))})")


def check_workflow_env(name, doc):
    """The agents' token never at workflow level (every job would get it)."""
    top = json.dumps({k: v for k, v in doc.items() if k != "jobs"}, default=str).lower()
    if core.P["agent_token_secret"].lower() in top:
        core.err(f"{name}: the agents' token may only be set in a job's env, after its token check")


def check_after_shift(name, doc):
    """The manager's checks that run after Claude (token, guard workflows, the account's events) live in their own job
    (policy `after_shift`): a fresh runner that the shift's Claude (bypassPermissions) could not have touched, which always
    runs after the shift and runs exactly the pinned scripts."""
    want = core.P["after_shift"].get(name)
    if not want:
        return
    job = (doc.get("jobs") or {}).get(want["job"])
    if not isinstance(job, dict):
        core.err(f"{name}: needs a job '{want['job']}' that runs the after-shift checks on a fresh runner")
        return
    jw = f"{name} job {want['job']}"
    if job.get("needs") != want["needs"] or str(job.get("if", "")).strip() != want["if"]:
        core.err(f"{jw}: must have needs: {want['needs']} and if: {want['if']} (it runs after every shift, failed ones too)")
    runs = [str(s.get("run", "")).strip() for s in (job.get("steps") or []) if isinstance(s, dict)]
    for r in want["runs"]:
        if r not in runs:
            core.err(f"{jw}: must run exactly '{r}'")
    events_run = next(r for r in want["runs"] if "check-agent-events.sh" in r)
    for jn, other in (doc.get("jobs") or {}).items():   # elsewhere the event check may run only before a claude step
        if jn == want["job"] or not isinstance(other, dict):
            continue
        seen_claude = False
        for i, st in enumerate(other.get("steps") or [], 1):
            run = str(st.get("run", "")) if isinstance(st, dict) else ""
            seen_claude = seen_claude or (isinstance(st, dict) and core.is_claude(st))
            if "check-agent-events.sh" in run and seen_claude:
                core.err(f"{name} job {jn} step {i}: after Claude ran, the event check belongs in job '{want['job']}' only")
            elif "check-agent-events.sh" in run and run.strip() != events_run:
                core.err(f"{name} job {jn} step {i}: the event check before the shift must run exactly '{events_run}'")


def check_rerun_guard(name, doc):
    """A job that holds a secret runs only on a run's first attempt (policy `rerun_guard` in its `if`): a re-run keeps the
    original commit and its workflow file but gets today's secrets, so re-running an old run would hand a current token to
    code that predates the guards. Founders start a fresh run (a push or a dispatch) instead of re-running."""
    want = core.P["rerun_guard"]
    for jn, job in (doc.get("jobs") or {}).items():
        if not isinstance(job, dict) or "secrets." not in json.dumps(job):
            continue
        if want not in str(job.get("if", "")):
            core.err(f"{name} job {jn}: holds a secret, so its 'if' must contain {want} (a re-run of an old run would get today's secrets)")


def check_id_token_jobs(name, doc):
    """A job that can mint an OIDC token (id-token: write) runs only on a run's first attempt and only after the main-head
    check: a re-run of an old run, or an unchecked push, must not mint one."""
    want = core.P["rerun_guard"]; head = core.P["main_head_guard"]
    for jn, job in (doc.get("jobs") or {}).items():
        perms = job.get("permissions") if isinstance(job, dict) else None
        if not isinstance(perms, dict) or perms.get("id-token") != "write":
            continue
        if want not in str(job.get("if", "")):
            core.err(f"{name} job {jn}: id-token: write, so its 'if' must contain {want}")
        steps = [s for s in (job.get("steps") or []) if isinstance(s, dict)]
        head_at = next((i for i, s in enumerate(steps) if str(s.get("run", "")).strip() == head), None)
        lock_at = next((i for i, s in enumerate(steps) if s.get("uses") == core.P["lock_action"]), None)
        if head_at is None or lock_at is None or head_at > lock_at:
            core.err(f"{name} job {jn}: id-token: write, so it must run '{head}' before the lock")
