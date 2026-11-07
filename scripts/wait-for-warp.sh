#!/usr/bin/env bash
# wait-for-warp.sh — shared helper: waits until warp-proxy-service is healthy.
# Usage: bash scripts/wait-for-warp.sh [timeout_seconds]
# Exit code 1 on timeout.

TIMEOUT="${1:-120}"
DEADLINE=$(($(date +%s) + TIMEOUT))

until docker inspect warp-proxy-service --format '{{.State.Health.Status}}' 2>/dev/null | grep -q "^healthy$"; do
  if [ "$(date +%s)" -gt "$DEADLINE" ]; then
    echo "[!] WARP proxy did not become healthy within ${TIMEOUT}s."
    echo "    Logs:"
    docker logs warp-proxy-service --tail 30 2>/dev/null || true
    exit 1
  fi
  STATUS=$(docker inspect warp-proxy-service --format '{{.State.Health.Status}}' 2>/dev/null || echo "absent")
  echo "    ... waiting for WARP (current: $STATUS)"
  sleep 4
done
echo "[✓] WARP proxy is healthy."

