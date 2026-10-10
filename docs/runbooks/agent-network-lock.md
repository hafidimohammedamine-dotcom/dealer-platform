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
2. Starts a local DNS server (dnsmasq) that forwards nothing: every allowed name (and anything under it) answers the fixed
   unroutable address 192.0.2.1, every other name is NXDOMAIN. So no query from the job reaches an outside resolver (no DNS
   tunnelling through a subdomain), and a connection to a subdomain dies at the proxy. It stops systemd-resolved and points
   `/etc/resolv.conf` at dnsmasq.
3. Starts a local proxy (nginx `stream` with `ssl_preread`) that reads the TLS server name (SNI) of each connection,
   connects only to allow-listed names and resolves those exact names itself through the upstream resolver (the only DNS
   the firewall lets out, from the proxy's user). The firewall (iptables) sends every outbound port-443 connection, except the proxy's
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
`api.anthropic.com` and the npm/Yarn registries, plus the runner's own services, which every job needs to report its result
(measured 2026-10-10, see "Measured limits"): `broker.actions.githubusercontent.com`,
`results-receiver.actions.githubusercontent.com` and the run service, whose generated name matches
`run-actions-<n>-azure-<region>.actions.githubusercontent.com` (the proxy's only pattern; the same host a job with
`id-token: write` reads from `ACTIONS_ID_TOKEN_REQUEST_URL`, which the lock checks against that pattern). dnsmasq answers the
sink address for `actions.githubusercontent.com` and everything under it so the proxy can see the SNI; the proxy connects
only to the exact names and that pattern.

## Tests
- `scripts/check-egress-lock.test.sh`: every failure branch, with stubbed system commands; it also checks the generated
  dnsmasq, nginx, iptables and AppArmor setup and the order of the sudo removal.
- `.github/workflows/egress-lock-test.yml`: runs the PR's lock on a real runner with no secrets and a read-only token
  (tools, git push path, Bun, gitleaks, bubblewrap) and in a break-on-purpose run. Never with `id-token`: a PR must not run
  its own lock code next to an OIDC token (the workflow checker rejects `id-token: write` on PR triggers).
- `.github/workflows/egress-lock-claude.yml`: from `main` only, weekly (Mondays) and started by a founder (never on a push:
  a push to main by the agents' token would run its own lock before the main guard could revert it; every file it runs is
  pinned, see `docs/runbooks/ci-guards.md`). Job `probe` runs the real claude-code-action under the lock and checks the
  `Skill(payload)` deny. Job `scrub` checks the subprocess isolation. Job `reads` checks the reviewers' tool rules: with
  `Read(./**)` as the only Read allow, Read, Grep and Glob outside the checkout are denied (measured 2026-10-10, run
  38028365846: `/proc/self/environ`, `/dev/fd/../environ` (normalised to `/dev/environ`), `/dev/stdin`, `/etc/hostname`,
  `/home/runner/runners`, `/home/runner/work/_temp`, and Grep or Glob in `/proc/self` were all denied; reads under the
  working folder worked). Job `oidc` (`id-token: write`) fetches an OIDC token under the lock, proving the run service's
  generated name is allowed and nginx accepts it.

## Messages and fixes
- `Linux x64 runners only` / `must run inside GitHub Actions` - only for GitHub-hosted Ubuntu x64 runners.
- `bad CLAUDE_CODE_VERSION`, `bad CLAUDE_CODE_SHA256`, `Claude Code download does not match its pinned sha256`, `Claude Code
  <v> not installed`, `bad BUN_VERSION`, `bad BUN_SHA256`, `Bun download does not match its pinned sha256`, `Bun <v> not
  installed` - fix the pins in `action.yml` (see "Bumping the pins"). `could not download Claude Code <v> from
  downloads.claude.ai` / `could not download Bun <v> from github.com` / `the Bun archive did not unpack (corrupt zip ...)` -
  the download failed before the network closed; re-run once, then check the vendor's release.
- `empty allow-list` / `not a plain host name: '<x>'` - fix `allow-domains.txt` (exact names only, no wildcards).
- `unexpected OIDC host: '<host>'` - the runner's `ACTIONS_ID_TOKEN_REQUEST_URL` is not
  `https://run-actions-<n>-azure-<region>.actions.githubusercontent.com/...` (the run service's name pattern).
  Re-run once; if it persists, GitHub changed its OIDC service: a founder checks the new host and updates `lock.sh`.
- `no www-data user for nginx`, `nginx stream module missing`, `nginx config invalid`, `could not install dnsmasq-base nginx
  libnginx-mod-stream bubblewrap socat`, `could not load the AppArmor profile for bubblewrap` - the runner image changed. Re-run
  once, then a founder checks the packages and the AppArmor setup.
- `self-test: allowed host api.github.com not reachable` / `allowed name <name> not reachable through the lock` - the proxy
  or DNS is not working, or a name in the list is wrong. The log shows the proxy log and a verbose curl. Every self-test
  failure ends with `self-test failed; see errors above`.
- Any other `self-test: ...` message means the lock is not doing its job on this runner. Do not bypass it; open an
  `area:security` issue for the founders. The messages: `sudo still works`, `sudo still lists rules for this user (a
  command-limited rule is left)`, `Docker still reachable`, `systemd lets this user start docker.socket`, `polkit (pkexec)
  lets this user run commands as root` (the Docker and containerd units are masked before sudo goes), `group-writable admin
  socket still there`, `blocked host
  example.com reachable`, `gist.github.com reachable`, `uploads.github.com reachable`, `allowed IP reachable under another
  name (SNI)`, `raw IP without a name reachable`, `plain HTTP (port 80) reachable`, `DNS for an allowed name does not
  resolve`, `DNS for a blocked name resolves`, `outside DNS server reachable`, `IPv6 reachable`, `bubblewrap cannot start
  (subprocess isolation would fail)`, `unprivileged user namespaces are not restricted`, `a program started by bubblewrap
  can create user namespaces`, `AppArmor profiles that allow user namespaces are still loaded: <names>`, `a program outside
  bubblewrap can become root in a user namespace`, `<path> is still setuid/setgid (maps root into a user namespace)`,
  `podman can still become root in a user namespace`, and `domain fronting through <name> answers for another host
  (Host: <host>, HTTP <code> <location>)`. `could not remove setuid from <path>` is a lock error before the self-test (chmod failed).
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
- Job `reads` fails - the check step (`scripts/check-claude-probe.py read-deny`) prints one `denied` / `NOT DENIED` line
  per probe read and `token-shaped strings in tool results and the answer: <n>`. A `NOT DENIED` line means a Read rule
  no longer holds (a Claude Code change, or an edited allow list): the Claude process, which holds the token, could be
  talked into reading its own environment. Open an `area:security` issue and stop the review workflows until it is fixed.
- `ERROR: cannot read the execution file (<error>)` (any probe job) - the Claude step did not produce its execution file
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
- `the agents' account '<login>' owns repositories (...); it must own none` - the agents' account must own no repository
  (no fork either): one would be a place to push our code or data out with the token's own rights. A founder reads what was
  pushed there, deletes those repositories and rotates `AGENT_GH_TOKEN_V2` if anything of ours left this repository.
  `could not list the agent account's own repositories` - the token could not call GitHub; re-run once.
- `workflow <name> is '<state>', not active` - one of `main-guard.yml`, `pusher-ledger.yml`, `guards.yml` or `review.yml`
  is disabled. Nobody but a founder should do that: a founder reads the repository's audit log for who disabled it, and
  re-enables it (Actions -> the workflow -> Enable); agents do not run until then. `the default branch's head (<sha>) has no
  successful main-guard run (runs: ...)` - a push to the default branch whose main-guard run was cancelled, failed or never
  happened: a founder reads that push (who, what) before any agent runs; `has not finished after <n>s; re-run this job
  later` - the run is still going (right after a merge), re-run. `could not read the state of workflow ...` / `could not
  read the default branch's head commit` / `could not list the main-guard runs ...` - the token could not call GitHub;
  re-run once. `GH_REPO or GITHUB_REPOSITORY (owner/repo) is not set` / `bad GH_REPO` - the job environment is wrong.
- `accounts file not found: <file>`, `bad line <n> in <file> ...`, `no founder listed in <file>` - fix `.github/accounts.txt`.

**What the agents' own token can do, and what catches it.** A classic `repo` token on a collaborator account can push to any
branch of this repository, `main` included, and the free plan cannot block that with a ruleset. So `main` is guarded after
the fact: `main-guard.yml` runs on every push to `main` (`scripts/check-main-push.sh`); when the pusher's user ID is not a
`founder` row of `.github/accounts.txt` it reverts the pushed commits with new commits (never a force push), disables the
manager workflow and opens an `area:security` + `blocked` issue for the founders (`docs/runbooks/ci-guards.md`). The agents'
token cannot change that workflow (no `workflow` scope), and pushes made with the workflow's own token start no workflow.
A push of founder-only files onto a founder's branch is caught by the pusher ledger in `guards` (every commit of a PR that
changes founder-only files must have been pushed by a founder). Pushing our code to another repository is caught by the
owns-no-repositories check above at the next job start, every hour with the manager (its failed run then shows in the
daily report; detection, not prevention: a founder decision, see below). The manager also denies `gh repo` (create, fork, delete).

The instant fix round after a failed review (`review.yml`) starts only for a PR from this repository whose author has the
agents' account ID (250452267) and whose branch starts with `agent/`.

The command deny lists are a second layer. They block `npm`, `npx`, `yarn npm publish/login`, `gh api`, `gh gist`, `gh repo`, `gh
auth`, `gh secret`, `curl` and `wget` in the manager. They match command prefixes, so they are not a boundary on their own.

## Measured limits
Measured from GitHub runners on 2026-10-09 and 2026-10-10 in the session that built PR #30 (the run logs are the record;
they are not reproducible from this repository alone, see "Founder decisions" 2). The test sent
`curl -H 'Host: <other site>' https://<allowed name>/` through the lock.

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
  and fails on any other 2xx.

**The runner's own services (2026-10-10).** With only the exact allow-list, a job finished its steps and then hung until its
timeout (shown as cancelled): the runner reports the finished job over a new connection. Measured on the runner (`.runner`,
`ss` on the Listener and Worker, DNS): the Listener talks to `broker.actions.githubusercontent.com`, the Worker streams
results to `results-receiver.actions.githubusercontent.com` and reports to the run service `run-actions-<n>-azure-<region>.
actions.githubusercontent.com` (the same name a job with `id-token: write` sees in `ACTIONS_ID_TOKEN_REQUEST_URL`; a job
without it cannot read the name). The lock allows the two exact names plus that one name pattern (the proxy's only regex),
and the self-test probes them with every foreign Host value: they answered `OK` (200) or 400 only. With them allowed, a
locked job completed 35 seconds after its last step (run 38017297112).

**Fronting probes with same-CDN hosts (2026-10-10, run 38015841277).** Every allowed name was asked for `example.com`,
`www.cloudflare.com` (Cloudflare, which fronts api.anthropic.com and the registries), `pypi.org` (Fastly),
`storage.googleapis.com`, `gist.github.com`, `objects.githubusercontent.com` and `claude.ai` in the Host header. Results:
github.com 301 to itself (302 to gist.github.com for that Host, the documented exception); api.github.com and
codeload.github.com 400; api.anthropic.com and the three registries 403 for every Host, `claude.ai` included. No name served
another site. The self-test now repeats five of these Host values on every allowed name and runner service on every run.

**AppArmor policy sources (2026-10-10).** The lock unloads every loaded profile whose source grants `userns`, searching
`/etc/apparmor.d` and snapd's `/var/lib/snapd/apparmor/profiles` recursively; on GitHub's image the snapd folder is empty
and the grants (1password, Discord, chrome, podman, rootlesskit, lxc-*, sbuild-*, ...) all sit in `/etc/apparmor.d`. The
self-test fails if any of those profiles is still loaded.

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

**What the lock still does not stop:** `api.github.com` is allowed, and the job's own GitHub token - the agents' classic
`repo` token - can comment on or open issues in any repository the account can see, public ones included. An injected
instruction (or a dependency's install script, which gets `GH_TOKEN` from the environment) needs no credentials of its own
to post data there. With an attacker's own credentials, the other allowed services are open too: GitHub (a push, issue or
gist), npm (a publish) or the Anthropic API (the attacker's key). Each run prints a `Known open routes` notice. What
catches the first route: `scripts/check-agent-events.sh` runs after every manager shift (job `after`) and fails if the
agents' account has any event outside this repository since the shift started; the manager denies `gh api`, `gh gist`
and `gh repo` as hygiene. Prevention needs an organization-owned repository with a fine-grained token limited to this
repository (founder decision 1).

The job's processes keep the groups they started with (sudo, docker, adm); Linux cannot take them away mid-job. The lock makes
them powerless instead:
- no sudoers rule remains for the user, `ALL` or those groups;
- Docker is stopped and its socket is gone;
- the self-test fails if `sudo -n -l` still works or a docker/lxd/containerd socket is writable.

## Evidence for the Skill deny and the pins
- Versions: Claude Code 2.1.295 and Bun 1.3.14. Tag v1.0.247 of claude-code-action is commit 2dca132f; its
  `src/entrypoints/run.ts` pins Claude Code 2.1.295 and its `action.yml` installs Bun 1.3.14.
- Compared on 2026-10-10 with the vendors' sources, in the session that built PR #30 (a founder re-checks them before merging;
  see "Founder decisions" 2): Claude Code 2.1.295 linux-x64 checksum
  from `https://downloads.claude.ai/claude-code-releases/2.1.295/manifest.json`; Bun 1.3.14 `bun-linux-x64.zip` from the
  release's `SHASUMS256.txt`; coverage.py 7.16.2 cp312/cp313 manylinux x86_64 wheel digests and PyYAML 6.0.3 cp312/cp313
  digests from `https://pypi.org/pypi/<name>/<version>/json`; tag `v1.0.247` of claude-code-action = commit
  `2dca132ff0e0c4094ce6048b422c6915a071210b` (`git ls-remote`), whose `action.yml` sets `bun-version: 1.3.14` and whose
  `src/entrypoints/run.ts` sets `claudeCodeVersion = "2.1.295"`. Re-checked at every pin bump (see "Bumping the pins").
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
Proposed in PR #30 (written there by the agent session that built it; the PR thread holds the founder's instructions). A
founder accepts them by merging PR #30, and that merge is the record of acceptance; until then they are pending. Owner: the
merging founder. Review by 2026-11-08, or earlier if any of them changes.
1. **Open exit routes.** The agents' own token can comment on or open issues in any repository its account can see
   through `api.github.com`, which the lock allows: an agent misled by an injected instruction, or a dependency's install
   script, could post data (the token itself included) to a repository an attacker reads, with no credentials of its
   own. With an attacker's own credentials, GitHub (push, issue, gist), npm (publish) and the Anthropic API are open as
   well. Accepted for now with these controls: `scripts/check-agent-events.sh` after every shift (job `after` of the
   manager) fails on any event of the agents' account outside this repository and tells a founder to rotate the token;
   the manager denies `gh api`, `gh gist`, `gh repo`, `gh workflow` and `gh run cancel/delete` (hygiene: `bash -c` gets
   around prefix denies); the reviews. The check looks at a rolling 24 hours before and after each shift, because the
   events feed can lag (the reviewer recalls delays of hours; a founder may confirm against GitHub's documentation). This
   detects after the fact. Prevention - an organization-owned repository with a
   fine-grained token limited to this repository, a read-only package mirror and a GitHub proxy that accepts only this
   job's own token - is founder issue #35 ("Move the repository to an organization and give the agents a fine-grained
   token"), not this PR.
2. **Pins and measurements.** The pins were compared with the vendors' sources on 2026-10-10 in the PR's session (see
   "Evidence"); the measurements in this runbook were taken on GitHub's runners on 2026-10-09 and 2026-10-10 (run IDs are
   cited where they matter) and cannot be reproduced from this repository alone: they need a runner, the lock and, for the
   Claude probes, a Claude token. Merging accepts them as recorded; a founder re-checks the pins at the next bump and the
   probes by starting `egress-lock-claude.yml` (decision 3).
3. **The Claude jobs run under the lock for the first time after merge.** Before merge they are checked statically
   (`scripts/check-workflows.sh`), and the lock itself runs on a real runner in `egress-lock-test.yml` (jobs `lock` and
   `break-on-purpose`). The jobs that need a Claude token or an OIDC token (`egress-lock-claude.yml`: the `Skill(payload)`
   deny probe, the subprocess-isolation scrub probe, the `reads` probe and the `oidc` job; the manager, review, mention
   answers, reports) never run next to PR
   code, so they first run under the lock after merge. Right after merging, a founder starts `egress-lock-claude.yml` by
   hand (Actions -> Run workflow) and reads its result; a failure there is a revert trigger (the founder reverts the merge
   in the web UI and the fix comes as a new founder PR).
4. **What the agents' token can still do (2026-10-10).** The free plan cannot block pushes to `main` or repository
   creation by the agents' account. Accepted with these controls: `main-guard.yml` reverts any non-founder push to
   `main`, cancels and disables every workflow that holds a secret or write scope and opens a blocked security issue;
   the pusher ledger in `guards` keeps non-founder commits out of founder-only changes; the owns-no-repositories check
   stops every agent job (hourly with the manager; the daily report lists the failed runs) if the agents' account ever
   owns a repository; the manager denies `gh repo`, `gh workflow`, `gh run cancel` and `gh run delete`; and
   `scripts/check-agent-token.sh` (start and end of every shift) fails unless `main-guard.yml`, `pusher-ledger.yml`,
   `guards.yml` and `review.yml` are active and the default branch's head has a successful main-guard run, because the
   agents' token (classic `repo` covers the Actions API) could disable those workflows or cancel their runs - a
   residual risk: between such a tampering and the next shift start nothing runs, and the failing check is what tells
   a founder. Measured 2026-10-10 on this repository with a token that lacks the workflow permission: GitHub refuses
   any ref update that changes `.github/workflows/`, even a rewind of `main` to an older commit with no new commits
   (`refusing to allow a GitHub App to create or update workflow ... without workflows permission`; a classic token
   without the `workflow` scope, like the agents', gets the same refusal), so the agents' token cannot roll `main`
   back past a workflow change either. Two more routes closed in round 14: a push whose head commit says `[skip ci]`
   starts no main-guard run, so every run (and an hourly schedule) checks that the previous push's head passed the guard
   and stops the agents if not; and a re-run of an old workflow run would get today's secrets with yesterday's workflow
   file, so every secret-holding job runs only on a run's first attempt and the secrets were renamed to `..._V2` (the old
   names hold nothing). These detect and undo rather than prevent; prevention (rulesets, a fine-grained
   token) needs a paid plan or an organization-owned repository and is a later founder issue.
