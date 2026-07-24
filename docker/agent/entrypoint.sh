#!/usr/bin/env bash
# Container entrypoint (see docs/ai-agents-in-docker-spec.md §5).
#
# Runs as root so it can apply the egress firewall, seeds an ephemeral Claude
# config from the read-only host mount, then drops to the non-root user for the
# actual work.
set -euo pipefail

# 1. Apply the egress allowlist firewall (needs NET_ADMIN).
if [ "$(id -u)" = "0" ]; then
  /usr/local/bin/init-firewall.sh
else
  echo "WARN: entrypoint not running as root; skipping firewall. Do not override USER." >&2
fi

# 2. Seed a writable, ephemeral Claude config (on tmpfs) from the read-only host
#    credential mount. Host creds stay read-only; this copy is discarded on exit.
RO_CONF=/opt/claude-config-ro
if [ -d "$RO_CONF" ]; then
  mkdir -p "$CLAUDE_CONFIG_DIR"
  cp -a "$RO_CONF/." "$CLAUDE_CONFIG_DIR/" 2>/dev/null || true
  echo "[entrypoint] seeded $CLAUDE_CONFIG_DIR from $RO_CONF (read-only source)"
else
  echo "[entrypoint] WARN: no host Claude config mounted at $RO_CONF" >&2
fi

# 3. Make the tmpfs-backed home writable by the non-root user.
chown -R pwuser:pwuser /home/pwuser 2>/dev/null || true

# 4. Drop privileges and run the requested command as the non-root user.
exec gosu pwuser "$@"
