# Agent dev-environment image (see docs/ai-agents-in-docker-spec.md).
#
# Reuses the same Playwright base as the CI test image (tic-tac-toe/Dockerfile),
# so Node and a clean, cookie-free Chromium are preinstalled and the Playwright
# version matches @playwright/test in the client workspace.
FROM mcr.microsoft.com/playwright:v1.50.0-noble

# System tooling:
#   git                 - version control for the agent
#   iptables + ipset    - egress allowlist firewall (init-firewall.sh)
#   dnsutils            - dig, used to resolve allowlisted domains -> ipset
#   gosu                - drop from root to the non-root user after firewall setup
#   ca-certificates,curl- TLS + smoke tests
RUN apt-get update && apt-get install -y --no-install-recommends \
      git \
      iptables \
      ipset \
      dnsutils \
      gosu \
      ca-certificates \
      curl \
    && rm -rf /var/lib/apt/lists/*

# iptables-legacy is far more reliable than the nft backend inside containers.
RUN update-alternatives --set iptables /usr/sbin/iptables-legacy || true \
    && update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy || true

# Claude Code CLI. Pinned for supply-chain reproducibility (do NOT use "latest"
# in a real setup). Override at build time with --build-arg CLAUDE_CODE_VERSION=...
ARG CLAUDE_CODE_VERSION=2.1.218
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}

# In-container Claude config dir. This is decoupled from the host dir name
# (~/.claude-mike): agent-run.sh mounts the host creds read-only at
# /opt/claude-config-ro, and entrypoint.sh seeds them into this path, which lives
# on a tmpfs (writable, ephemeral). Result: host credentials cannot be modified
# and poisoned session state cannot persist between runs.
#
# NOTE: this carries auth only for FILE-based credentials (.credentials.json). If
# host auth lives in the macOS Keychain, Claude Code will prompt for login on
# first run inside the container (allowed via api.anthropic.com in the firewall).
ENV CLAUDE_CONFIG_DIR=/home/pwuser/.claude

WORKDIR /workspace

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY init-firewall.sh /usr/local/bin/init-firewall.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/init-firewall.sh

# Container starts as root so the firewall can be applied; entrypoint.sh then
# drops to the non-root "pwuser" (uid 1000, provided by the Playwright base).
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash", "-l"]
