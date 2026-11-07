#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

echo "=========================================================="
echo "    🔄 REINSTALLING DOCKER-ANONYMOUS (CLEAN WIPE & REBUILD)"
echo "=========================================================="

# 1. Stop everything and wipe persistent volumes
echo "[1/5] Removing containers, volumes, and state..."
docker compose down -v --remove-orphans 2>/dev/null || true
rm -f .env

# 2. Generate a fresh randomised fingerprint profile
echo "[2/5] Generating new anti-fingerprint profile (ciphers + UA + machine ID)..."
bash scripts/generate-env.sh .env

# 3. Rebuild from scratch — forces fresh TypeScript compilation
echo "[3/5] Rebuilding Docker images (--no-cache)..."
docker compose build --no-cache

# 4. Register a brand-new Cloudflare WARP identity → new exit IP
echo "[4/5] Starting WARP with fresh X25519 identity..."
docker compose up warp-proxy -d
bash scripts/wait-for-warp.sh 120

echo "=========================================================="
echo "    ✨ REINSTALL COMPLETE — EXECUTING RUNTIME"
echo "=========================================================="

# 5. Run application
docker compose run --rm node-app "$@"
