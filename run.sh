#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# Ensure environment profile exists
if [ ! -f .env ]; then
  echo "[!] .env not found. Generating default profile..."
  bash scripts/generate-env.sh .env
fi

# Ensure WARP proxy is running and healthy
_warp_ensure_healthy() {
  local WARP_HEALTH
  WARP_HEALTH=$(docker inspect warp-proxy-service --format '{{.State.Health.Status}}' 2>/dev/null || echo "absent")

  if [ "$WARP_HEALTH" = "healthy" ]; then
    return 0
  fi

  echo "[*] WARP proxy is '$WARP_HEALTH' — starting..."
  docker compose up warp-proxy -d

  echo "[*] Waiting for WARP to become healthy (attempt 1/2)..."
  if bash scripts/wait-for-warp.sh 90; then
    return 0
  fi

  # First attempt timed out — WireGuard identity may have expired.
  # Force re-registration without wiping the volume.
  echo "[!] WARP timed out. Re-registering identity (FORCE_NEW_IDENTITY=1)..."
  docker compose stop warp-proxy
  docker compose rm -f warp-proxy
  FORCE_NEW_IDENTITY=1 docker compose up warp-proxy -d

  echo "[*] Waiting for WARP to become healthy (attempt 2/2)..."
  bash scripts/wait-for-warp.sh 120
}

_warp_ensure_healthy

# Run application without wiping data
docker compose run --rm node-app "$@"
