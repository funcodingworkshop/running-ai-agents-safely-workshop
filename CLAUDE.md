# CLAUDE.md

Guidance for AI agents working in this repo. See `README.md` for full docs and
`docs/ai-agents-in-docker-spec.md` for the sandbox design.

## Project

`tic-tac-toe/` is an npm-workspaces monorepo:
- `server/` — Express + TypeScript (tsx dev), runs on port **5000**
- `client/` — React + Vite, runs on port **5173** (dev-server proxies `/api` → 5000)

## Testing

```
cd tic-tac-toe
npm ci            # install dependencies (respects the lockfile)
npm test          # server unit tests (Vitest) + client E2E (Playwright)
```

Single suites: `npm run test:server`, `npm run test:e2e`. Playwright's config
starts the Vite + Express servers itself, so no manual server startup is needed.

## Playwright browsers — do NOT install them

The container image (`docker/agent/agent.Dockerfile`, based on
`mcr.microsoft.com/playwright:v1.50.0-noble`) already ships the browser binaries at
`/ms-playwright` (env `PLAYWRIGHT_BROWSERS_PATH` points there), matched to
Playwright **1.50.0**.

- **Never run `npx playwright install` / `playwright install`.** The browsers are
  already present; `npm ci` is all you need.
- In the sandbox, outbound network is **default-deny** (only Anthropic API, npm, and
  GitHub are allowlisted). Browser downloads go to `cdn.playwright.dev`, which is
  **blocked** — so `playwright install` will hang forever, not fail fast.
- Keep `@playwright/test` pinned to **1.50.0** so it uses the pre-baked browsers. If a
  Playwright upgrade is ever required, bump the image's base tag to the matching
  `mcr.microsoft.com/playwright:vX.Y.Z-noble` version instead of downloading browsers
  at runtime.

## Sandbox notes

- The mounted project (`/workspace`) is the only writable path; the rest of the
  filesystem is read-only. Write your changes there.
- Commits/pushes happen on the **host** after human review — don't rely on git push
  from inside the container.
