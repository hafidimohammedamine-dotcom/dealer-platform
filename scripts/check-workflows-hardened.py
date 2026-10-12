"""The shape of a run step after a claude step (founder-owned). Loaded by scripts/check-workflows.py before
check-workflows-claude.py, which calls check_hardened_step for every step that sets the policy's post_claude_shell.

Plainly: a Claude step can write $GITHUB_ENV and $GITHUB_PATH, and a later step's default bash honours both (PATH,
BASH_ENV, LD_PRELOAD, planted BASH_FUNC_<name>%% functions). A hardened step is built so that neither is read:
- shell: the policy's post_claude_shell (an absolute bash, so not found through PATH; -p, so bash reads no BASH_ENV or
  ENV file, ignores SHELLOPTS and BASHOPTS from the environment and imports no function from it);
- env: every name in post_claude_empty_env set to "" and post_claude_fixed_env set as given, in the step's own env
  (which wins over $GITHUB_ENV), so the loader, bash, locale, proxy and git read nothing planted; PINS_SHA256 set in the
  step's own env to the hash of .github/pins.txt (never taken from $GITHUB_ENV); every $NAME the body reads set there too
  (GITHUB_OUTPUT excepted: the runner's own, and GITHUB_* cannot be overridden through $GITHUB_ENV - the assignment is
  ignored, docs.github.com "Variables reference");
- run: printable ASCII, tabs and newlines only (Python's splitlines() would also break at \\r, \\v, \\f, U+2028...,
  where bash would not), split on newlines only; the first line post_claude_run_first (the PATH reset), then exactly the
  lines of post_claude_run_prefix in that order (set -u and the two pin lines with /usr/bin/sha256sum), then only
  pinned scripts started under `/usr/bin/env -i PATH=/usr/bin:/bin HOME=/nonexistent TMPDIR=/tmp` (post_claude_script_line;
  any extra NAME=value there must be a name in post_claude_script_env and never PATH, HOME or TMPDIR again), so every
  command is a builtin, an absolute path or a pinned script in a fresh environment.
"""
import re

import check_workflows_lib as core  # loaded into sys.modules by check-workflows.py before this module

ASCII = re.compile(r"[\x20-\x7e\t\n]*")
VARS = re.compile(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)")
ASSIGN = re.compile(r" ([A-Z0-9_]+)=")


def check_hardened_step(sw, step):
    """All rules for a step with the hardened shell (see the module docstring)."""
    P = core.P
    if "uses" in step:
        core.err(f"{sw}: a uses step may not set the hardened shell")
        return
    if not isinstance(step.get("env"), dict):
        core.err(f"{sw}: a step with the hardened shell must have an env mapping")
        return
    env = step["env"]
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
    for name in sorted(set(VARS.findall(run)) - {"GITHUB_OUTPUT"}):
        if name not in env:
            core.err(f"{sw}: the run reads ${name}, which the step's own env does not set (it could come from $GITHUB_ENV)")
    check_run_lines(sw, [l.strip(" \t") for l in run.split("\n") if l.strip(" \t") and not l.lstrip(" \t").startswith("#")])


def check_run_lines(sw, lines):
    """The body, comments and blank lines removed: PATH reset, the fixed prefix in order, then script lines only."""
    P = core.P
    want = [P["post_claude_run_first"]] + list(P["post_claude_run_prefix"])
    if lines[:len(want)] != want:
        core.err(f"{sw}: a step with the hardened shell must start its run with these lines, in this order: {' / '.join(want)} (the PATH reset, set -u and the pin check with /usr/bin/sha256sum)")
        return
    script_line = re.compile(P["post_claude_script_line"])
    for line in lines[len(want):]:
        if not script_line.fullmatch(line):
            core.err(f"{sw}: line not allowed in a step with the hardened shell: {line[:100]!r} (after the fixed lines only a pinned script under post_claude_script_line)")
            continue
        extra = ASSIGN.findall(line.split(" /usr/bin/", 1)[0].split("TMPDIR=/tmp", 1)[1])
        bad = [n for n in extra if n not in P["post_claude_script_env"]]
        if bad:
            core.err(f"{sw}: the script line may not set {', '.join(bad)} (only post_claude_script_env: {', '.join(P['post_claude_script_env'])})")
