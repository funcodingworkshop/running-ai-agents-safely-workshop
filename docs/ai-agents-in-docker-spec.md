# AI Agents in Docker — Specification

**Status:** Implemented · **Companion to:** [`ai-agents-in-docker-vision.md`](./ai-agents-in-docker-vision.md)

**Implementation:** `docker/agent/agent.Dockerfile`, `docker/agent/init-firewall.sh`,
`docker/agent/entrypoint.sh`, `scripts/agent-build.sh`, `scripts/agent-run.sh`.
Build with `scripts/agent-build.sh`, then enter with `scripts/agent-run.sh` (or
`scripts/agent-run.sh claude` to launch Claude Code directly).

## 1. Overview

This document turns the [vision note](./ai-agents-in-docker-vision.md) into a concrete,
testable specification for running an autonomous coding agent (Claude Code) inside a Docker
container. The goal is a reproducible, sandboxed development environment where the agent has
everything it needs to work on this repo — run unit and end-to-end tests, edit source — while
its blast radius is contained: writes are confined to the mounted project, outbound network
access is restricted to an allowlist, credentials are read-only, and the human reviews and
commits changes on the host.

This spec covers **what to build and how to verify it**. It intentionally does *not* include
the implementation (the `agent.Dockerfile`, scripts, and firewall init are specified here but
authored in a follow-up task).

## 2. Goals / Non-goals

### Goals
- A single, reproducible agent image containing Node, Claude Code CLI, git, and the test
  toolchain (Playwright + Chromium, Vitest).
- The project mounted as a volume and made the **only** durable writable location.
- Claude auth credentials mapped in **read-only** from the host `~/.claude-mike`.
- Outbound network **default-deny** with a small allowlist (Anthropic API, npm, GitHub).
- A clean, cookie-free browser for visual/E2E tests — never the host Chrome profile.
- Editor-agnostic orchestration: an `agent.Dockerfile` plus `build`/`run` helper scripts.

### Non-goals (this iteration)
- docker-compose or VS Code devcontainer orchestration.
- Multi-agent / parallel-agent orchestration.
- Browsers other than Chromium.
- Host-level firewall changes or Windows host support (targets macOS + Docker Desktop / Linux).
- Automated commit or push from inside the container — commits are a human host action.

## 3. Threat model → control mapping

Each risk from the vision doc maps to a concrete control in this spec.

| Risk (from vision) | Control |
| --- | --- |
| Prompt injection | Egress allowlist (§5.3) limits where an injected instruction can send data; write confinement (§5.2) limits what it can alter; human review before commit (§6). |
| Over-privileged access | Non-root container user; `--read-only` root filesystem; single writable project volume (§5.2). |
| Big blast radius | Container isolation; no host paths mounted except the project (rw) and creds (ro); host-side review + commit (§6). |
| Data exfiltration | Default-DROP outbound firewall with a minimal allowlist (§5.3); no host Chrome cookies/session available to leak (§5.4). |
| Insufficient oversight of irreversible actions | Container holds no push/deploy credentials; all git commit/push happen on the host after human diff review (§6). |
| Tool & supply-chain compromise | Pinned base image and pinned Claude Code version (§5.1); egress allowlist blocks unexpected download sources (§5.3). |
| Memory & state poisoning | Credentials/auth mounted read-only; Claude session/config scratch lives on ephemeral tmpfs that is discarded per run (§5.2). |

## 4. Architecture

```
  HOST (macOS / Linux)                          CONTAINER (agent image)
  ─────────────────────                         ────────────────────────
  ~/projects/.../repo   ──(bind mount, rw)──▶   /workspace              (only durable RW path)
  ~/.claude-mike        ──(bind mount, ro)──▶   $CLAUDE_CONFIG_DIR/creds (read-only)
                                                 tmpfs → /tmp, ~/.cache, session scratch (RW, ephemeral)
                                                 rootfs: --read-only

  human: reviews diff,   ◀── git status/commit   claude code + node + chromium (non-root user)
         commits, pushes      on host only        │
                                                   └─▶ egress firewall (default DROP)
                                                         allow: api.anthropic.com,
                                                                registry.npmjs.org,
                                                                github.com / *.githubusercontent.com,
                                                                DNS, loopback
                                                         drop:  everything else
```

Components:
- **Agent image** — built from `agent.Dockerfile`, extends the Playwright base already used by
  the repo's CI test image.
- **Volume mounts** — project (rw) and credentials (ro); nothing else from the host.
- **Network + firewall** — a dedicated docker network and an `init-firewall.sh` applied at
  container start.
- **Container user** — non-root, owns `/workspace`.
- **Host↔container boundary** — the human writes prompts, reviews the resulting diff, and runs
  git on the host.

## 5. Detailed requirements

### 5.1 Agent image (`agent.Dockerfile`)

- **Base:** `mcr.microsoft.com/playwright:v1.50.0-noble` — same base as the existing CI test
  image (`tic-tac-toe/Dockerfile`), so Node and a clean Chromium are preinstalled and the
  Playwright version matches `@playwright/test@^1.50.0`.
- **Add:** `git`; `iptables` + `ipset` (for the firewall); `@anthropic-ai/claude-code`
  installed globally via npm.
- **Pin for supply-chain reproducibility:** the base image tag is already pinned; also pin the
  Claude Code version (e.g. `npm i -g @anthropic-ai/claude-code@<version>`), not `latest`.
- **User:** create/keep a **non-root** user that owns `/workspace`; the container runs as this
  user.
- **Config:** set `CLAUDE_CONFIG_DIR` to a known path so the credential mount and session
  scratch land predictably.

**Acceptance:** image builds; inside it `claude --version`, `git --version`, `node --version`,
and a Chromium launch all succeed; `whoami` is not `root`.

### 5.2 Volume mounts & write confinement

- Mount the project **rw** at `/workspace` — the only durable writable path.
- Mount `~/.claude-mike` (or its auth/creds subset) **read-only** into `$CLAUDE_CONFIG_DIR`.
- Run the container with `--read-only` root filesystem, plus `tmpfs` mounts for `/tmp`, the npm
  cache, the browser cache, and Claude's session/config scratch. Combined with the non-root
  user, the mapped project volume is the only place durable writes can land.
- **Tradeoff (memory/state poisoning):** a fully read-only config dir can break Claude's need to
  write session state. Resolution: mount only the **auth/credential** material read-only, and
  back the writable portion of the config dir with **tmpfs** so session state is ephemeral and
  discarded when the container exits — poisoned state cannot persist across runs, and host
  credentials cannot be modified.

**Acceptance:** a write to `/workspace/<file>` succeeds and is visible on the host; a write to
`/etc/<file>` or `$HOME` outside the tmpfs paths fails; the host `~/.claude-mike` is unchanged
after a session.

### 5.3 Network egress (allowlist firewall)

- Attach the container to a dedicated docker network.
- Apply `init-firewall.sh` at container start (requires `--cap-add=NET_ADMIN`). It sets the
  default OUTPUT policy to **DROP** and allows only:
  - DNS resolution and loopback,
  - `api.anthropic.com` (Claude Code),
  - `registry.npmjs.org` (dependency installs),
  - `github.com` and `*.githubusercontent.com` (git + raw content),
  - *(optional, list explicitly)* Claude Code telemetry endpoints (e.g. statsig / sentry) — mark
    optional so they can be omitted for stricter setups.
- Resolve allowlisted domains to IPs and load them into an `ipset`; rules match the set. This
  follows the Anthropic devcontainer `init-firewall.sh` pattern (prior art) — reference that
  implementation rather than reinventing it.
- The exact endpoint list Claude Code requires is an open question (§8) — the firewall must be
  verified by the acceptance test below and adjusted if Claude Code fails to reach a needed host.

**Acceptance:** inside the container, `curl https://api.anthropic.com` and an `npm` install and a
`git fetch` from GitHub all succeed; `curl https://example.com` (a non-allowlisted host) fails
with a connection/timeout error.

### 5.4 Clean browser

- Visual/E2E tests use the Chromium bundled in the base image, launched by Playwright with a
  **fresh in-container profile**.
- **Prohibited:** mounting any host browser profile, cookie store, or session (e.g.
  `~/Library/Application Support/Google/Chrome`) into the container.

**Acceptance:** Playwright E2E tests run against a Chromium instance with an empty profile; no
host cookies/history are present in the container.

### 5.5 Helper scripts

- `scripts/agent-build.sh` — builds the agent image from `agent.Dockerfile` (tagged, e.g.
  `agent-dev`).
- `scripts/agent-run.sh` — starts an **interactive** container: applies all mounts (§5.2),
  `--read-only` + tmpfs, `--cap-add=NET_ADMIN`, the dedicated network; runs `init-firewall.sh`
  first, then drops the user into a shell (or launches `claude`).
- Scripts are **parameterized** (project path, image tag, credential dir) with sensible
  defaults — not hardcoded to one user or one absolute path — and are safe to re-run
  (idempotent).

**Acceptance:** a fresh clone can run `scripts/agent-build.sh && scripts/agent-run.sh` and land
in a working container with the firewall active and `/workspace` mounted.

## 6. Developer workflow

Mirrors the vision doc, made concrete:

1. Build the image: `scripts/agent-build.sh`.
2. Start the container: `scripts/agent-run.sh` (mounts project rw, creds ro; firewall applied).
3. Connect in (interactive shell / Claude Code session) and write a prompt.
4. Claude works within `/workspace`, running unit tests (Vitest) and E2E tests (Playwright
   Chromium) inside the container — see §7 for the exact command.
5. On the **host**, the human reviews the diff (`git status` / `git diff`) and commits/pushes.
   The container holds no push credentials by policy; irreversible git actions are a human step.

## 7. Acceptance criteria (end-to-end checklist)

The implementation is complete when all hold:

- [ ] Image builds from `agent.Dockerfile`; `claude`, `git`, `node`, and Playwright/Chromium are
      available and the container runs as a non-root user.
- [ ] `agent-run.sh` starts a container where `/workspace` is the mounted project and writable;
      writes outside `/workspace` (and the ephemeral tmpfs paths) fail.
- [ ] Egress: `api.anthropic.com`, `registry.npmjs.org`, and GitHub are reachable; any
      non-allowlisted host (e.g. `example.com`) is **not** reachable.
- [ ] Claude auth from `~/.claude-mike` works read-only; the host credential files are unchanged
      after a session; Claude session state does not persist between runs.
- [ ] `cd /workspace/tic-tac-toe && npm ci && npm run test` passes inside the container
      (Vitest server tests + Playwright Chromium E2E; Playwright self-starts the client on 5173
      and server on 5000).
- [ ] No host Chrome profile/cookies exist in the container.
- [ ] Commits/pushes are performed by the human on the host after diff review; the container is
      not used to push.

## 8. Open questions / future work

- **Exact Claude Code egress endpoints** — confirm the full set of hosts Claude Code needs
  (API, telemetry, updates) and finalize the allowlist; decide whether telemetry is allowed.
- **Consolidation with the CI test image** — whether to unify or clearly separate this agent-dev
  image from the existing `tic-tac-toe/Dockerfile` CI test-runner image.
- **Secrets handling** — how to inject any project secrets the agent may need without persisting
  them in the image or the writable volume.
- **Image size / build caching** — optimize layer caching and final image size once the toolset
  is finalized.
- **DNS re-resolution** — allowlisted domains behind rotating IPs (CDNs) may need periodic ipset
  refresh; decide whether the current start-time resolution is sufficient.
