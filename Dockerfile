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
    NODE_ENV=production

# Build the app WITHOUT standalone (regular build)
RUN cd apps/app && SKIP_ENV_VALIDATION=true bun run build

# =============================================================================
# STAGE 3: Production Runtime
# =============================================================================
FROM node:20-slim AS production

WORKDIR /app

# Install bun and required packages
RUN apt-get update && apt-get install -y curl unzip openssl && \
    curl -fsSL https://bun.sh/install | bash && \
    ln -s /root/.bun/bin/bun /usr/local/bin/bun && \
    rm -rf /var/lib/apt/lists/*

# Copy everything from builder
COPY --from=app-builder /app/package.json ./
COPY --from=app-builder /app/bun.lock ./
COPY --from=app-builder /app/apps/app ./apps/app
COPY --from=app-builder /app/node_modules ./node_modules
COPY --from=app-builder /app/packages ./packages

# Set working directory to the app
WORKDIR /app/apps/app

# Set environment variables
ENV NODE_ENV=production
ENV PORT=3000

# Expose port
EXPOSE 3000

# Use bun to start the Next.js app directly
CMD ["bun", "run", "start"]
