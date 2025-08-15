# =============================================================================
# STAGE 1: Dependencies - Install and cache workspace dependencies
# =============================================================================
FROM oven/bun:1.2.8 AS deps

ENV REBUILD_DATE="2025-08-15-v4"

WORKDIR /app

# Copy workspace configuration
COPY package.json bun.lock ./

# Copy package.json files for all packages
COPY packages/db/package.json ./packages/db/
COPY packages/kv/package.json ./packages/kv/
COPY packages/ui/package.json ./packages/ui/
COPY packages/email/package.json ./packages/email/
COPY packages/integrations/package.json ./packages/integrations/
COPY packages/utils/package.json ./packages/utils/
COPY packages/tsconfig/package.json ./packages/tsconfig/
COPY packages/analytics/package.json ./packages/analytics/

# Copy app package.json files
COPY apps/app/package.json ./apps/app/
COPY apps/portal/package.json ./apps/portal/

# Install all dependencies
RUN PRISMA_SKIP_POSTINSTALL_GENERATE=true bun install

# =============================================================================
# STAGE 2: App Builder
# =============================================================================
FROM node:20-slim AS app-builder

WORKDIR /app

# Install bun in Node image
RUN apt-get update && apt-get install -y curl unzip && \
    curl -fsSL https://bun.sh/install | bash && \
    ln -s /root/.bun/bin/bun /usr/local/bin/bun && \
    rm -rf /var/lib/apt/lists/*

# Copy dependencies from deps stage
COPY --from=deps /app/node_modules ./node_modules
COPY --from=deps /app/package.json ./package.json
COPY --from=deps /app/bun.lock ./bun.lock

# Copy all source code needed for build
COPY packages ./packages
COPY apps/app ./apps/app

# Generate Prisma client using npx (Node is available)
RUN cd packages/db && npx prisma generate

# Build the app using bun
RUN cd apps/app && SKIP_ENV_VALIDATION=true bun run build

# =============================================================================
# STAGE 3: Portal Builder
# =============================================================================
FROM node:20-slim AS portal-builder

WORKDIR /app

# Install bun in Node image
RUN apt-get update && apt-get install -y curl unzip && \
    curl -fsSL https://bun.sh/install | bash && \
    ln -s /root/.bun/bin/bun /usr/local/bin/bun && \
    rm -rf /var/lib/apt/lists/*

# Copy dependencies from deps stage
COPY --from=deps /app/node_modules ./node_modules
COPY --from=deps /app/package.json ./package.json
COPY --from=deps /app/bun.lock ./bun.lock

# Copy all source code needed for build
COPY packages ./packages
COPY apps/portal ./apps/portal

# Generate Prisma client using npx (Node is available)
RUN cd packages/db && npx prisma generate

# Build the portal using bun
RUN cd apps/portal && SKIP_ENV_VALIDATION=true bun run build

# =============================================================================
# STAGE 4: Portal Production (Named stage for explicit selection)
# =============================================================================
FROM node:20-slim AS portal-production

WORKDIR /app

# Install bun
RUN apt-get update && apt-get install -y curl unzip && \
    curl -fsSL https://bun.sh/install | bash && \
    ln -s /root/.bun/bin/bun /usr/local/bin/bun && \
    rm -rf /var/lib/apt/lists/*

# Copy package files first
COPY --from=portal-builder /app/package.json ./
COPY --from=portal-builder /app/bun.lock ./

# Copy the entire portal app directory (includes all files)
COPY --from=portal-builder /app/apps/portal ./apps/portal

# Copy dependencies and packages
COPY --from=portal-builder /app/node_modules ./node_modules
COPY --from=portal-builder /app/packages ./packages

# Start from the app root
WORKDIR /app

# Add debug to see what's happening
RUN echo '#!/bin/sh' > /portal-start.sh && \
    echo 'echo "=== DEBUG: Portal Production Stage ==="' >> /portal-start.sh && \
    echo 'echo "Current directory: $(pwd)"' >> /portal-start.sh && \
    echo 'echo "Directory contents:"' >> /portal-start.sh && \
    echo 'ls -la' >> /portal-start.sh && \
    echo 'echo "Apps directory:"' >> /portal-start.sh && \
    echo 'ls -la apps/' >> /portal-start.sh && \
    echo 'exec bun run --cwd apps/portal start' >> /portal-start.sh && \
    chmod +x /portal-start.sh

EXPOSE 3000
CMD ["/portal-start.sh"]

# =============================================================================
# STAGE 5: Ultra-Minimal Migrator - Only Prisma
# =============================================================================
FROM node:20-slim AS migrator

WORKDIR /app

# Copy Prisma schema and migration files
COPY packages/db/prisma ./packages/db/prisma

# Create minimal package.json for Prisma
RUN echo '{"name":"migrator","type":"module","dependencies":{"prisma":"^6.13.0","@prisma/client":"^6.13.0"}}' > package.json

# Install ONLY Prisma dependencies using npm
RUN npm install

# Generate Prisma client
RUN cd packages/db && npx prisma generate

# Default command for migrations
CMD ["npx", "prisma", "migrate", "deploy", "--schema=packages/db/prisma/schema.prisma"]

# =============================================================================
# FINAL STAGE: App Production (DEFAULT - This is the default/final stage)
# =============================================================================
FROM node:20-slim AS production

WORKDIR /app

# Install bun
RUN apt-get update && apt-get install -y curl unzip && \
    curl -fsSL https://bun.sh/install | bash && \
    ln -s /root/.bun/bin/bun /usr/local/bin/bun && \
    rm -rf /var/lib/apt/lists/*

# Copy package files first
COPY --from=app-builder /app/package.json ./
COPY --from=app-builder /app/bun.lock ./

# Copy the entire app directory (includes all files)
COPY --from=app-builder /app/apps/app ./apps/app

# Copy dependencies and packages
COPY --from=app-builder /app/node_modules ./node_modules
COPY --from=app-builder /app/packages ./packages

# Simple start script using npx for migrations
RUN echo '#!/bin/sh' > /start.sh && \
    echo 'echo "=== DEBUG: Starting App Production Stage ==="' >> /start.sh && \
    echo 'echo "Current directory: $(pwd)"' >> /start.sh && \
    echo 'echo "Directory contents:"' >> /start.sh && \
    echo 'ls -la' >> /start.sh && \
    echo 'echo "Apps directory:"' >> /start.sh && \
    echo 'ls -la apps/' >> /start.sh && \
    echo 'echo "Running database setup..."' >> /start.sh && \
    echo 'cd /app/packages/db && npx prisma db push --accept-data-loss' >> /start.sh && \
    echo 'echo "Starting application..."' >> /start.sh && \
    echo 'cd /app && exec bun run --cwd apps/app start' >> /start.sh && \
    chmod +x /start.sh

EXPOSE 3000
CMD ["/start.sh"]
