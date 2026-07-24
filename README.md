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
