#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

echo "=========================================================="
echo "    🔄 REINSTALLING DOCKER-ANONYMOUS (CLEAN WIPE & REBUILD)"
echo "=========================================================="

# 1. Stop containers, delete volumes and previous data
echo "[1/5] Removing existing containers, volumes, and state..."
docker compose down -v --remove-orphans >/dev/null 2>&1 || true

# Remove local persistent files and .env
rm -f .env

# 2. Generate new randomized Node.js fingerprint profile
echo "[2/5] Generating fresh Node.js anti-fingerprint profile (ciphers + identity)..."
bash scripts/generate-env.sh .env

# 3. Force re-compilation and rebuild of application containers without cache
echo "[3/5] Recompiling Node.js application and rebuilding Docker images (--no-cache)..."
docker compose build --no-cache

# 4. Start Cloudflare WARP with a brand new registration (generates new exit IP)
echo "[4/5] Initializing fresh Cloudflare WARP identity (Rotating IP address)..."
docker compose up warp-proxy -d --wait

echo "=========================================================="
echo "    ✨ REINSTALLATION COMPLETE — RUNNING VERIFICATION"
echo "=========================================================="

# 5. Execute application
docker compose run --rm node-app "$@"

