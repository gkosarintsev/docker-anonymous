#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# Ensure environment profile exists
if [ ! -f .env ]; then
  echo "[!] .env not found — generating default profile..."
  bash scripts/generate-env.sh .env
fi

# Ensure WARP proxy is running and healthy
WARP_HEALTH=$(docker inspect warp-proxy-service --format '{{.State.Health.Status}}' 2>/dev/null || echo "absent")

if [ "$WARP_HEALTH" != "healthy" ]; then
  echo "[*] WARP proxy is '$WARP_HEALTH' — starting..."
  docker compose up warp-proxy -d
  bash scripts/wait-for-warp.sh 120
fi

# Run application without wiping any state
docker compose run --rm node-app "$@"
