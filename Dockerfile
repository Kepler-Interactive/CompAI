# =============================================================================
# STAGE 1: Dependencies - Install and cache workspace dependencies
# =============================================================================
FROM oven/bun:1.2.8 AS deps

WORKDIR /app

# Copy workspace configuration
COPY package.json bun.lock ./

# Copy package.json files for all packages (including local db)
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

# Install bun in Node image for compatibility
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

# Set build-time environment variables for Next.js
ARG NEXT_PUBLIC_BETTER_AUTH_URL
ARG NEXT_PUBLIC_APP_URL
ARG NEXT_PUBLIC_PORTAL_URL
ENV NEXT_PUBLIC_BETTER_AUTH_URL=$NEXT_PUBLIC_BETTER_AUTH_URL \
    NEXT_PUBLIC_APP_URL=$NEXT_PUBLIC_APP_URL \
    NEXT_PUBLIC_PORTAL_URL=$NEXT_PUBLIC_PORTAL_URL \
    NEXT_TELEMETRY_DISABLED=1 \
    NODE_ENV=production \
    NEXT_OUTPUT_STANDALONE=true \
    NODE_OPTIONS=--max_old_space_size=4096

# Build the app with standalone output
RUN cd apps/app && SKIP_ENV_VALIDATION=true bun run build

# =============================================================================
# STAGE 3: Production Runtime (using standalone for smaller image)
# =============================================================================
FROM node:22-alpine AS production

WORKDIR /app

# Install curl for health checks and potential seed operations
RUN apk add --no-cache curl

# Copy the standalone Next.js build
COPY --from=app-builder /app/apps/app/.next/standalone ./
COPY --from=app-builder /app/apps/app/.next/static ./apps/app/.next/static
COPY --from=app-builder /app/apps/app/public ./apps/app/public

# Copy Prisma schema for potential runtime migrations
COPY --from=app-builder /app/packages/db/prisma ./packages/db/prisma

# Create a startup script that handles migrations and seeding
RUN echo '#!/bin/sh' > /startup.sh && \
    echo 'echo "Starting CompAI Application..."' >> /startup.sh && \
    echo '' >> /startup.sh && \
    echo '# Optional: Run database migrations (uncomment if needed)' >> /startup.sh && \
    echo '# cd /app/packages/db && npx prisma migrate deploy || echo "Migration skipped"' >> /startup.sh && \
    echo '' >> /startup.sh && \
    echo '# Optional: Seed frameworks after app starts (runs in background)' >> /startup.sh && \
    echo '(sleep 30 && curl -s http://localhost:3000/api/frameworks/seed || echo "Seed check complete") &' >> /startup.sh && \
    echo '' >> /startup.sh && \
    echo 'echo "Starting Next.js server..."' >> /startup.sh && \
    echo 'exec node apps/app/server.js' >> /startup.sh && \
    chmod +x /startup.sh

# Expose port
EXPOSE 3000

# Use the startup script
CMD ["/startup.sh"]

# =============================================================================
# STAGE 4: Migrator (optional - can be used as separate service)
# =============================================================================
FROM node:20-slim AS migrator

WORKDIR /app

# Install Prisma CLI
RUN npm install -g prisma@6.14.0 @prisma/client@6.14.0

# Copy Prisma schema and migrations
COPY packages/db/prisma ./packages/db/prisma

# Run migrations
CMD ["prisma", "migrate", "deploy", "--schema=packages/db/prisma/schema.prisma"]
