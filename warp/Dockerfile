FROM ghcr.io/mon-ius/docker-warp-socks:v8

COPY entrypoint.sh /entrypoint.sh
RUN sed -i 's/\r$//' /entrypoint.sh && chmod +x /entrypoint.sh

HEALTHCHECK --interval=8s --timeout=6s --start-period=20s --retries=20 \
    CMD curl -4 -s -f -x http://127.0.0.1:9091 --max-time 5 https://cloudflare.com/cdn-cgi/trace >/dev/null 2>&1 || exit 1

ENTRYPOINT ["/entrypoint.sh"]

