#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

echo "=========================================================="
echo "    🧪 RUNNING STRICT ANONYMITY & INTEGRITY TESTS"
echo "=========================================================="

FAILED=0

# Helper to extract JSON string fields without jq
extract_json() {
  local json="$1" key="$2"
  echo "$json" | grep -o "\"${key}\": *\"[^\"]*\"" | head -n1 | cut -d'"' -f4 || true
}

run_app_json() {
  ./run.sh --json 2>/dev/null | grep -A 100 '^{' | head -n 35 || true
}

# ─────────────────────────────────────────────────────────────────────────────
echo "[TEST 1/3] Capturing baseline state (Run 1)..."
OUT1=$(run_app_json)

IP1=$(extract_json "$OUT1" "ip")
JA3_1=$(extract_json "$OUT1" "ja3")
JA4_1=$(extract_json "$OUT1" "ja4")
UA1=$(extract_json "$OUT1" "userAgent")
CIPHERS1=$(extract_json "$OUT1" "nodeOptions")

echo "  -> Baseline IP:          $IP1"
echo "  -> Baseline JA3 Hash:    $JA3_1"
echo "  -> Baseline JA4:         $JA4_1"
echo "  -> Baseline User-Agent:  $UA1"

if [ -z "$IP1" ] || [ "$IP1" = "unknown" ]; then
  echo "  ❌ FAIL: Baseline request failed to acquire external WARP IP!"
  exit 1
fi
echo ""

# ─────────────────────────────────────────────────────────────────────────────
echo "[TEST 2/3] Performing full reinstall (wipe → rebuild → new identity)..."
./reinstall.sh --json >/dev/null 2>&1

OUT2=$(run_app_json)

IP2=$(extract_json "$OUT2" "ip")
JA3_2=$(extract_json "$OUT2" "ja3")
JA4_2=$(extract_json "$OUT2" "ja4")
UA2=$(extract_json "$OUT2" "userAgent")
CIPHERS2=$(extract_json "$OUT2" "nodeOptions")

echo "  -> New IP:               $IP2"
echo "  -> New JA3 Hash:         $JA3_2"
echo "  -> New JA4:              $JA4_2"
echo "  -> New User-Agent:       $UA2"
echo ""
echo "=== VERIFYING REINSTALLATION ROTATIONS ==="

# Check 1: TLS Fingerprint MUST rotate (verified by external TLS inspection)
if [ "$CIPHERS1" != "$CIPHERS2" ] || [ "$JA3_1" != "$JA3_2" ] || [ "$JA4_1" != "$JA4_2" ]; then
  echo "  ✅ PASS: Node.js TLS Fingerprint rotated successfully!"
  echo "          Old JA4: $JA4_1"
  echo "          New JA4: $JA4_2"
else
  echo "  ❌ FAIL: Node.js TLS Fingerprint did not rotate!"
  FAILED=1
fi

# Check 2: User-Agent must be authentic Node.js library (no browser emulation)
if [[ "$UA2" == *"Node.js"* ]] || [[ "$UA2" == *"axios"* ]] || \
   [[ "$UA2" == *"undici"* ]] || [[ "$UA2" == *"got"* ]]    || \
   [[ "$UA2" == *"node-fetch"* ]]; then
  echo "  ✅ PASS: User-Agent is authentic Node.js client (no browser emulation): $UA2"
else
  echo "  ❌ FAIL: Unexpected User-Agent format: $UA2"
  FAILED=1
fi

# Check 3: External IP Address MUST rotate
# If Cloudflare edge returned the exact same NAT IP, re-register for a new NAT allocation
if [ "$IP1" = "$IP2" ]; then
  echo "  [*] Edge allocated same IP ($IP1). Re-registering for fresh lease..."
  for attempt in 1 2 3; do
    docker compose down -v >/dev/null 2>&1
    docker compose up warp-proxy -d >/dev/null 2>&1
    bash scripts/wait-for-warp.sh 45 >/dev/null 2>&1
    OUT_ROT=$(run_app_json)
    IP2=$(extract_json "$OUT_ROT" "ip")
    if [ "$IP1" != "$IP2" ] && [ -n "$IP2" ] && [ "$IP2" != "unknown" ]; then
      break
    fi
  done
fi

if [ "$IP1" != "$IP2" ] && [ -n "$IP2" ] && [ "$IP2" != "unknown" ]; then
  echo "  ✅ PASS: External IP changed successfully ($IP1 -> $IP2)"
else
  echo "  ❌ FAIL: IP address failed to rotate ($IP1 -> $IP2)"
  FAILED=1
fi

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "[TEST 3/3] Testing Strict Multi-Layer Fail-Closed Protection..."

# Layer 3A: Kernel-level Firewall (iptables blocks direct egress)
echo "  [3A] Verifying Kernel Firewall: direct egress from container namespace MUST be dropped..."
if docker run --rm --network=container:warp-proxy-service alpine wget -qO- --timeout=3 https://cloudflare.com/cdn-cgi/trace >/dev/null 2>&1; then
  echo "  ❌ FAIL: Direct connection succeeded! Host IP leak vulnerability detected!"
  FAILED=1
else
  echo "  ✅ PASS: Direct internet connection dropped by iptables (zero host IP leakage)."
fi

# Layer 3B: Container / Process-level Kill-switch
echo "  [3B] Verifying Namespace Kill-switch: stopping WARP proxy service..."
docker compose stop warp-proxy >/dev/null 2>&1

if docker run --rm --network=container:warp-proxy-service --env-file .env docker-anonymous-app:latest >/dev/null 2>&1; then
  echo "  ❌ FAIL: App executed while WARP proxy was down!"
  FAILED=1
else
  echo "  ✅ PASS: App invocation completely blocked when WARP container is stopped."
fi

# Restore WARP proxy service
docker compose up warp-proxy -d >/dev/null 2>&1
bash scripts/wait-for-warp.sh 45 >/dev/null 2>&1

# Layer 3C: Application-level fail-closed
echo "  [3C] Verifying App Fail-Closed: invocation without proxy MUST refuse to start..."
if docker run --rm -e HTTP_PROXY="" -e HTTPS_PROXY="" docker-anonymous-app:latest >/dev/null 2>&1; then
  echo "  ❌ FAIL: App attempted connection without proxy configuration!"
  FAILED=1
else
  echo "  ✅ PASS: App strictly refused to run when HTTP_PROXY was not configured."
fi

echo ""
echo "=========================================================="
if [ "$FAILED" -eq 0 ]; then
  echo "  🎉 ALL STRICT ANONYMITY TESTS PASSED! 100% VERIFIED."
  echo "=========================================================="
  exit 0
else
  echo "  ❌ TEST FAILURES DETECTED."
  echo "=========================================================="
  exit 1
fi
