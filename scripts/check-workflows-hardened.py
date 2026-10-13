"""The shape of a run step after a claude step, and the job that proves it ran (founder-owned). Loaded by
scripts/check-workflows.py before check-workflows-claude.py, which calls check_hardened_step for every step that sets the
policy's post_claude_shell; check-workflows.py calls check_hardened_check_job once per workflow file.

Plainly: a Claude step can write $GITHUB_ENV and $GITHUB_PATH, and a later step's default bash honours both (PATH,
BASH_ENV, LD_PRELOAD, planted BASH_FUNC_<name>%% functions). A hardened step is built so that what it can be built
against is not read, and so that the one thing it cannot be built against fails closed:
- shell: the policy's post_claude_shell (an absolute bash, so not found through PATH; -p, so bash reads no BASH_ENV
  file, ignores SHELLOPTS, BASHOPTS and CDPATH from the environment and imports no function from it);
- keys: only post_claude_step_keys (name, if, id, shell, env, run; an id is required), so no continue-on-error;
- env: every name in post_claude_empty_env set to "" and post_claude_fixed_env set as given, in the step's own env
  (which wins over $GITHUB_ENV), so the loader, bash, locale, proxy and git read nothing planted; PINS_SHA256 set in the
  step's own env to the hash of .github/pins.txt (never taken from $GITHUB_ENV); every $NAME the body reads set there
  too (GITHUB_OUTPUT excepted: the runner's own, and GITHUB_* cannot be overridden through $GITHUB_ENV - the assignment
  is ignored, docs.github.com "Variables reference");
- run: printable ASCII, tabs and newlines only (Python's splitlines() would also break at \\r, \\v, \\f, U+2028...,
  where bash would not), split on newlines only, no `${{` anywhere (a value expanded by the runner could carry a line
  break out of a comment); the first line post_claude_run_first (the PATH reset), then exactly the lines of
  post_claude_run_prefix in that order (set -u and the two pin lines with /usr/bin/sha256sum), then only pinned scripts
  started under `/usr/bin/env -i PATH=/usr/bin:/bin HOME=/nonexistent TMPDIR=/tmp` (post_claude_script_line; any extra
  NAME=value there must be in post_claude_script_env with exactly that value), and last post_claude_run_last, the
  marker `echo "hardened=ok" >> "$GITHUB_OUTPUT"`;
- the marker is what fails closed: a loader variable that acts by merely existing (LD_TRACE_LOADED_OBJECTS makes every
  dynamically linked program, bash included, print its libraries and exit 0 without running) cannot be emptied away by a
  step env, so the step would go green having run nothing. Therefore the job exports each hardened step's marker as an
  output (`<id>_ran: ${{ steps.<id>.outputs.hardened }}`) and the workflow has the job hardened_check_job (no Claude
  step, `needs` every job with hardened steps, `if: always()`), whose one run line fails unless every marker is `ok` or
  the job was skipped. The checker requires the outputs and that job, with exactly the expected shape.
"""
import re

import check_workflows_lib as core  # loaded into sys.modules by check-workflows.py before this module

ASCII = re.compile(r"[\x20-\x7e\t\n]*")
VARS = re.compile(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)")
ASSIGN = re.compile(r" ([A-Z0-9_]+)=([^ ]*)")
FOUND = {}   # {job name: [step id, ...]} of the hardened steps in the file being checked (reset by check-workflows.py)


def code_lines(run):
    """The run body's lines without blank lines and full-line comments, each stripped of spaces and tabs."""
    return [l.strip(" \t") for l in str(run).split("\n") if l.strip(" \t") and not l.lstrip(" \t").startswith("#")]


def check_hardened_step(sw, jname, step):
    """All rules for a step with the hardened shell (see the module docstring); records the step for the check job."""
    P = core.P
    extra = set(step) - set(P["post_claude_step_keys"])
    if extra:
        core.err(f"{sw}: a step with the hardened shell may only have {'/'.join(P['post_claude_step_keys'])} (found {', '.join(sorted(extra))})")
        return
    if not isinstance(step.get("id"), str) or not re.fullmatch(r"[a-z][a-z0-9-]*", step["id"]):
        core.err(f"{sw}: a step with the hardened shell needs an id (lowercase letters, digits and hyphens): the job exports its marker as output <id>_ran")
        return
    if not isinstance(step.get("env"), dict):
        core.err(f"{sw}: a step with the hardened shell must have an env mapping")
        return
    env = step["env"]
    lower = {}
    for k in env:   # GitHub reads env names without regard to case: two keys that differ only by case are "already defined"
        if lower.setdefault(str(k).lower(), k) != k:
            core.err(f"{sw}: env names {lower[str(k).lower()]} and {k} differ only by case (GitHub refuses the workflow file)")
    for k in P["post_claude_empty_env"]:
        if env.get(k) != "":
            core.err(f"{sw}: a step with the hardened shell must set env {k}: \"\" (a step's own env wins over $GITHUB_ENV)")
    for k, v in P["post_claude_fixed_env"].items():
        if env.get(k) != v:
            core.err(f"{sw}: a step with the hardened shell must set env {k}: {v}")
    if env.get("PINS_SHA256") != core.PINS_HASH:
        core.err(f"{sw}: a step with the hardened shell must set env PINS_SHA256 to the sha256 of .github/pins.txt itself (never from $GITHUB_ENV)")
    run = step.get("run")
    if not isinstance(run, str) or not run.strip():
        core.err(f"{sw}: a step with the hardened shell must have a run body")
        return
    if not ASCII.fullmatch(run):
        core.err(f"{sw}: the run of a step with the hardened shell may hold only printable ASCII, tabs and newlines (bash and the checker must split the same lines)")
        return
    if "${{" in run:
        core.err(f"{sw}: no ${{{{ ... }}}} in the run of a step with the hardened shell, comments included (the runner expands it before bash reads the line; pass values through env)")
        return
    lines = code_lines(run)
    for name in sorted(set(VARS.findall("\n".join(lines))) - {"GITHUB_OUTPUT"}):
        if name not in env:
            core.err(f"{sw}: the run reads ${name}, which the step's own env does not set (it could come from $GITHUB_ENV)")
    if check_run_lines(sw, lines):
        FOUND.setdefault(jname, []).append(step["id"])   # the step ends with the marker: the check job must read it


def check_run_lines(sw, lines):
    """The body, comments and blank lines removed: PATH reset, the fixed prefix in order, script lines, the marker last
    (required when post_claude_require_marker is true; allowed before that). Returns whether the marker is there."""
    P = core.P
    want = [P["post_claude_run_first"]] + list(P["post_claude_run_prefix"])
    if lines[:len(want)] != want:
        core.err(f"{sw}: a step with the hardened shell must start its run with these lines, in this order: {' / '.join(want)} (the PATH reset, set -u and the pin check with /usr/bin/sha256sum)")
        return False
    marked = lines[-1] == P["post_claude_run_last"]
    if not marked and P["post_claude_require_marker"]:
        core.err(f"{sw}: a step with the hardened shell must end its run with the marker line {P['post_claude_run_last']} (the hardened-check job fails without it; policy post_claude_require_marker)")
        return False
    script_line = re.compile(P["post_claude_script_line"])
    for line in lines[len(want):len(lines) - 1 if marked else len(lines)]:
        if not script_line.fullmatch(line):
            core.err(f"{sw}: line not allowed in a step with the hardened shell: {line[:100]!r} (between the fixed lines and the marker only a pinned script under post_claude_script_line)")
            continue
        for name, value in ASSIGN.findall(line.split(" /usr/bin/", 1)[0].split("TMPDIR=/tmp", 1)[1]):
            if P["post_claude_script_env"].get(name) != value:
                core.err(f"{sw}: the script line may not set {name}={value} (only post_claude_script_env: {', '.join(f'{k}={v}' for k, v in P['post_claude_script_env'].items())})")
    return marked


def check_hardened_check_job(fname, doc):
    """The job outputs for every hardened step that ends with the marker, and the one job that fails unless every marker
    is `ok` (or the job with the hardened steps was skipped). Uses FOUND, filled by check_hardened_step while the jobs
    were checked. With post_claude_require_marker false the check job is validated only when it exists."""
    P = core.P
    name = P["hardened_check_job"]
    jobs = doc["jobs"]
    for jname, ids in FOUND.items():
        outputs = jobs[jname].get("outputs") if isinstance(jobs[jname].get("outputs"), dict) else {}
        for sid in ids:
            if outputs.get(f"{sid}_ran") != f"${{{{ steps.{sid}.outputs.hardened }}}}":
                core.err(f"{fname} job {jname}: needs outputs {sid}_ran: ${{{{ steps.{sid}.outputs.hardened }}}} (the marker of hardened step {sid}, read by job {name})")
    if not FOUND:
        if name in jobs:
            core.err(f"{fname} job {name}: no hardened step with the marker line in this workflow to check")
        return
    job = jobs.get(name)
    if not isinstance(job, dict):
        if P["post_claude_require_marker"]:
            core.err(f"{fname}: needs job {name} (fails unless every hardened step wrote its marker; see scripts/check-workflows-hardened.py)")
        return
    env = {f"{j}_result": f"${{{{ needs.{j}.result }}}}" for j in sorted(FOUND)}
    env.update({f"{j}_{sid}": f"${{{{ needs.{j}.outputs.{sid}_ran }}}}" for j in sorted(FOUND) for sid in FOUND[j]})
    run = "".join(f'[ "${j}_result" = skipped ] || [ "${j}_{sid}" = ok ] || {{ echo "hardened step {j}/{sid} did not run"; exit 1; }}\n'
                  for j in sorted(FOUND) for sid in FOUND[j])
    want = {"needs": sorted(FOUND), "if": "always()", "runs-on": P["runs_on"], "permissions": {"contents": "read"}, "env": env,
            "steps": [{"run": run}]}
    got = {k: v for k, v in job.items() if k != "name"}
    if isinstance(got.get("steps"), list) and len(got["steps"]) == 1 and isinstance(got["steps"][0], dict):
        got["steps"] = [{k: v for k, v in got["steps"][0].items() if k != "name"}]
    for key in sorted(set(want) | set(got)):
        if want.get(key) != got.get(key):
            core.err(f"{fname} job {name}: {key} must be exactly {want.get(key)!r} (found {got.get(key)!r})")
