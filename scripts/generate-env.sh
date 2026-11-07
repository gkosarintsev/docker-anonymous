#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${1:-.env}"

# 1. Pool of strong Node.js OpenSSL cipher suites
CIPHERS=(
  "ECDHE-ECDSA-AES128-GCM-SHA256"
  "ECDHE-RSA-AES128-GCM-SHA256"
  "ECDHE-ECDSA-AES256-GCM-SHA384"
  "ECDHE-RSA-AES256-GCM-SHA384"
  "ECDHE-ECDSA-CHACHA20-POLY1305"
  "ECDHE-RSA-CHACHA20-POLY1305"
  "DHE-RSA-AES128-GCM-SHA256"
  "DHE-RSA-AES256-GCM-SHA384"
  "ECDHE-ECDSA-AES128-SHA256"
  "ECDHE-RSA-AES128-SHA256"
)

# Shuffle ciphers using shuf
SHUFFLED_CIPHERS=($(printf "%s\n" "${CIPHERS[@]}" | shuf))

# Select a subset of 6 to 9 ciphers
COUNT=$((6 + RANDOM % 4))
SELECTED_CIPHERS="${SHUFFLED_CIPHERS[0]}"
for ((i=1; i<COUNT; i++)); do
  SELECTED_CIPHERS="${SELECTED_CIPHERS}:${SHUFFLED_CIPHERS[i]}"
done

# 2. Pool of realistic Node.js User-Agents (Node runtimes & libraries, NO browser emulation)
USER_AGENTS=(
  "axios/1.7.9 (Node.js/v20.18.0; linux-x64)"
  "axios/1.7.7 (Node.js/v20.17.0; linux-x64)"
  "node-fetch/3.3.2 (+https://github.com/node-fetch/node-fetch; Node.js/v20.18.0)"
  "node-fetch/2.6.12 (Node.js/v20.18.0; linux-x64)"
  "undici/6.21.1 (Node.js/v20.18.0; linux-x64)"
  "undici/5.28.4 (Node.js/v20.16.0; linux-x64)"
  "got/14.4.2 (https://github.com/sindresorhus/got; Node.js/v20.18.0)"
  "Node.js/v20.18.0 (linux; x64)"
  "Node.js/v20.17.0 (linux; x64)"
)

SELECTED_UA="${USER_AGENTS[$((RANDOM % ${#USER_AGENTS[@]}))]}"

# 3. Machine ID
MACHINE_ID=$(openssl rand -hex 16)

# 4. Cloudflare WARP Gateway Endpoint (Randomly selected from verified Anycast gateways)
WARP_SERVERS=("162.159.192.1" "188.114.96.1" "188.114.97.1")
WARP_SERVER="${WARP_SERVER:-${WARP_SERVERS[$((RANDOM % ${#WARP_SERVERS[@]}))]}}"
WARP_PORT="2408"

# 5. Write .env
cat <<EOF > "$ENV_FILE"
# Auto-generated Node.js Stealth Environment Profile
HTTP_PROXY=http://127.0.0.1:9091
HTTPS_PROXY=http://127.0.0.1:9091
ALL_PROXY=http://127.0.0.1:9091

# Node.js TLS Anti-Fingerprint (Permuted OpenSSL cipher suite order)
NODE_OPTIONS=--tls-cipher-list=${SELECTED_CIPHERS}

# Node.js Client Identity (No browser emulation)
USER_AGENT=${SELECTED_UA}

# System Identifier
MACHINE_ID=${MACHINE_ID}

# Cloudflare WARP Gateway Endpoint
WARP_SERVER=${WARP_SERVER}
WARP_PORT=${WARP_PORT}
EOF

echo "[env] Generated fresh environment profile in $ENV_FILE"
echo "      Cipher list: ${SELECTED_CIPHERS}"
echo "      User-Agent:  ${SELECTED_UA}"
echo "      WARP Server: ${WARP_SERVER}:${WARP_PORT}"
