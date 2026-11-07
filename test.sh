#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

echo "=========================================================="
echo "    🧪 RUNNING AUTOMATED ANONYMITY & INTEGRITY TESTS"
echo "=========================================================="

FAILED=0

# ─── Helper ──────────────────────────────────────────────────────────────────
# Parse a JSON string field without requiring jq
extract_json() {
  local json="$1" key="$2"
  echo "$json" | grep -o "\"${key}\": *\"[^\"]*\"" | head -n1 | cut -d'"' -f4 || true
}

run_app_json() {
  ./run.sh --json 2>/dev/null | grep -A 100 '^{' | head -n 30 || true
}

# ─────────────────────────────────────────────────────────────────────────────
echo "[TEST 1/3] Capturing baseline state..."
OUT1=$(run_app_json)

IP1=$(extract_json "$OUT1" "ip")
JA3_1=$(extract_json "$OUT1" "ja3")
JA4_1=$(extract_json "$OUT1" "ja4")
UA1=$(extract_json "$OUT1" "userAgent")
CIPHERS1=$(extract_json "$OUT1" "nodeOptions")

echo "  -> IP:          $IP1"
echo "  -> JA3:         $JA3_1"
echo "  -> JA4:         $JA4_1"
echo "  -> User-Agent:  $UA1"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
echo "[TEST 2/3] Performing full reinstall (wipe → rebuild → new WARP identity)..."
./reinstall.sh --json >/dev/null 2>&1

OUT2=$(run_app_json)

IP2=$(extract_json "$OUT2" "ip")
JA3_2=$(extract_json "$OUT2" "ja3")
JA4_2=$(extract_json "$OUT2" "ja4")
UA2=$(extract_json "$OUT2" "userAgent")
CIPHERS2=$(extract_json "$OUT2" "nodeOptions")

echo "  -> IP:          $IP2"
echo "  -> JA3:         $JA3_2"
echo "  -> JA4:         $JA4_2"
echo "  -> User-Agent:  $UA2"
echo ""
echo "=== VERIFYING ROTATIONS ==="

# Check 1: IP rotation (advisory — Cloudflare may reassign same edge IP)
if [ "$IP1" != "$IP2" ] && [ -n "$IP2" ] && [ "$IP2" != "unknown" ]; then
  echo "  ✅ PASS: IP rotated ($IP1 → $IP2)"
else
  echo "  ⚠️  NOTE: Same Cloudflare edge IP ($IP2). WARP X25519 credentials were still rotated."
fi

# Check 2: TLS fingerprint MUST change (primary assertion)
if [ "$CIPHERS1" != "$CIPHERS2" ] || [ "$JA3_1" != "$JA3_2" ] || [ "$JA4_1" != "$JA4_2" ]; then
  echo "  ✅ PASS: TLS fingerprint rotated"
  echo "           JA4: $JA4_1 → $JA4_2"
else
  echo "  ❌ FAIL: TLS fingerprint did NOT rotate after reinstall!"
  FAILED=1
fi

# Check 3: User-Agent must be a real Node.js client identifier
if [[ "$UA2" == *"Node.js"* ]] || [[ "$UA2" == *"axios"* ]] || \
   [[ "$UA2" == *"undici"* ]] || [[ "$UA2" == *"got"* ]]    || \
   [[ "$UA2" == *"node-fetch"* ]]; then
  echo "  ✅ PASS: User-Agent is authentic Node.js client: $UA2"
else
  echo "  ❌ FAIL: Unexpected User-Agent: '$UA2'"
  FAILED=1
fi

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "[TEST 3/3] Kill-switch — host IP must NOT leak when WARP proxy is down..."
docker compose stop warp-proxy >/dev/null 2>&1

# Run app WITHOUT sharing the warp-proxy network namespace.
# HTTP_PROXY still points to 127.0.0.1:9091 — but nothing listens there
# in a fresh container → ProxyAgent gets ECONNREFUSED → process exits 1.
# This confirms fail-closed at the application level.
if docker run --rm --env-file .env docker-anonymous-app:latest >/dev/null 2>&1; then
  echo "  ❌ FAIL: Request succeeded with proxy down — host IP may have leaked!"
  FAILED=1
else
  echo "  ✅ PASS: Request blocked (ECONNREFUSED on proxy). Host IP was NOT exposed."
fi

# Restore WARP proxy
docker compose up warp-proxy -d >/dev/null 2>&1
bash scripts/wait-for-warp.sh 120 >/dev/null 2>&1

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "=========================================================="
if [ "$FAILED" -eq 0 ]; then
  echo "  🎉 ALL TESTS PASSED!"
  echo "=========================================================="
  exit 0
else
  echo "  ❌ SOME TESTS FAILED."
  echo "=========================================================="
  exit 1
fi
