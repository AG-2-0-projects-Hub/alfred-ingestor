// Excursion detector on deterministic samples: set the pinned timeline to u = 0, 0.02, 0.04 ... (no scroll noise), wait for the clip to seek,
// grab a small composited screenshot each time, then flag any sample that differs a lot from the samples K steps before AND after while those two
// match each other (a still / ghost layer showing through for a moment). usage: node exc.js PAGE.html [WxH] [step=0.02]
const { chromium } = require(process.env.HOME + '/AG_master_files/projects/the-ingestor/_tests/runner/node_modules/playwright');
const http = require('http'), fs = require('fs'), path = require('path');
const ROOT = process.env.LANDING_ROOT || (process.env.HOME + '/AG_master_files/projects/the-ingestor/landing/_preview');
const OUT = (process.env.OUT_DIR || '/tmp/landing-tools') + '/exc/';
fs.mkdirSync(OUT, { recursive: true });
const TYPES = { '.html': 'text/html; charset=utf-8', '.webp': 'image/webp', '.svg': 'image/svg+xml', '.mp4': 'video/mp4', '.webm': 'video/webm', '.jpg': 'image/jpeg', '.png': 'image/png' };
const server = http.createServer((req, res) => {
  const f = path.join(ROOT, decodeURIComponent(req.url.split('?')[0]));
  if (!f.startsWith(ROOT) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) { res.writeHead(404); return res.end(); }
  const size = fs.statSync(f).size, type = TYPES[path.extname(f)] || 'application/octet-stream', r = req.headers.range;
  if (r) { const m = /bytes=(\d*)-(\d*)/.exec(r), s = m[1] ? +m[1] : 0, e = m[2] ? +m[2] : size - 1; res.writeHead(206, { 'Content-Type': type, 'Content-Range': `bytes ${s}-${e}/${size}`, 'Accept-Ranges': 'bytes', 'Content-Length': e - s + 1 }); fs.createReadStream(f, { start: s, end: e }).pipe(res); }
  else { res.writeHead(200, { 'Content-Type': type, 'Content-Length': size, 'Accept-Ranges': 'bytes' }); fs.createReadStream(f).pipe(res); }
});
const PAGE = process.argv[2] || 'preview-v4.html';
const [W, H] = (process.argv[3] || '1440x900').split('x').map(Number);
const STEP = +process.argv[4] || 0.02;
const TAG = PAGE.replace('.html', '') + '_' + W + 'x' + H;
(async () => {
  await new Promise(r => server.listen(8769, '127.0.0.1', r));
  const browser = await chromium.launch({ args: ['--autoplay-policy=no-user-gesture-required'] });
  const ctx = await browser.newContext({ viewport: { width: W, height: H } });
  const page = await ctx.newPage();
  const errs = []; page.on('pageerror', e => errs.push(String(e)));
  await page.goto('http://127.0.0.1:8769/' + PAGE, { waitUntil: 'load' });
  await page.waitForTimeout(3000);
  const END = await page.evaluate(async () => {
    const tl = ScrollTrigger.getAll().find(s => s.pin).animation, E = tl.duration(), vids = [...document.querySelectorAll('#vclip video')];
    for (let u = 0; u <= E; u += 0.8) { tl.time(u, false); await new Promise(r => setTimeout(r, 220)); }
    for (let k = 0; k < 80 && !vids.every(v => v.readyState >= 2); k++) await new Promise(r => setTimeout(r, 250));
    tl.time(0, false); await new Promise(r => setTimeout(r, 400));
    return E;
  });
  const cdp = await ctx.newCDPSession(page);
  const shots = [], us = [], fl = [];
  for (let u = 0; u <= END + 1e-6; u += STEP) {
    const fa = await page.evaluate(u => { ScrollTrigger.getAll().find(s => s.pin).animation.time(u, false); return +document.querySelector('#light').style.opacity || 0; }, u);
    fl.push(fa);
    await page.waitForTimeout(150);
    const r = await cdp.send('Page.captureScreenshot', { format: 'jpeg', quality: 45, clip: { x: 0, y: 0, width: W, height: H, scale: 0.25 } });
    shots.push(r.data); us.push(+u.toFixed(3));
  }
  const feats = await page.evaluate(async (b64s) => {
    const out = [], c = document.createElement('canvas'); c.width = 32; c.height = 20; const x = c.getContext('2d', { willReadFrequently: true });
    for (const s of b64s) { const bm = await createImageBitmap(await (await fetch('data:image/jpeg;base64,' + s)).blob()); x.drawImage(bm, 0, 0, 32, 20); bm.close(); out.push(Array.from(x.getImageData(0, 0, 32, 20).data).filter((_, i) => i % 4 !== 3)); }
    return out;
  }, shots);
  const d = (a, b) => { let s = 0; for (let i = 0; i < a.length; i++) s += Math.abs(a[i] - b[i]); return s / a.length; };
  const flagged = new Map();
  for (const K of [2, 3, 5]) {
    for (let i = K; i < feats.length - K; i++) {
      const dl = d(feats[i], feats[i - K]), dr = d(feats[i], feats[i + K]), dlr = d(feats[i - K], feats[i + K]);
      if (Math.min(dl, dr) >= 7 && dlr <= 0.5 * Math.min(dl, dr)) { const prev = flagged.get(i); const sc = Math.min(dl, dr) - dlr; if (!prev || sc > prev.score) flagged.set(i, { i, u: us[i], K, dl: +dl.toFixed(1), dr: +dr.toFixed(1), dlr: +dlr.toFixed(1), score: +sc.toFixed(1) }); }
    }
  }
  // merge neighbours into events
  const arr = [...flagged.values()].sort((a, b) => a.i - b.i), events = [];
  arr.forEach(e => { const l = events[events.length - 1]; if (l && e.i - l.last <= 3) { l.last = e.i; l.to = e.u; if (e.score > l.score) { l.score = e.score; l.peak = e.u; l.pi = e.i; } } else events.push({ from: e.u, to: e.u, last: e.i, score: e.score, peak: e.u, pi: e.i }); });
  console.log(`${TAG}: ${us.length} samples, END=${END.toFixed(2)}, step ${STEP}`);
  events.forEach(e => {
    let m = 0; for (let j = Math.max(0, e.pi - 4); j <= Math.min(fl.length - 1, e.pi + 4); j++) m = Math.max(m, fl[j]);
    const f = feats[e.pi], bright = f.reduce((a, b) => a + b, 0) / f.length;
    e.flare = m; e.bright = bright;
    /* intended: the cream flare, or a clip's own cream flood (a mostly cream frame is a bright excursion by design) */
    e.real = m < 0.25 && bright < 190;
  });
  const real = events.filter(e => e.real);
  console.log(`EXCURSION EVENTS: ${real.length} REAL, ${events.length - real.length} on the cream flare / cream flood (intended)`);
  events.forEach((e, n) => { console.log(`   ${e.real ? 'REAL   ' : 'cream  '} u ${e.from}-${e.to} (peak ${e.peak}, score ${e.score}, flare ${e.flare.toFixed(2)}, brightness ${e.bright.toFixed(0)})`); if (n < 8) for (const o of [-3, 0, 3]) { const j = Math.min(Math.max(e.pi + o, 0), shots.length - 1); fs.writeFileSync(OUT + `${TAG}_ev${n + 1}_${o < 0 ? 'a' : o === 0 ? 'b' : 'c'}.jpg`, Buffer.from(shots[j], 'base64')); } });
  console.log('page errors:', errs.length ? errs.join(' | ') : 'none');
  await browser.close(); server.close();
})();
