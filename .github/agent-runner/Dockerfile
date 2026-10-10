# Agent runner image: one throwaway container per GitHub Actions job on a founder's PC (founder-owned file).
# Built by `.github/agent-runner/agent-runner.sh build`; runs under rootless Docker with the flags in that script.
# Everything is pinned: the base image by digest, the Actions runner by sha256, packages from the image's apt snapshot.
# The network lock (.github/actions/agent-egress-lock, container mode) runs inside the job; it needs the packages below.
FROM ubuntu:24.04@sha256:534baea6a22c03a63003dbc8dbe78fe34bc0d7e595d9a9dc9834884ff530eb55

ARG RUNNER_VERSION=2.337.0
ARG RUNNER_SHA256=70920811a4f8ad4328818682bca5c6469c1c942fab52448868071d0063816613

ENV DEBIAN_FRONTEND=noninteractive
# The network lock reads these; the job (and Claude) inherit them.
ENV AGENT_LOCK_CONTAINER=1 \
    RUNNER_TOOL_CACHE=/opt/hostedtoolcache \
    RUNNER_ALLOW_RUNASROOT=0

# Packages the lock installs on GitHub's runners (dnsmasq, nginx stream, bubblewrap, socat), the tools agents' jobs use
# (git, gh, jq, python3, node comes from setup-node at lock time, yarn through corepack), and what the Actions runner needs.
RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends \
      ca-certificates curl git gh jq python3 python3-venv unzip zip tar gzip xz-utils openssl \
      sudo iptables dnsmasq-base nginx libnginx-mod-stream bubblewrap socat \
      libicu74 libkrb5-3 zlib1g liblttng-ust1t64 libssl3t64 \
    && rm -rf /var/lib/apt/lists/* \
    # No setuid helpers for user-namespace mappings (the lock also strips them; see agent-network-lock.md).
    && rm -f /usr/bin/newuidmap /usr/bin/newgidmap \
    # The job user: not root (the Actions runner refuses root); sudo until the lock removes it.
    && useradd --create-home --uid 1001 --shell /bin/bash runner \
    && echo 'runner ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/runner && chmod 0440 /etc/sudoers.d/runner \
    && mkdir -p /opt/hostedtoolcache /actions-runner && chown runner:runner /opt/hostedtoolcache /actions-runner

# The Actions runner, pinned. --disableupdate at config time: upgrades happen by rebuilding this image.
WORKDIR /actions-runner
RUN curl -fsSL -o runner.tgz "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz" \
    && echo "${RUNNER_SHA256}  runner.tgz" | sha256sum --check --quiet \
    && tar -xzf runner.tgz && rm -f runner.tgz \
    && chown -R runner:runner /actions-runner

COPY --chmod=0755 entrypoint.sh /usr/local/bin/agent-runner-entrypoint
USER runner
ENTRYPOINT ["/usr/local/bin/agent-runner-entrypoint"]
