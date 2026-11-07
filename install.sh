#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

echo "=========================================================="
echo "    🚀 INSTALLING DOCKER-ANONYMOUS (INITIAL SETUP)"
echo "=========================================================="

# 1. Generate environment profile if not present
if [ ! -f .env ]; then
  echo "[1/4] Generating Node.js stealth fingerprint profile..."
  bash scripts/generate-env.sh .env
else
  echo "[1/4] Using existing .env profile."
fi

# 2. Build Docker images (compiles TypeScript in multi-stage build)
echo "[2/4] Compiling TypeScript and building Docker images..."
docker compose build

# 3. Start Cloudflare WARP proxy and wait until healthy
echo "[3/4] Starting Cloudflare WARP proxy..."
docker compose up warp-proxy -d
bash scripts/wait-for-warp.sh 120

echo "=========================================================="
echo "    ✨ INSTALLATION COMPLETE — EXECUTING RUNTIME"
echo "=========================================================="

# 4. Run application
docker compose run --rm node-app "$@"
