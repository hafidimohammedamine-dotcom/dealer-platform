"""Who may start what (founder-owned): people are matched by numeric user ID, never by login (a login can be renamed and
re-registered), and every job that holds the agents' token checks that token first. Loaded by scripts/check-workflows.py
after scripts/check-workflows-lib.py. Rules and messages: docs/runbooks/ci-guards.md."""
import json
import re

import check_workflows_lib as core  # noqa: E402 - loaded into sys.modules by check-workflows.py before this module

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
    """A job that mentions the agents' token (any case) runs the token check first: right after checkout and the lock,
    as a plain step (only name and run)."""
    P = core.P
    uses = P["agent_token_secret"].lower() in json.dumps(job).lower()
    if not uses and fname not in P["agent_token_required_in"]:
        return
    lead = 0
    while lead < len(steps) and isinstance(steps[lead], dict) and (
            str(steps[lead].get("uses", "")).startswith("actions/checkout@") or steps[lead].get("uses") == P["lock_action"]):
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
