# =============================================================================
# STAGE 1: Dependencies - Install and cache workspace dependencies
# =============================================================================
FROM oven/bun:1.2.8 AS deps

ENV REBUILD_DATE="2025-08-15-v2"

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
# STAGE 2: Ultra-Minimal Migrator - Only Prisma
# =============================================================================
FROM oven/bun:1.2.8 AS migrator

WORKDIR /app

# Copy Prisma schema and migration files
COPY packages/db/prisma ./packages/db/prisma

# Create minimal package.json for Prisma
RUN echo '{"name":"migrator","type":"module","dependencies":{"prisma":"^6.13.0","@prisma/client":"^6.13.0"}}' > package.json

# Install ONLY Prisma dependencies
RUN bun install

# Generate Prisma client
RUN cd packages/db && bunx prisma generate

# Default command for migrations
CMD ["bunx", "prisma", "migrate", "deploy", "--schema=packages/db/prisma/schema.prisma"]

# =============================================================================
# STAGE 3: Portal Builder
# =============================================================================
FROM deps AS portal-builder

WORKDIR /app

# Copy all source code needed for build
COPY packages ./packages
COPY apps/portal ./apps/portal

# Generate Prisma client
RUN cd packages/db && bunx prisma generate

# Build the portal
RUN cd apps/portal && SKIP_ENV_VALIDATION=true bun run build

# =============================================================================
# STAGE 4: Portal Production
# =============================================================================
FROM oven/bun:1.2.8 AS portal

WORKDIR /app

# Copy package files first
COPY --from=portal-builder /app/package.json ./
COPY --from=portal-builder /app/bun.lock ./

# Copy the entire portal app directory (includes all files)
COPY --from=portal-builder /app/apps/portal ./apps/portal

# Copy dependencies and packages
COPY --from=portal-builder /app/node_modules ./node_modules
COPY --from=portal-builder /app/packages ./packages

# Ensure the working directory exists
WORKDIR /app/apps/portal

EXPOSE 3000
CMD ["bun", "run", "start"]

# =============================================================================
# STAGE 5: App Builder
# =============================================================================
FROM deps AS app-builder

WORKDIR /app

# Copy all source code needed for build
COPY packages ./packages
COPY apps/app ./apps/app

# Generate Prisma client in the full workspace context
RUN cd packages/db && bunx prisma generate

# Build the app
RUN cd apps/app && SKIP_ENV_VALIDATION=true bun run build

# =============================================================================
# STAGE 6: App Production (DEFAULT - This is now last!)
# =============================================================================
FROM oven/bun:1.2.8 AS app

WORKDIR /app

# Copy package files first
COPY --from=app-builder /app/package.json ./
COPY --from=app-builder /app/bun.lock ./

# Copy the entire app directory (includes all files)
COPY --from=app-builder /app/apps/app ./apps/app

# Copy dependencies and packages
COPY --from=app-builder /app/node_modules ./node_modules
COPY --from=app-builder /app/packages ./packages

# Simple start script using bunx for migrations
RUN echo '#!/bin/sh' > /start.sh && \
    echo 'echo "Running database setup..."' >> /start.sh && \
    echo 'cd /app/packages/db && bunx prisma db push --accept-data-loss' >> /start.sh && \
    echo 'echo "Starting application..."' >> /start.sh && \
    echo 'cd /app/apps/app && exec bun run start' >> /start.sh && \
    chmod +x /start.sh

EXPOSE 3000
CMD ["/start.sh"]
