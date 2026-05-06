# ── Stage 1: Build ─────────────────────────────────────────────
FROM node:20-alpine AS builder

# OCI standard build-time labels (injected by Jenkins pipeline)
ARG BUILD_DATE=unknown
ARG VCS_REF=unknown
ARG VERSION=dev

WORKDIR /app

# Install dependencies (cached layer)
COPY package*.json ./
RUN npm ci --prefer-offline

# Copy source and build production bundle
COPY . .
RUN npm run build

# ── Stage 2: Production (nginx) ─────────────────────────────────
FROM nginx:stable-alpine AS production

# Carry build-args into the final image as OCI labels
ARG BUILD_DATE=unknown
ARG VCS_REF=unknown
ARG VERSION=dev

LABEL org.opencontainers.image.title="Finance Tracker" \
      org.opencontainers.image.description="Personal Finance Tracker — React + Vite" \
      org.opencontainers.image.url="https://github.com/Unlicensed-Mystic/docker1" \
      org.opencontainers.image.source="https://github.com/Unlicensed-Mystic/docker1" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.version="${VERSION}"

# Remove default nginx static assets
RUN rm -rf /usr/share/nginx/html/*

# Copy compiled React app from builder stage
COPY --from=builder /app/dist /usr/share/nginx/html

# Use custom nginx config (SPA routing support)
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

# Health-check so Docker & orchestrators can detect container readiness
HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
    CMD wget -qO- http://localhost/ || exit 1

CMD ["nginx", "-g", "daemon off;"]
