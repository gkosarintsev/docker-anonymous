# Stage 1: Build & Compile TypeScript
FROM node:22-alpine AS builder

WORKDIR /build

COPY package*.json tsconfig.json ./
RUN npm ci

COPY src/ ./src/
RUN npm run build

# Stage 2: Minimal hardened runner (non-root)
FROM node:22-alpine AS runner

WORKDIR /app
ENV NODE_ENV=production

COPY package*.json ./
RUN npm ci --omit=dev && \
    addgroup -S appgroup && \
    adduser  -S appuser -G appgroup

COPY --from=builder /build/dist ./dist

USER appuser
ENTRYPOINT ["node", "dist/index.js"]
