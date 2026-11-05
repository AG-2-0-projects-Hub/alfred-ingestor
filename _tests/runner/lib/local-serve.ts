// Serves the local release build (frontend/build/web) on http://localhost:3000 with /api/*
// proxied to the deployed STAGING backend, so a Playwright scenario can test frontend
// changes BEFORE they are pushed: `STAGING_FRONTEND_URL=http://localhost:3000 npx tsx scenarios/p12.ts`.
// Same-origin on purpose: the backend's CORS allow-list has no localhost. The app reads its
// BACKEND_URL from /assets/.env, which is rewritten on the fly to this server's own origin.
//   build: cd frontend && flutter build web --pwa-strategy=none --release
//   serve: cd _tests/runner && npx tsx lib/local-serve.ts
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';
import { env } from './env.ts';

const ROOT = fileURLToPath(new URL('../../../frontend/build/web', import.meta.url));
const PORT = Number(process.env.PORT ?? 3000);
const BACKEND = env.stagingBackend.replace(/\/$/, '');
const TYPES: Record<string, string> = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.json': 'application/json',
  '.css': 'text/css', '.svg': 'image/svg+xml', '.png': 'image/png', '.wasm': 'application/wasm',
  '.ttf': 'font/ttf', '.otf': 'font/otf', '.woff2': 'font/woff2',
};

createServer(async (req, res) => {
  try {
    const url = new URL(req.url ?? '/', `http://localhost:${PORT}`);
    if (url.pathname.startsWith('/api/')) {
      const chunks: Buffer[] = [];
      for await (const c of req) chunks.push(c as Buffer);
      const headers = new Headers();
      for (const [k, v] of Object.entries(req.headers)) {
        if (v && !['host', 'connection', 'content-length', 'origin', 'referer'].includes(k)) headers.set(k, String(v));
      }
      const hasBody = !['GET', 'HEAD'].includes(req.method ?? 'GET');
      const up = await fetch(BACKEND + url.pathname + url.search, {
        method: req.method, headers, body: hasBody ? Buffer.concat(chunks) : undefined,
      });
      res.writeHead(up.status, { 'content-type': up.headers.get('content-type') ?? 'application/json' });
      res.end(Buffer.from(await up.arrayBuffer()));
      return;
    }
    if (url.pathname === '/assets/.env') {
      const text = (await readFile(join(ROOT, 'assets/.env'), 'utf8')).replace(/^BACKEND_URL=.*$/m, `BACKEND_URL=http://localhost:${PORT}`);
      res.writeHead(200, { 'content-type': 'text/plain' });
      res.end(text);
      return;
    }
    const rel = normalize(decodeURIComponent(url.pathname)).replace(/^([/\\])+/, '');
    let file = join(ROOT, rel || 'index.html');
    if (!file.startsWith(ROOT)) { res.writeHead(403); res.end(); return; }
    const body = await readFile(file).catch(() => readFile((file = join(ROOT, 'index.html'))));
    res.writeHead(200, { 'content-type': TYPES[extname(file)] ?? 'application/octet-stream' });
    res.end(body);
  } catch (e) {
    res.writeHead(500); res.end(String(e));
  }
}).listen(PORT, () => console.log(`local-serve on http://localhost:${PORT} -> ${BACKEND}`));
