import { ProxyAgent, setGlobalDispatcher } from 'undici';

// 1. Strict Fail-Closed: refuse to run if proxy is not configured
const proxyUrl = process.env.HTTP_PROXY || process.env.HTTPS_PROXY;
if (!proxyUrl) {
  console.error('[FAIL-CLOSED] HTTP_PROXY is not set. Direct host connection is blocked.');
  process.exit(1);
}

// 2. Route ALL outbound requests through Cloudflare WARP proxy
setGlobalDispatcher(
  new ProxyAgent({
    uri: proxyUrl,
    connect: { timeout: 10_000 },
  })
);

const userAgent = process.env.USER_AGENT ?? `Node.js/${process.version} (linux-x64)`;

// ─── Types ───────────────────────────────────────────────────────────────────

interface TraceData {
  ip?: string;
  warp?: string;
  colo?: string;
  loc?: string;
  [key: string]: string | undefined;
}

interface FingerprintData {
  tls?: {
    ja3_hash?: string;
    ja4?: string;
  };
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

/** Parse Cloudflare's key=value trace format */
async function fetchTrace(): Promise<TraceData> {
  const res = await fetch('https://cloudflare.com/cdn-cgi/trace', {
    headers: { 'User-Agent': userAgent },
  });
  if (!res.ok) throw new Error(`Cloudflare trace: HTTP ${res.status}`);
  const data: TraceData = {};
  for (const line of (await res.text()).split('\n')) {
    const eq = line.indexOf('=');
    if (eq > 0) data[line.slice(0, eq).trim()] = line.slice(eq + 1).trim();
  }
  return data;
}

/** Fetch remote TLS fingerprint (JA3/JA4). Non-fatal on failure. */
async function fetchFingerprint(): Promise<FingerprintData | null> {
  try {
    const res = await fetch('https://tls.peet.ws/api/all', {
      headers: { 'User-Agent': userAgent },
    });
    return res.ok ? ((await res.json()) as FingerprintData) : null;
  } catch {
    return null;
  }
}

// ─── Main ────────────────────────────────────────────────────────────────────

async function main(): Promise<void> {
  const isJson = process.argv.includes('--json');

  // Run both requests concurrently
  const [trace, fp] = await Promise.all([fetchTrace(), fetchFingerprint()]);

  const ip         = trace.ip  ?? 'unknown';
  const warpActive = trace.warp === 'on';
  const ja3        = fp?.tls?.ja3_hash ?? 'unknown';
  const ja4        = fp?.tls?.ja4      ?? 'unknown';

  if (isJson) {
    process.stdout.write(
      JSON.stringify(
        {
          timestamp:   new Date().toISOString(),
          ip,
          warp:        warpActive,
          colo:        trace.colo ?? 'unknown',
          loc:         trace.loc  ?? 'unknown',
          ja3,
          ja4,
          userAgent,
          nodeOptions: process.env.NODE_OPTIONS ?? '',
          proxy:       proxyUrl,
        },
        null,
        2
      ) + '\n'
    );
    return;
  }

  console.log('====================================================');
  console.log('    🛡️  MINIMAL NODE.JS CLIENT (WARP PROTECTED)  🛡️');
  console.log('====================================================');
  console.log(`[+] Proxy Gateway:   ${proxyUrl}`);
  console.log(`[+] Public IP:       ${ip}`);
  console.log(`[+] Cloudflare WARP: ${warpActive ? 'ACTIVE ✓' : 'INACTIVE ✗'} (loc=${trace.loc ?? '?'} colo=${trace.colo ?? '?'})`);
  console.log(`[+] Node User-Agent: ${userAgent}`);
  console.log(`[+] Remote JA3 Hash: ${ja3}`);
  console.log(`[+] Remote JA4:      ${ja4}`);
  console.log('====================================================');
  console.log('✨ [SUCCESS] Request completed via Cloudflare WARP.');
}

main().catch((err: unknown) => {
  const msg = err instanceof Error ? err.message : String(err);
  console.error('[FAIL-CLOSED] Request failed:', msg);
  process.exit(1);
});
