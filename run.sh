#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# Ensure environment profile exists
if [ ! -f .env ]; then
  echo "[!] .env not found. Generating default profile..."
  bash scripts/generate-env.sh .env
fi

# Ensure WARP proxy is running and healthy
if ! docker compose ps warp-proxy 2>/dev/null | grep -q "Up"; then
  echo "[*] Starting Cloudflare WARP proxy..."
  docker compose up warp-proxy -d --wait >/dev/null 2>&1
fi

# Run application without wiping data
docker compose run --rm node-app "$@"

