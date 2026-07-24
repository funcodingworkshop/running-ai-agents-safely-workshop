#!/usr/bin/env bash
# Build the agent dev-environment image (see docs/ai-agents-in-docker-spec.md §5.5).
#
# Env overrides:
#   AGENT_IMAGE           image tag to build            (default: agent-dev:latest)
#   CLAUDE_CODE_VERSION   pinned Claude Code version    (default: image default)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_CONTEXT="$REPO_ROOT/docker/agent"

IMAGE_TAG="${AGENT_IMAGE:-agent-dev:latest}"

build_args=()
if [ -n "${CLAUDE_CODE_VERSION:-}" ]; then
  build_args+=(--build-arg "CLAUDE_CODE_VERSION=${CLAUDE_CODE_VERSION}")
fi

echo "Building $IMAGE_TAG from $BUILD_CONTEXT/agent.Dockerfile"
docker build \
  -f "$BUILD_CONTEXT/agent.Dockerfile" \
  ${build_args[@]+"${build_args[@]}"} \
  -t "$IMAGE_TAG" \
  "$BUILD_CONTEXT"

echo "Done: $IMAGE_TAG"
