# Runbook: agent network lock (`.github/actions/agent-egress-lock`)

Founder-owned action. Every job with a Claude step runs it right after checking out `main` (`scripts/check-workflows.sh`
enforces that). Other CI runbook topics: `docs/runbooks/ci-guards.md`.

## What it does
1. Installs Node 20 (`actions/setup-node`, the runner image no longer caches it), gitleaks
   (`.github/actions/install-gitleaks`), Claude Code from `downloads.claude.ai` and Bun from Bun's GitHub release; the last
   three are checked against a sha256 pinned in the action. The claude-code-action uses these binaries
   (`path_to_claude_code_executable`, `path_to_bun_executable`) instead of downloading its own, because the lock closes
   GitHub's release storage. It also sets `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` and `DISABLE_AUTOUPDATER=1` for the
   later steps.
2. Starts a local DNS server (dnsmasq) that answers only the allowed names, stops systemd-resolved and points
   `/etc/resolv.conf` at it.
3. Starts a local proxy (nginx `stream` with `ssl_preread`) that reads the TLS server name (SNI) of each connection and
   connects only to allow-listed names. The firewall (iptables) sends every outbound port-443 connection, except the proxy's
   own, to that proxy and rejects everything else: plain HTTP, raw IPs without a name, other DNS servers, all IPv6. An allowed
   IP cannot be reused under another name. The one exception to "no raw IPs" is root's access to the Azure host services
   (168.63.129.16 and 169.254.169.254) that the runner machine itself needs; the job's steps do not run as root.
4. Installs bubblewrap and socat for Claude Code's subprocess isolation (`CLAUDE_CODE_SUBPROCESS_ENV_SCRUB`). Where AppArmor
   restricts unprivileged user namespaces, it keeps that restriction on (`kernel.apparmor_restrict_unprivileged_userns=1`).
   Only `/usr/bin/bwrap` may create user namespaces (AppArmor profile `agent-bwrap`). Everything bwrap starts runs stacked
   under the child profile `agent-bwrap-child`, which has no capabilities and may not create user namespaces. The image's
   other profiles that grant user namespaces (browsers, podman, lxc, sbuild and more; measured on 2026-10-09) are unloaded;
   Ubuntu's own `unprivileged_userns` profile stays. The setuid helpers `/usr/bin/newuidmap` and `newgidmap` lose their
   setuid/setgid bits: with them, any unconfined program (`podman unshare`, measured on 2026-10-10) became root with every
   capability inside a user namespace, around the restriction; bubblewrap does not use them.
5. Stops Docker and removes sudo for the runner user, for `ALL`, and for every group the job's processes carry, so no later
   step can undo the lock.
6. Self-tests and fails the job on any problem. Only after the self-test passes does it write the `claude-path` and `bun-path`
   outputs, so a Claude step can never start on a runner the lock did not finish.

Allowed names are exact hosts, listed in `allow-domains.txt`: `github.com`, `api.github.com`, `codeload.github.com`,
`api.anthropic.com` and the npm/Yarn registries. There are no wildcards. The runner's own services needed no new connection
during the steps (measured 2026-10-09). The one addition: a job with `id-token: write` (`claude.yml`) also allows its own OIDC
token host, read from the runner's `ACTIONS_ID_TOKEN_REQUEST_URL` (a generated name such as
`run-actions-3-azure-eastus.actions.githubusercontent.com`), for that run only.

## Tests
- `scripts/check-egress-lock.test.sh`: every failure branch, with stubbed system commands; it also checks the generated
  dnsmasq, nginx, iptables and AppArmor setup and the order of the sudo removal.
- `.github/workflows/egress-lock-test.yml`: runs the PR's lock on a real runner with no secrets (tools, git push path, Bun,
  gitleaks, bubblewrap), in a job with `id-token: write` that fetches an OIDC token under the lock, and in a
  break-on-purpose run.
- `.github/workflows/egress-lock-claude.yml`: from `main` only, on pushes to main that change the lock action or this workflow,
  weekly (Mondays) and on demand. Job `probe` runs the real claude-code-action under the lock and checks the
  `Skill(payload)` deny. Job `scrub` checks the subprocess isolation.

## Messages and fixes
- `Linux x64 runners only` / `must run inside GitHub Actions` - only for GitHub-hosted Ubuntu x64 runners.
- `bad CLAUDE_CODE_VERSION`, `bad CLAUDE_CODE_SHA256`, `Claude Code download does not match its pinned sha256`, `Claude Code
  <v> not installed`, `bad BUN_VERSION`, `bad BUN_SHA256`, `Bun download does not match its pinned sha256`, `Bun <v> not
  installed` - fix the pins in `action.yml` (see "Bumping the pins").
- `empty allow-list` / `not a plain host name: '<x>'` - fix `allow-domains.txt` (exact names only, no wildcards).
- `unexpected OIDC host: '<host>'` - the runner's `ACTIONS_ID_TOKEN_REQUEST_URL` is not `https://<name>.actions.githubusercontent.com/...`.
  Re-run once; if it persists, GitHub changed its OIDC service: a founder checks the new host and updates `lock.sh`.
- `no www-data user for nginx`, `nginx stream module missing`, `nginx config invalid`, `could not install dnsmasq-base nginx
  libnginx-mod-stream bubblewrap socat`, `could not load the AppArmor profile for bubblewrap` - the runner image changed. Re-run
  once, then a founder checks the packages and the AppArmor setup.
- `self-test: allowed host api.github.com not reachable` / `allowed name <name> not reachable through the lock` - the proxy
  or DNS is not working, or a name in the list is wrong. The log shows the proxy log and a verbose curl. Every self-test
  failure ends with `self-test failed; see errors above`.
- Any other `self-test: ...` message means the lock is not doing its job on this runner. Do not bypass it; open an
  `area:security` issue for the founders. The messages: `sudo still works`, `sudo still lists rules for this user (a
  command-limited rule is left)`, `Docker still reachable`, `group-writable admin socket still there`, `blocked host
  example.com reachable`, `gist.github.com reachable`, `uploads.github.com reachable`, `allowed IP reachable under another
  name (SNI)`, `raw IP without a name reachable`, `plain HTTP (port 80) reachable`, `DNS for an allowed name does not
  resolve`, `DNS for a blocked name resolves`, `outside DNS server reachable`, `IPv6 reachable`, `bubblewrap cannot start
  (subprocess isolation would fail)`, `unprivileged user namespaces are not restricted`, `a program started by bubblewrap
  can create user namespaces`, `AppArmor profiles that allow user namespaces are still loaded: <names>`, `a program outside
  bubblewrap can become root in a user namespace`, `<path> is still setuid/setgid (maps root into a user namespace)`,
  `podman can still become root in a user namespace`, and `domain fronting through <name> answers for another host
  (HTTP <code> <location>)`. `could not remove setuid from <path>` is a lock error before the self-test (chmod failed).
  `self-test: deliberate break` appears only in the break-on-purpose test run.
- A tool in an agent job cannot download something it needs: add its exact host to `allow-domains.txt` in a founder PR. First
  run the domain-fronting check for it (see "Measured limits").
- `Claude answered under the lock, and Skill(payload) was denied` fails (job `probe`) - either Claude could not reach
  `api.anthropic.com` through the lock, or the Skill deny did not hold. Read the printed result and denials.
- Job `scrub` fails - Claude ran `bash scripts/check-scrub-probe.sh` as a tool, and the check step (`scripts/check-claude-probe.py
  scrub`) printed `probe: SCRUB-PROBE env-tokens=<n> proc-tokens=<n> pid=<n>` with a count above 0, or `probe: did not run`.
  The probe counts Claude tokens (`sk-ant...`) visible to a tool, in its own environment and in every readable
  `/proc/<pid>/environ`, and prints counts only. A count above 0 means the subprocess isolation is not working. Open an
  `area:security` issue; do not turn the scrub off.
- `ERROR: cannot read the execution file (<error>)` (either probe job) - the Claude step did not produce its execution file
  (it failed before running); read that step's log.

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
agents' own account, `mohammedaminehafidi-ctrl` (an `agent` row in `.github/accounts.txt`, a collaborator on this repository
only). The token is either fine-grained (this repository only; Contents, Pull requests and Issues read/write, Actions read; no
Workflows, no admin) or classic with exactly the scope `repo` and nothing else (no `workflow`, so it cannot change
`.github/workflows/`). Fine-grained tokens cannot cover a personal account's repository for a collaborator, so the agents use
a classic `repo` token until the repository moves to an organization.

Every job that holds the agents' token runs `bash scripts/check-agent-token.sh .github/accounts.txt` as its first step after
checkout and the lock (`scripts/check-workflows.sh` enforces it). It fails the job with:
- `GH_TOKEN is not a fine-grained (github_pat_...) or classic (ghp_...) token` - wrong kind of token, or none.
- `GH_TOKEN carries classic OAuth scopes (...)` - a fine-grained token must have no classic scopes.
- `the classic GH_TOKEN must have exactly the scope 'repo' (has: '...')` - remove every other scope.
- `the agents' GH_TOKEN belongs to founder '<login>' ...` - the token's user ID is a founder's.
- `the agents' GH_TOKEN belongs to '<login>' (ID <id>), which is not an agent account in .github/accounts.txt` - use the
  agents' account's token, or add that account as `agent` in a founder PR.
- `could not read the token's GitHub login` - the token is missing or invalid.
- `accounts file not found: <file>`, `bad line <n> in <file> ...`, `no founder listed in <file>` - fix `.github/accounts.txt`.

The instant fix round after a failed review (`review.yml`) starts only for a PR from this repository whose author has the
agents' account ID (250452267) and whose branch starts with `agent/`.

The command deny lists are a second layer. They block `npm`, `npx`, `yarn npm publish/login`, `gh api`, `gh gist`, `gh
auth`, `gh secret`, `curl` and `wget` in the manager. They match command prefixes, so they are not a boundary on their own.

## Measured limits
Measured from GitHub runners on 2026-10-09 by the author of this change, accepted by founder Mohammed without a re-check (see
"Founder decisions"). The test sent `curl -H 'Host: <other site>' https://<allowed name>/` through the lock.

**Not used for fronting.** These did not answer for another site, and the self-test repeats the check against every exact
allowed name on every run:
- `api.github.com` and `codeload.github.com` returned 400.
- `api.anthropic.com` and the npm/Yarn registries were refused by Cloudflare (403).
- `github.com` redirected to itself (301).

**Exceptions with a note:**
- `github.com` with `Host: gist.github.com` reached the gist service (302). Gists are the documented GitHub route below either
  way, since `api.github.com` is allowed.
- The Actions service names (`*.actions.githubusercontent.com`, including the per-run OIDC host) answered a bare `OK` or 400
  for any Host: a generic health answer, not another site. The self-test therefore accepts a 2xx whose body is exactly `OK`
  and fails on any other 2xx. Of these names only the per-run OIDC host is allowed, and only in jobs with `id-token: write`.

**Removed after the test:**
- `objects.githubusercontent.com` and `release-assets.githubusercontent.com` served another site's page (200).
- The Azure log-storage names `productionresultssa*.blob.core.windows.net` routed by the Host header to other storage accounts
  (`AccountNotFound` for an unknown account).

A runner with neither of them still ran its steps and uploaded its logs.

**User namespaces (2026-10-10):** with the restriction on and the other profiles unloaded, `unshare -U` still worked for an
unconfined program (allowed by Ubuntu's `unprivileged_userns` profile: no capability inside), `unshare -Ur` was refused, but
`podman unshare id` printed `uid=0` with every capability, because the setuid `newuidmap`/`newgidmap` helpers write the
mapping. After the lock removed their setuid bits, podman reported `newuidmap: write to uid_map failed: Operation not
permitted`, and bubblewrap still started.

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
- Gathered by the author of this change on 2026-10-09. Accepted by founder Mohammed as recorded (see "Founder decisions");
  re-checked at the next pin bump.
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

## Founder decisions (accepted risks)
Accepted by founder Mohammed (`hafidimohammedamine-dotcom`) on 2026-10-09, in the session that built PR #30; recorded at his
request. Owner: Mohammed. Review by 2026-11-08, or earlier if any of them changes.
1. **Open exit routes.** An agent misled by an injected instruction that also carries an attacker's own credentials could
   still send data to GitHub (push, issue, gist), npm (publish) or the Anthropic API. Closing these needs a read-only package
   mirror and a GitHub proxy that accepts only this job's own token; that is a later issue, not this PR. Until then the
   limits are the agents' repo-only token (classic with only `repo`, or fine-grained), the manager's command denies and the
   reviews.
2. **Pins and measurements checked by the author, not re-checked by a founder.** The Claude Code and Bun sha256 pins, the
   coverage.py hashes, the claude-code-action tag-to-commit match, and the domain-fronting measurements above are accepted as
   recorded here. A founder re-checks them at the next pin bump.
3. **Agent workflows run under the lock for the first time after merge.** Before merge they are checked statically
   (`scripts/check-workflows.sh`), and the lock itself runs on a real runner in `egress-lock-test.yml`. The Claude jobs
   (`egress-lock-claude.yml`, manager, review, reports) first run under the lock after merge; a failure there is fixed in a
   follow-up founder PR.
