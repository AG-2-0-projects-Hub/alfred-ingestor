import { env } from './env.ts';

// Wakes staging services from Render free-tier sleep before scenarios run.
// First request to a sleeping service returns 502; we fire-and-forget those
// errors and wait ~60s for the service to become responsive.

const urls = [
  env.stagingBackend,
  env.stagingScraper,
];

export async function warmup(): Promise<void> {
  console.log('Warmup: pinging staging services...');

  const start = Date.now();
  await Promise.all(urls.map(url => pingUntilLive(url)));
  console.log(`Warmup: all services responsive (${Date.now() - start}ms)\n`);
}

async function pingUntilLive(url: string, maxMs = 90_000): Promise<void> {
  const deadline = Date.now() + maxMs;
  let attempt = 0;

  while (Date.now() < deadline) {
    attempt++;
    try {
      const res = await fetch(url, { method: 'GET', signal: AbortSignal.timeout(15_000) });
      if (res.status < 500) {
        // Any 2xx, 3xx, or 4xx response means the service is processing requests.
        // Even a 404 at root is fine — it proves the app is running.
        console.log(`  [${url}] live (status ${res.status}, attempt ${attempt})`);
        return;
      }
      console.log(`  [${url}] still warming (status ${res.status}, attempt ${attempt})`);
    } catch (err) {
      console.log(`  [${url}] still warming (${(err as Error).message}, attempt ${attempt})`);
    }
    await sleep(5_000);
  }
  throw new Error(`Service at ${url} never became responsive within ${maxMs}ms`);
}

function sleep(ms: number): Promise<void> {
  return new Promise(r => setTimeout(r, ms));
}
