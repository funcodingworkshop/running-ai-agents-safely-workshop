#!/usr/bin/env bash
# Start an interactive agent container (see docs/ai-agents-in-docker-spec.md §5.5).
#
# The container:
#   - mounts the project read-write at /workspace (the only durable writable path)
#   - mounts host Claude creds READ-ONLY (seeded into an ephemeral config at start)
#   - runs with a read-only root filesystem + tmpfs scratch, as a non-root user
#   - applies a default-deny egress firewall (needs --cap-add=NET_ADMIN)
#
# Env overrides:
#   AGENT_IMAGE        image tag to run             (default: agent-dev:latest)
#   PROJECT_DIR        host project to mount rw     (default: repo root)
#   CLAUDE_CREDS_DIR   host Claude creds (ro)       (default: ~/.claude-mike)
#   AGENT_NETWORK      docker network name          (default: agent-net)
#   ALLOW_TELEMETRY    1 to allowlist telemetry     (default: 0)
#
# Any extra args are passed as the container command, e.g.:
#   scripts/agent-run.sh claude          # launch Claude Code directly
#   scripts/agent-run.sh                 # drop into a shell
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

IMAGE_TAG="${AGENT_IMAGE:-agent-dev:latest}"
PROJECT_DIR="${PROJECT_DIR:-$REPO_ROOT}"
CLAUDE_CREDS_DIR="${CLAUDE_CREDS_DIR:-$HOME/.claude-mike}"
AGENT_NETWORK="${AGENT_NETWORK:-agent-net}"
ALLOW_TELEMETRY="${ALLOW_TELEMETRY:-0}"

if [ ! -d "$PROJECT_DIR" ]; then
  echo "ERROR: project dir not found: $PROJECT_DIR" >&2
  exit 1
fi
if [ ! -d "$CLAUDE_CREDS_DIR" ]; then
  echo "ERROR: Claude creds dir not found: $CLAUDE_CREDS_DIR" >&2
  echo "       Set CLAUDE_CREDS_DIR to your host Claude config dir." >&2
  exit 1
fi

# Authentication. On macOS the subscription login lives in the Keychain, which the
# container cannot read, so it is NOT carried by the read-only config mount. Generate
# a long-lived token on the host once (`claude setup-token`) and export it, or export
# an API key; either is forwarded into the container when set.
auth_env=()
if [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
  auth_env+=(-e "CLAUDE_CODE_OAUTH_TOKEN=$CLAUDE_CODE_OAUTH_TOKEN")
elif [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  auth_env+=(-e "ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY")
else
  echo "WARN: neither CLAUDE_CODE_OAUTH_TOKEN nor ANTHROPIC_API_KEY is set." >&2
  echo "      Claude Code will prompt for login inside the container." >&2
  echo "      Fix: run 'claude setup-token' on the host, then" >&2
  echo "           export CLAUDE_CODE_OAUTH_TOKEN=<token> before running this script." >&2
fi

# Dedicated network (idempotent).
docker network inspect "$AGENT_NETWORK" >/dev/null 2>&1 \
  || docker network create "$AGENT_NETWORK" >/dev/null

exec docker run --rm -it \
  --name agent-dev \
  --network "$AGENT_NETWORK" \
  --cap-add NET_ADMIN \
  --read-only \
  --tmpfs /tmp:exec,mode=1777 \
  --tmpfs /run:mode=0755 \
  --tmpfs /home/pwuser:exec,mode=0777 \
  -v "$PROJECT_DIR:/workspace" \
  -v "$CLAUDE_CREDS_DIR:/opt/claude-config-ro:ro" \
  -e "ALLOW_TELEMETRY=$ALLOW_TELEMETRY" \
  ${auth_env[@]+"${auth_env[@]}"} \
  -w /workspace \
  "$IMAGE_TAG" "$@"
