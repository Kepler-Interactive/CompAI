# =============================================================================
# STAGE 3: Production Runtime (simpler approach without standalone)
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
