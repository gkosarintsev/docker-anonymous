import { ProxyAgent, setGlobalDispatcher } from 'undici';

// 1. Strict Fail-Closed Check: refuse to start or execute if proxy is not configured
const proxyUrl = process.env.HTTP_PROXY || process.env.HTTPS_PROXY;
if (!proxyUrl) {
  console.error('[FAIL-CLOSED] Error: HTTP_PROXY is required. Direct host connection is blocked.');
  process.exit(1);
}

// 2. Route all outbound requests through Cloudflare WARP proxy
const proxyAgent = new ProxyAgent({
  uri: proxyUrl,
  connect: { timeout: 10000 },
});
setGlobalDispatcher(proxyAgent);

const userAgent = process.env.USER_AGENT || `Node.js/${process.version} (linux-x64)`;

interface TraceData {
  ip?: string;
  warp?: string;
  colo?: string;
  loc?: string;
  [key: string]: string | undefined;
}

interface FingerprintData {
  ip?: string;
  tls?: {
    ja3?: string;
    ja3_hash?: string;
    ja4?: string;
    ciphers?: string[];
  };
  http_version?: string;
}

async function fetchTrace(): Promise<TraceData> {
  const res = await fetch('https://cloudflare.com/cdn-cgi/trace', {
    headers: { 'User-Agent': userAgent },
  });
  if (!res.ok) {
    throw new Error(`Failed to fetch Cloudflare trace: HTTP ${res.status}`);
  }
  const text = await res.text();
  const data: TraceData = {};
  for (const line of text.split('\n')) {
    const [k, v] = line.split('=');
    if (k && v) data[k.trim()] = v.trim();
  }
  return data;
}

async function fetchFingerprint(): Promise<FingerprintData | null> {
  try {
    const res = await fetch('https://tls.peet.ws/api/all', {
      headers: { 'User-Agent': userAgent },
    });
    if (!res.ok) return null;
    return (await res.json()) as FingerprintData;
  } catch {
    return null;
  }
}

async function main() {
  const isJson = process.argv.includes('--json');

  const trace = await fetchTrace();
  const fp = await fetchFingerprint();

  const ip = trace.ip || 'unknown';
  const warpActive = trace.warp === 'on';
  const ja3 = fp?.tls?.ja3_hash || 'unknown';
  const ja4 = fp?.tls?.ja4 || 'unknown';

  if (isJson) {
    console.log(
      JSON.stringify(
        {
          timestamp: new Date().toISOString(),
          ip,
          warp: warpActive,
          colo: trace.colo || 'unknown',
          loc: trace.loc || 'unknown',
          ja3,
          ja4,
          userAgent,
          nodeOptions: process.env.NODE_OPTIONS || '',
          proxy: proxyUrl,
        },
        null,
        2
      )
    );
    return;
  }

  console.log('====================================================');
  console.log('    🛡️  MINIMAL NODE.JS CLIENT (WARP PROTECTED)  🛡️');
  console.log('====================================================');
  console.log(`[+] Proxy Gateway:   ${proxyUrl}`);
  console.log(`[+] Public IP:       ${ip}`);
  console.log(`[+] Cloudflare WARP: ${warpActive ? 'ACTIVE (Protected)' : 'INACTIVE'} (Location: ${trace.loc || 'N/A'}, Colo: ${trace.colo || 'N/A'})`);
  console.log(`[+] Node User-Agent: ${userAgent}`);
  console.log(`[+] Remote JA3 Hash: ${ja3}`);
  console.log(`[+] Remote JA4:      ${ja4}`);
  console.log('====================================================');
  console.log('✨ [SUCCESS] Internet request completed via Cloudflare WARP.');
}

main().catch((err: any) => {
  console.error('[FAIL-CLOSED TRIGGERED] Request failed:', err.message || err);
  process.exit(1);
});
