# Playwright base image ships Chromium + all system libs + Node 20 + Xvfb.
# IMPORTANT: keep this tag's version in lockstep with the "playwright" version
# in package.json (1.49.0). Bump both together.
FROM mcr.microsoft.com/playwright:v1.49.0-jammy

WORKDIR /app

# Install deps first (better layer caching). package-lock.json may not exist on a
# fresh checkout — fall back to `npm install` if so.
COPY package*.json ./
RUN npm ci || npm install

# Build TypeScript → dist/
COPY . .
RUN npm run build

ENV NODE_ENV=production
# Run a real (non-headless) Chromium — far better Cloudflare Turnstile pass rate.
ENV HEADLESS=false
ENV PORT=8080
EXPOSE 8080

# xvfb-run gives the headful browser a virtual display.
CMD ["xvfb-run", "--auto-servernum", "--server-args=-screen 0 1280x1024x24", "npm", "run", "start"]
