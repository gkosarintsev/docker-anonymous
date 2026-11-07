#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

echo "=========================================================="
echo "    🚀 INSTALLING DOCKER-ANONYMOUS (INITIAL SETUP)"
echo "=========================================================="

# 1. Generate environment profile if not present
if [ ! -f .env ]; then
  echo "[*] Generating initial Node.js stealth fingerprint profile..."
  bash scripts/generate-env.sh .env
else
  echo "[*] Using existing .env profile..."
fi

# 2. Build Docker containers (compiles TypeScript)
echo "[*] Compiling Node.js application and building Docker images..."
docker compose build

# 3. Start Cloudflare WARP proxy service and await healthcheck
echo "[*] Starting Cloudflare WARP proxy service..."
docker compose up warp-proxy -d --wait

echo "=========================================================="
echo "    ✨ INSTALLATION COMPLETE — EXECUTING RUNTIME"
echo "=========================================================="

# 4. Run application
docker compose run --rm node-app "$@"

