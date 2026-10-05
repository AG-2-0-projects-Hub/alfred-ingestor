// Screenshot a preview at exact timeline positions (no scrolling noise): node at.js PAGE.html u1,u2,u3 [WxH]
const { chromium } = require(process.env.HOME + '/AG_master_files/projects/the-ingestor/_tests/runner/node_modules/playwright');
const http = require('http'), fs = require('fs'), path = require('path');
const ROOT = process.env.LANDING_ROOT || (process.env.HOME + '/AG_master_files/projects/the-ingestor/landing/_preview');
const OUT = (process.env.OUT_DIR || '/tmp/landing-tools') + '/at/';
fs.mkdirSync(OUT, { recursive: true });
const TYPES = { '.html': 'text/html; charset=utf-8', '.webp': 'image/webp', '.svg': 'image/svg+xml', '.mp4': 'video/mp4', '.webm': 'video/webm', '.jpg': 'image/jpeg', '.png': 'image/png' };
const server = http.createServer((req, res) => {
  const f = path.join(ROOT, decodeURIComponent(req.url.split('?')[0]));
  if (!f.startsWith(ROOT) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) { res.writeHead(404); return res.end(); }
  const size = fs.statSync(f).size, type = TYPES[path.extname(f)] || 'application/octet-stream', r = req.headers.range;
  if (r) { const m = /bytes=(\d*)-(\d*)/.exec(r), s = m[1] ? +m[1] : 0, e = m[2] ? +m[2] : size - 1; res.writeHead(206, { 'Content-Type': type, 'Content-Range': `bytes ${s}-${e}/${size}`, 'Accept-Ranges': 'bytes', 'Content-Length': e - s + 1 }); fs.createReadStream(f, { start: s, end: e }).pipe(res); }
  else { res.writeHead(200, { 'Content-Type': type, 'Content-Length': size, 'Accept-Ranges': 'bytes' }); fs.createReadStream(f).pipe(res); }
});
const PAGE = process.argv[2], US = process.argv[3].split(',').map(Number);
const [W, H] = (process.argv[4] || '1440x900').split('x').map(Number);
(async () => {
  await new Promise(r => server.listen(8768, '127.0.0.1', r));
  const browser = await chromium.launch({ args: ['--autoplay-policy=no-user-gesture-required'] });
  const page = await (await browser.newContext({ viewport: { width: W, height: H } })).newPage();
  await page.goto('http://127.0.0.1:8768/' + PAGE, { waitUntil: 'load' });
  await page.waitForTimeout(3000);
  await page.evaluate(async () => {
    const st = ScrollTrigger.getAll().find(s => s.pin), tl = st.animation, END = tl.duration(), vids = [...document.querySelectorAll('#vclip video')];
    for (let u = 0; u <= END; u += 0.8) { tl.time(u, false); await new Promise(r => setTimeout(r, 220)); }
    for (let k = 0; k < 80 && !vids.every(v => v.readyState >= 2); k++) await new Promise(r => setTimeout(r, 250));
  });
  for (const u of US) {
    await page.evaluate(async u => { const tl = ScrollTrigger.getAll().find(s => s.pin).animation; tl.time(u, false); await new Promise(r => setTimeout(r, 900)); }, u);
    await page.screenshot({ path: OUT + PAGE.replace('.html', '') + '_u' + u.toFixed(2) + '.png' });
  }
  await browser.close(); server.close();
})();
