FROM ghcr.io/mon-ius/docker-warp-socks:v8

COPY entrypoint.sh /entrypoint.sh
RUN sed -i 's/\r$//' /entrypoint.sh && chmod +x /entrypoint.sh

HEALTHCHECK --interval=4s --timeout=4s --start-period=3s --retries=10 \
    CMD curl -4 -s -f -x http://127.0.0.1:9091 --max-time 3 https://cloudflare.com/cdn-cgi/trace >/dev/null 2>&1 || exit 1

ENTRYPOINT ["/entrypoint.sh"]

