# Runbook: the agents' runners on the founders' PCs

Every job with a Claude step (`agent-manager.yml`, `review.yml`, `agent-daily-report.yml`, `agent-weekly-audit.yml`,
`claude.yml`, `egress-lock-claude.yml`) and the container-mode lock test in `egress-lock-test.yml` run on
`runs-on: [self-hosted, agents]`: GitHub Actions runners on the founders' own Linux PCs, so the agents work 24/7 at no GitHub
cost. The short checks (`ci.yml`, `guards.yml`, the hosted lock tests) stay on GitHub's machines inside the free plan's
~2,000 minutes a month. Files: `.github/agent-runner/` (founder-owned).

## How a job runs on a PC
- **One throwaway container per job.** A lane (`agent-runner.sh lane <n>`) asks GitHub for a one-hour registration token
  with the founder's `gh` login, starts a container from the `agent-runner:current` image and hands the token over on
  stdin. Inside, the pinned Actions runner registers itself as **ephemeral**, runs exactly one job and exits; Docker deletes
  the container (`--rm`). The lane then starts the next one. Nothing from one job survives into the next.
- **Rootless Docker.** The Docker daemon runs as the founder's user, so "root" inside a container is an unprivileged user on
  the PC. The job itself runs as the container's `runner` user (the Actions runner refuses root).
- **No capabilities except what the lock needs**: `--cap-drop ALL`, then `NET_ADMIN` and `NET_BIND_SERVICE` (the firewall,
  DNS and proxy inside the container's own network namespace), `SETUID`/`SETGID`/`CHOWN`/`FOWNER`/`DAC_OVERRIDE`/`AUDIT_WRITE`
  (sudo, service users, writing `/etc`). The lock removes sudo before Claude starts, so the job holds none of them; the
  self-test checks `CapEff` is 0. Never `--privileged`, never `SYS_ADMIN` (the guard fails the PR).
- **Seccomp**: Docker's default profile plus the user-namespace calls bubblewrap needs (Claude Code's subprocess isolation):
  `.github/agent-runner/seccomp.json`, derived by `make-seccomp.py` from the vendored `docker-default-seccomp.json`
  (Apache-2.0, `NOTICE.md`). The guard regenerates it and fails on any hand edit.
- **Limits per container**: 4 GB memory (no swap), `nproc / lanes` CPUs, 4096 processes.
- **The network lock in container mode** (`AGENT_LOCK_CONTAINER=1`, set by the image): same allow-list, dnsmasq, SNI proxy,
  firewall, sudo removal and self-test as on GitHub's runners (`docs/runbooks/agent-network-lock.md`). Differences: no
  AppArmor or sysctl (host settings; the container boundary takes their place), `/etc/resolv.conf` is rewritten in place
  (Docker bind-mounts it), the upstream DNS server is the one `--dns` passes (the PC's own), and the self-test adds `the job
  runs as root in the container` / `the job's processes hold capabilities (CapEff is not 0)`; `no upstream DNS server in
  /etc/resolv.conf` means the lane's `--dns` value is missing or loopback (re-run `setup`).
- **Pins**: the base image by digest, the Actions runner by version and sha256 (`Dockerfile`; `--disableupdate`, upgrades
  happen by rebuilding), packages from the image's apt snapshot; Claude Code, Bun, gitleaks and Node come from the lock at
  job time, checked against their pinned checksums, before the network closes.
- **Tokens**: the founder's GitHub login stays in `gh` on the PC (never in a file of ours, never in a container). The
  registration token is single-use for registering and expires after an hour. The runner's own credentials live only inside
  the container and die with it. `AGENT_GH_TOKEN` and the Claude token reach the job the same way as before (GitHub secrets).

## Setup on a PC (founder, once)
Requirements: Linux x86_64 with 16 GB RAM or more (3 lanes), Docker Engine in **rootless mode** for your user, `gh` logged
in as the founder, a checkout of this repository.
```bash
# 1. Docker Engine + rootless mode (Ubuntu/Debian; see https://docs.docker.com/engine/security/rootless/)
sudo apt-get install -y uidmap dbus-user-session docker-ce docker-ce-rootless-extras   # after adding Docker's apt repository
dockerd-rootless-setuptool.sh install
docker info --format '{{.SecurityOptions}}'      # must contain "rootless"
# 2. GitHub login (the founder's own account; it authorizes runner registration)
gh auth login
# 3. From the repository checkout, on main:
bash .github/agent-runner/agent-runner.sh setup 3   # lanes: 3 per 16 GB; asks sudo for the two host settings below
bash .github/agent-runner/agent-runner.sh build     # builds agent-runner:current (a few minutes the first time)
bash .github/agent-runner/agent-runner.sh check     # runs the lock inside one container; must end with "check OK"
bash .github/agent-runner/agent-runner.sh start     # 3 lanes as user services, back after reboots
bash .github/agent-runner/agent-runner.sh status
```
`setup` changes two host settings with sudo and keeps them across reboots: it loads the firewall kernel modules the
containers cannot load themselves (`/etc/modules-load.d/agent-runner.conf`: `nf_tables nf_conntrack nf_nat nft_compat
nft_redir xt_owner`), and it sets `kernel.apparmor_restrict_unprivileged_userns=0` (`/etc/sysctl.d/80-agent-runner.conf`)
because Ubuntu 24.04's restriction would strip the capabilities bubblewrap needs inside the containers. **Founder decision
(Mohammed, 2026-10-10):** the PCs are dedicated to the agents and the rootless containers are the boundary, so that host
switch is off there. Do not run the lanes on a PC you also use for other work.

More PCs: repeat the setup on each; every PC adds its lanes to the same `agents` pool. More lanes on one PC: `setup <n>` again,
then `stop` and `start`. The Claude plan's weekly limit is shared by every lane; when it is reached the jobs fail at the
Claude step until it resets, and the hourly schedule simply tries again.

## Upgrades (monthly, with the DevOps upgrade)
- Runner: new `RUNNER_VERSION`/`RUNNER_SHA256` in the `Dockerfile` (sha256 from the release notes at
  https://github.com/actions/runner/releases), new base digest if any, then on each PC: `git pull`, `build`, `check`,
  `stop`, `start`. GitHub refuses runners that fall too far behind the current version.
- Docker's seccomp profile: replace `docker-default-seccomp.json` from the moby tag named in `NOTICE.md`, regenerate
  `seccomp.json` (`python3 -I make-seccomp.py docker-default-seccomp.json seccomp.json`), update `NOTICE.md`.
- Claude Code, Bun, gitleaks: the lock's pins (`docs/runbooks/agent-network-lock.md`); no image rebuild needed.

## When something fails
- `check` says `tools do not work inside bubblewrap` - the host switch above is still on, or user namespaces are off
  (`sysctl user.max_user_namespaces`). `api.github.com not reachable through the lock` - the `--dns` server from `setup` is
  wrong for this network (re-run `setup`), or the kernel modules are missing (`sudo modprobe ...` as in `setup`).
- `setup` says `Docker is not in rootless mode for this user` - finish step 1; `gh is not logged in` - step 2; `cannot find
  this PC's DNS server` - set it by hand in `~/.config/agent-runner/env` (`DNS=<ip>`).
- A lane logs `no registration token (offline, or gh not logged in); retrying in 60s` - the PC is offline or the `gh` login
  expired (`gh auth login` again). `journalctl --user -u agent-lane@1 -f` follows a lane.
- Jobs stay queued on GitHub ("Waiting for a runner") - no lane is online: `status` on each PC, `start` if needed.
- The container fails before the lock (`config.sh` errors) - the registration token was refused (clock skew, revoked login);
  the lane retries by itself.
- A job ends and the runner "disappears" from GitHub's runner list: normal for ephemeral runners.

## The guard: `scripts/check-agent-runner.sh`
Runs in `guards` (the `main` copy on the PR's `.github/agent-runner` as data) and in CI. Messages: `missing <file>`;
`seccomp.json differs from make-seccomp.py's output: regenerate it (...)`; `make-seccomp.py failed`; `seccomp.json must deny
by default`; `Dockerfile: FROM must be ubuntu:<version>@sha256:<digest>` / `exactly one FROM` / `ARG RUNNER_VERSION=<x.y.z>` /
`ARG RUNNER_SHA256=<64 hex>` / `the runner download must be checked against RUNNER_SHA256` / `ENV AGENT_LOCK_CONTAINER=1` /
`USER runner (jobs never run as root)` / `remove the setuid helpers newuidmap/newgidmap` / `only the pinned runner download
may use curl/wget` / `no :latest tags`; `entrypoint.sh does not parse` / `agent-runner.sh does not parse`; `the registration
token must go to the container on stdin` / `must be read from stdin`; `containers must start with --cap-drop ALL` / `must use
seccomp.json` / `no SYS_ADMIN or --privileged`; `NOTICE.md must name docker-default-seccomp.json and its Apache-2.0 license`.
Each names the file and the rule; fix the file in a founder PR. Tests: `scripts/check-agent-runner.test.sh` (the guard on
broken copies, and the host script with stubbed `docker`, `gh`, `systemctl` and `sudo`).

## Known limits
- The container is the boundary on the PC: a job that escaped Docker's isolation would still be an unprivileged user there.
  The PC must not hold anything else of value (no founder credentials beyond the `gh` login, no customer data).
- GitHub's runner must reach its own services (`*.actions.githubusercontent.com`, Azure log storage) to report results; the
  lock keeps the connections it opened before closing, as on GitHub's machines. If a job's log upload ever fails, the job
  shows as failed; re-run it.
- Container mode has no AppArmor: a program in the container can create user namespaces, but it holds no capability in the
  container's network namespace, so it cannot change the firewall, and it has nothing to escalate to.
