#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# Ensure environment profile exists
if [ ! -f .env ]; then
  echo "[!] .env not found. Generating default profile..."
  bash scripts/generate-env.sh .env
fi

# Ensure WARP proxy is running and healthy
WARP_HEALTH=$(docker inspect warp-proxy-service --format '{{.State.Health.Status}}' 2>/dev/null || echo "absent")

if [ "$WARP_HEALTH" != "healthy" ]; then
  echo "[*] WARP proxy is '$WARP_HEALTH' — starting..."
  docker compose up warp-proxy -d

  echo "[*] Waiting for WARP to become healthy..."
  DEADLINE=$(($(date +%s) + 120))
  until docker inspect warp-proxy-service --format '{{.State.Health.Status}}' 2>/dev/null | grep -q "^healthy$"; do
    if [ "$(date +%s)" -gt "$DEADLINE" ]; then
      echo "[!] WARP proxy failed to start within 120s. Check: docker logs warp-proxy-service"
      exit 1
    fi
    sleep 3
  done
  echo "[*] WARP proxy is healthy."
fi

# Run application without wiping data
docker compose run --rm node-app "$@"
