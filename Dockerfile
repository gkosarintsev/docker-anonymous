# Stage 1: Build & Compile TypeScript
FROM node:22-alpine AS builder

WORKDIR /build

COPY package*.json tsconfig.json ./
RUN npm install

COPY src/ ./src/
RUN npm run build

# Stage 2: Minimal hardened runner
FROM node:22-alpine AS runner

WORKDIR /app
ENV NODE_ENV=production

COPY package*.json ./
RUN npm install --omit=dev

COPY --from=builder /build/dist ./dist

ENTRYPOINT ["node", "dist/index.js"]
