# Playwright image ships Node.js + browsers matching this exact version.
FROM mcr.microsoft.com/playwright:v1.50.0-noble

WORKDIR /app

# Install dependencies first for better layer caching.
COPY package.json package-lock.json ./
COPY client/package.json ./client/
COPY server/package.json ./server/
RUN npm ci

# Copy the rest of the source.
COPY . .

# Run the E2E suite (Playwright config starts the Vite server itself).
CMD ["npm", "run", "test"]
