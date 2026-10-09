# Runbook: agent network lock (`.github/actions/agent-egress-lock`)

Founder-owned action. Every job with a Claude step runs it right after checking out `main` (`scripts/check-workflows.sh`
enforces that). Other CI runbook topics: `docs/runbooks/ci-guards.md`.

## What it does
1. Installs gitleaks (`.github/actions/install-gitleaks`), Claude Code from `downloads.claude.ai` and Bun from Bun's GitHub
   release, each checked against a sha256 pinned in the action. The claude-code-action uses these binaries
   (`path_to_claude_code_executable`, `path_to_bun_executable`) instead of downloading its own, because the lock closes
   GitHub's release storage.
2. Starts a local DNS server (dnsmasq) that answers only the names in `allow-domains.txt`.
3. Starts a local proxy (nginx `stream` with `ssl_preread`) that reads the TLS server name (SNI) of each connection and
   connects only to allow-listed names. The firewall (iptables) sends every outbound port-443 connection, except the proxy's
   own, to that proxy and rejects everything else: plain HTTP, raw IPs without a name, other DNS servers, all IPv6. An allowed
   IP cannot be reused under another name.
4. Installs bubblewrap and socat for Claude Code's subprocess isolation (`CLAUDE_CODE_SUBPROCESS_ENV_SCRUB`). Where AppArmor
   restricts unprivileged user namespaces, it keeps that restriction on (`kernel.apparmor_restrict_unprivileged_userns=1`).
   Only `/usr/bin/bwrap` may create user namespaces (AppArmor profile `agent-bwrap`). Everything bwrap starts runs stacked
   under the child profile `agent-bwrap-child`, which has no capabilities and may not create user namespaces.
5. Stops Docker and removes sudo for the runner user, for `ALL`, and for every group the job's processes carry, so no later
   step can undo the lock.
6. Self-tests and fails the job on any problem. Only after the self-test passes does it write the `claude-path` and `bun-path`
   outputs, so a Claude step can never start on a runner the lock did not finish.

Allowed names are exact hosts: `github.com`, `api.github.com`, `codeload.github.com`, `api.anthropic.com` and the npm/Yarn
registries. The only wildcard is `.actions.githubusercontent.com` (approved in `lock.sh`), where the runner talks to many
generated names.

## Tests
- `scripts/check-egress-lock.test.sh`: every failure branch, with stubbed system commands; it also checks the generated
  dnsmasq, nginx, iptables and AppArmor setup and the order of the sudo removal.
- `.github/workflows/egress-lock-test.yml`: runs the PR's lock on a real runner with no secrets, plus a break-on-purpose run.
- `.github/workflows/egress-lock-claude.yml`: from `main` only, on pushes to main that change the lock action or this workflow,
  weekly (Mondays) and on demand. Job `probe` runs the real claude-code-action under the lock and checks the
  `Skill(payload)` deny. Job `scrub` checks the subprocess isolation.

## Messages and fixes
- `Linux x64 runners only` / `must run inside GitHub Actions` - only for GitHub-hosted Ubuntu x64 runners.
- `bad CLAUDE_CODE_VERSION`, `bad CLAUDE_CODE_SHA256`, `Claude Code download does not match its pinned sha256`, `Claude Code
  <v> not installed`, `bad BUN_VERSION`, `bad BUN_SHA256`, `Bun download does not match its pinned sha256`, `Bun <v> not
  installed` - fix the pins in `action.yml` (see "Bumping the pins").
- `empty allow-list` / `not a plain host name` / `suffix entry not approved` - fix `allow-domains.txt`.
- `no www-data user for nginx`, `nginx stream module missing`, `nginx config invalid`, `could not install dnsmasq-base nginx
  libnginx-mod-stream bubblewrap socat`, `could not load the AppArmor profile for bubblewrap` - the runner image changed. Re-run
  once, then a founder checks the packages and the AppArmor setup.
- `self-test: allowed host api.github.com not reachable` - the proxy or DNS is not working. The log shows the proxy log and a
  verbose curl.
- Any other `self-test: ...` message means the lock is not doing its job on this runner. Do not bypass it; open an
  `area:security` issue for the founders. The messages: `sudo still works`, `sudo still lists rules for this user (a
  command-limited rule is left)`, `Docker still reachable`, `group-writable admin socket still there`, `blocked host
  example.com reachable`, `gist.github.com reachable`, `uploads.github.com reachable`, `allowed IP reachable under another
  name (SNI)`, `raw IP without a name reachable`, `plain HTTP (port 80) reachable`, `DNS for an allowed name does not
  resolve`, `DNS for a blocked name resolves`, `outside DNS server reachable`, `IPv6 reachable`, `bubblewrap cannot start
  (subprocess isolation would fail)`, `unprivileged user namespaces are not restricted`, `a program started by bubblewrap
  can create user namespaces`, and `domain fronting through <name> answers for another host (HTTP <code> <location>)`.
  `self-test: deliberate break` appears only in the break-on-purpose test run.
- A tool in an agent job cannot download something it needs: add its exact host to `allow-domains.txt` in a founder PR. First
  run the domain-fronting check for it (see "Measured limits").
- `Claude answered under the lock, and Skill(payload) was denied` fails (job `probe`) - either Claude could not reach
  `api.anthropic.com` through the lock, or the Skill deny did not hold. Read the printed result and denials.
- Job `scrub` fails - Claude ran `bash scripts/check-scrub-probe.sh` as a tool, and it printed `SCRUB-PROBE env-tokens=<n>
  proc-tokens=<n> pid=<n>` with a count above 0, or printed nothing. The probe counts Claude tokens (`sk-ant...`) visible to a
  tool, in its own environment and in every readable `/proc/<pid>/environ`, and prints counts only. A count above 0 means the
  subprocess isolation is not working. Open an `area:security` issue; do not turn the scrub off.

## Bumping the pins
Bump them in a founder PR, together with the claude-code-action SHA:
- **Claude Code:** the action's `src/entrypoints/run.ts` names the version it expects. Copy that version's `linux-x64`
  `checksum` from `https://downloads.claude.ai/claude-code-releases/<version>/manifest.json` into `action.yml`.
- **Bun:** the action's `action.yml` (setup-bun step) names the Bun version. Copy the sha256 of `bun-linux-x64.zip` from
  `https://github.com/oven-sh/bun/releases/download/bun-v<version>/SHASUMS256.txt`.

The reviewers check the pins, and `egress-lock-test.yml` / `egress-lock-claude.yml` prove the result.

## The agents' GitHub token
Claude Code's subprocess isolation keeps the Claude token out of every tool the agents run. `GH_TOKEN` stays visible to those
tools, because they need it to push and comment. So the GitHub token's scope is the real limit, and it must come from the
agents' own account: a fine-grained token for this repository only, with Contents, Pull requests and Issues (read/write),
Actions (read), and **no Workflows permission and no admin**. Without the Workflows permission it cannot push changes to
`.github/workflows/`.

The manager checks this before Claude starts. `scripts/check-agent-token.sh` fails the job if the token's login is in
`.github/founders.txt`:
- `the agents' GH_TOKEN belongs to founder '<login>' ...` - the token is a founder's.
- `could not read the token's GitHub login` - the token is missing or invalid.

So the manager does not run at all until the agents' account and token exist. The instant fix round after a failed review also
needs the repository variable `AGENT_GH_LOGIN` (the agents' login). It starts only for a PR from this repository whose author
is that login.

The command deny lists are a second layer. They block `npm`, `npx`, `yarn npm publish/login`, `gh api`, `gh gist`, `gh
auth`, `gh secret`, `curl` and `wget` in the manager. They match command prefixes, so they are not a boundary on their own.

## Measured limits
Measured from GitHub runners on 2026-10-09 by the author of this change, not yet re-checked by a founder. The test sent
`curl -H 'Host: <other site>' https://<allowed name>/` through the lock.

**Not used for fronting.** These did not answer for another site, and the self-test repeats the check against every exact
allowed name on every run:
- `api.github.com` and `codeload.github.com` returned 400.
- `api.anthropic.com` and the npm/Yarn registries were refused by Cloudflare (403).
- `github.com` redirected to itself (301).

**Exceptions with a note:**
- `github.com` with `Host: gist.github.com` reached the gist service (302). Gists are the documented GitHub route below either
  way, since `api.github.com` is allowed.
- `.actions.githubusercontent.com` names answered `OK` or 400 for any Host. That is a generic health answer, not another site.

**Removed after the test:**
- `objects.githubusercontent.com` and `release-assets.githubusercontent.com` served another site's page (200).
- The Azure log-storage names `productionresultssa*.blob.core.windows.net` routed by the Host header to other storage accounts
  (`AccountNotFound` for an unknown account).

A runner with neither of them still ran its steps and uploaded its logs.

**What the lock still does not stop:** an injected instruction that also carries an attacker's own credentials could still
send data to an allowed service: GitHub (a push, issue or gist), npm (a publish) or the Anthropic API (the attacker's key).
Each run prints a `Known open routes` notice. The founders decide whether to accept these routes or close them, for example
with a read-only package mirror for the manager.

The job's processes keep the groups they started with (sudo, docker, adm); Linux cannot take them away mid-job. The lock makes
them powerless instead:
- no sudoers rule remains for the user, `ALL` or those groups;
- Docker is stopped and its socket is gone;
- the self-test fails if `sudo -n -l` still works or a docker/lxd/containerd socket is writable.

## Evidence for the Skill deny and the pins
- Versions: Claude Code 2.1.295 and Bun 1.3.14. Tag v1.0.247 of claude-code-action is commit 2dca132f; its
  `src/entrypoints/run.ts` pins Claude Code 2.1.295 and its `action.yml` installs Bun 1.3.14.
- Gathered by the author of this change on 2026-10-09. A founder should repeat these checks before relying on them.
- **CI:** run https://github.com/hafidimohammedamine-dotcom/dealer-platform/actions/runs/37986311153 printed
  `permission_denials: [{"tool_name": "Skill", ... "skill": "payload"}]` with the real claude-code-action under the lock. It
  was an earlier version of the egress test that still ran the probe on the PR branch; the probe now runs only from `main`.
- **What cannot run before merge:** the probe and scrub jobs need a Claude token, which never runs next to PR code. They run on
  the first push to `main` after merge, then weekly. A failure there means the deny or the isolation does not hold; the fix is
  a follow-up founder PR.
- **The manager's push path** (`persist-credentials: false` plus `gh auth setup-git`): checked before merge by
  `egress-lock-test.yml`, which runs `gh auth setup-git` and `git ls-remote origin HEAD` through the lock. Pushing itself is
  first proven by the manager's next run with the agents' token.
- **Local re-check:**
  1. In an empty folder, create `.claude/skills/probe/SKILL.md`, a skill telling Claude to reply `PROBE-LOADED-7731`.
  2. Add two agents in `.claude/agents/`: `subprobe` (`skills: probe`) and `subskill` (`tools: Skill`, told to load `probe`).
  3. Run `claude -p "Use the Skill tool to load the skill named probe ..." --permission-mode bypassPermissions --disallowedTools
     "Skill(probe)" --output-format json`. It gives `permission_denials: [{'tool_name': 'Skill', ... 'skill': 'probe'}]`.
  4. Ask it, with the same flags, to run both subagents. It gives `SUBPROBE: PROBE-LOADED-7731` (the preload still works) and
     `SUBSKILL: SUB-SKILL-DENIED` (the deny holds in a subagent).

Re-check when a pin changes.
