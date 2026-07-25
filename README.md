# Running AI Agents Safely Workshop

The `tic-tac-toe` app is an npm workspaces monorepo with a `server` (Express + tsx)
and a `client` (React + Vite).

## Setup

```
cd tic-tac-toe
npm install
```

## Development

Runs the server and client together:

```
npm run dev
```

## Production build & start

Build both workspaces, then run the compiled server and client together:

```
npm run build
npm start
```

## Tests

Run everything (server unit tests + client E2E):

```
npm test
```

Or run a single suite:

```
npm run test:server        # Vitest unit tests (server)
npm run test:e2e           # Playwright E2E (headless)
npm run test:e2e:headed    # Playwright E2E in a visible browser
```

## Running tests in Docker

Uses the official `mcr.microsoft.com/playwright:v1.50.0-noble` image, so the
browsers are preinstalled and match the Playwright version. Requires a running
Docker daemon.

```
npm run docker:build       # build the test image
npm run docker:test        # run the full suite in a container
```

`docker:test` runs `npm test` inside the container; the Playwright config starts
the Vite server itself, so no extra services or port mapping are needed.

## Developing in a sandboxed agent container

Run Claude Code inside a locked-down container: the project is the only writable
path, outbound network is default-deny (allowlist: Anthropic API, npm, GitHub),
credentials are mounted read-only, and the browser is clean. See
[`docs/ai-agents-in-docker-spec.md`](docs/ai-agents-in-docker-spec.md) for the design.

```
scripts/agent-build.sh          # build the agent image (agent-dev:latest)
scripts/agent-run.sh claude     # start the sandbox and launch Claude Code
scripts/agent-run.sh            # or drop into a shell at /workspace
```

**Auth:** on macOS your subscription login lives in the Keychain, which the container
can't read, so it isn't carried by the read-only config mount. Generate a long-lived
token once on the host and export it before running (the script forwards it in):

```
claude setup-token                        # opens a browser; prints a token
export CLAUDE_CODE_OAUTH_TOKEN=<token>     # or export ANTHROPIC_API_KEY=<key>
```

Without it, Claude Code will show its login / API-billing screen inside the container.

Inside the container, work as usual (e.g. `cd tic-tac-toe && npm ci && npm test`).
Then **review and commit on the host** — the container cannot push.

Defaults are overridable via env vars (see the script headers):

```
PROJECT_DIR=$PWD/tic-tac-toe scripts/agent-run.sh   # mount only tic-tac-toe
CLAUDE_CREDS_DIR=~/.claude-mike                      # host Claude config (read-only)
ALLOW_TELEMETRY=1                                    # also allowlist telemetry
```

### Running on Windows (WSL2)

The sandbox itself is a Linux container, so every security control — the read-only
root filesystem, tmpfs scratch, non-root user, and the `iptables`/`ipset` egress
firewall (`--cap-add=NET_ADMIN`) — runs unchanged on Windows. Nothing in the
Dockerfile, `entrypoint.sh`, or `init-firewall.sh` needs editing. The only friction is
that the helper scripts are bash and assume Unix host paths, which WSL2 resolves.

1. **Install Docker Desktop with the WSL2 backend** (Settings → General → *Use the
   WSL 2 based engine*). This gives the container a real Linux kernel, which the
   firewall requires. The legacy Hyper-V backend is not supported.

2. **Run everything from inside a WSL2 shell** (e.g. Ubuntu), not `cmd.exe` or
   PowerShell. Keep the repo and your Claude config dir **inside the WSL2 filesystem**
   (e.g. `~/projects/...` in Ubuntu, not `/mnt/c/...`). Native Linux paths make the
   bind mounts in `agent-run.sh` work as-is and are much faster than crossing the
   Windows↔WSL2 boundary.

3. **Authenticate with a token.** There is no macOS Keychain fallback on Windows, so
   the token step is required, not optional:

   ```
   claude setup-token                        # run once; prints a token
   export CLAUDE_CODE_OAUTH_TOKEN=<token>     # or export ANTHROPIC_API_KEY=<key>
   ```

Then build and run exactly as above (`scripts/agent-build.sh`, `scripts/agent-run.sh`)
from the WSL2 shell.

> Running the scripts from **Git Bash** instead of WSL2 also works, but Git Bash
> rewrites container paths like `/workspace` into Windows paths. Prefix commands with
> `MSYS_NO_PATHCONV=1` if you go that route. WSL2 avoids this entirely.
