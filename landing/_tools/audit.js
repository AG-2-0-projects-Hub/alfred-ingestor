// Deterministic layer audit: step the pinned timeline in tiny increments (no scrolling, no seeking noise) and, from the page's real DOM state,
// find where a clip layer is partly transparent over the WRONG still, or where only a still shows for a short stretch (a flash).
// usage: node audit.js PAGE.html [WxH]
const { chromium } = require(process.env.HOME + '/AG_master_files/projects/the-ingestor/_tests/runner/node_modules/playwright');
const http = require('http'), fs = require('fs'), path = require('path');
const ROOT = process.env.LANDING_ROOT || (process.env.HOME + '/AG_master_files/projects/the-ingestor/landing/_preview');
const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.css': 'text/css', '.webp': 'image/webp', '.svg': 'image/svg+xml', '.mp4': 'video/mp4', '.webm': 'video/webm', '.jpg': 'image/jpeg', '.png': 'image/png' };
const server = http.createServer((req, res) => {
  const f = path.join(ROOT, decodeURIComponent(req.url.split('?')[0]));
  if (!f.startsWith(ROOT) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) { res.writeHead(404); return res.end(); }
  const size = fs.statSync(f).size, type = TYPES[path.extname(f)] || 'application/octet-stream', r = req.headers.range;
  if (r) { const m = /bytes=(\d*)-(\d*)/.exec(r), s = m[1] ? +m[1] : 0, e = m[2] ? +m[2] : size - 1; res.writeHead(206, { 'Content-Type': type, 'Content-Range': `bytes ${s}-${e}/${size}`, 'Accept-Ranges': 'bytes', 'Content-Length': e - s + 1 }); fs.createReadStream(f, { start: s, end: e }).pipe(res); }
  else { res.writeHead(200, { 'Content-Type': type, 'Content-Length': size, 'Accept-Ranges': 'bytes' }); fs.createReadStream(f).pipe(res); }
});
const PAGE = process.argv[2] || 'preview-v4.html';
const [W, H] = (process.argv[3] || '1440x900').split('x').map(Number);
(async () => {
  await new Promise(r => server.listen(8767, '127.0.0.1', r));
  const browser = await chromium.launch({ args: ['--autoplay-policy=no-user-gesture-required'] });
  const page = await (await browser.newContext({ viewport: { width: W, height: H } })).newPage();
  const errs = []; page.on('pageerror', e => errs.push(String(e)));
  await page.goto('http://127.0.0.1:8767/' + PAGE, { waitUntil: 'load' });
  await page.waitForTimeout(3000);
  const info = await page.evaluate(async () => {
    const st = ScrollTrigger.getAll().find(s => s.pin); const tl = st.animation, END = tl.duration();
    const vids = [...document.querySelectorAll('#vclip video')];
    // coarse pass so every clip loads
    for (let u = 0; u <= END; u += 0.8) { tl.time(u, false); await new Promise(r => setTimeout(r, 220)); }
    for (let k = 0; k < 80 && !vids.every(v => v.readyState >= 2); k++) await new Promise(r => setTimeout(r, 250));
    tl.time(0, false); await new Promise(r => setTimeout(r, 300));
    const layers = [...document.querySelectorAll('#vclip canvas')].length ? [...document.querySelectorAll('#vclip canvas')] : vids;
    const shots = ['#s0', '#s1', '#s2', '#s3', '#s4', '#s5'].map(s => document.querySelector(s)), light = document.querySelector('#light');
    const rows = [];
    for (let u = 0; u <= END + 1e-6; u += 0.01) {
      tl.time(u, false);
      const op = layers.map(l => +l.style.opacity || 0), vis = shots.map(s => s.style.visibility === 'visible');
      let top = -1; vis.forEach((v, i) => { if (v) top = i; });
      rows.push([+u.toFixed(2), op, top, +light.style.opacity || 0]);
    }
    return { END, rows, ready: vids.map(v => v.readyState) };
  });
  const rows = info.rows, an = [];
  // 1) clip partly transparent over the wrong still (flare not covering)
  for (let r = 1; r < rows.length; r++) {
    const [u, op, top, fl] = rows[r], prev = rows[r - 1][1];
    op.forEach((o, i) => {
      if (o > 0.02 && o < 0.98 && fl < 0.5) {
        const rising = o > prev[i] + 1e-4, falling = o < prev[i] - 1e-4;
        const expect = rising ? i : i + 1;
        if ((rising || falling) && top !== expect) an.push({ u, kind: 'wrong-still-under-fade', clip: 'c' + (i + 1), dir: rising ? 'in' : 'out', opacity: +o.toFixed(2), still_under: top, expected: expect });
      }
    });
  }
  // 2) only a still shows (no clip opaque, no flare): list the stretches
  const stretches = []; let cur = null;
  for (const [u, op, top, fl] of rows) {
    const max = Math.max(...op), only = max < 0.5 && fl < 0.5;
    if (only) { if (!cur) cur = { from: u, to: u, shot: top }; else { cur.to = u; if (top !== cur.shot) cur.shot = cur.shot + '/' + top; } }
    else if (cur) { stretches.push(cur); cur = null; }
  }
  if (cur) stretches.push(cur);
  // collapse wrong-still anomalies into ranges
  const ranges = []; an.forEach(a => { const l = ranges[ranges.length - 1]; if (l && l.clip === a.clip && l.dir === a.dir && a.u - l.to < 0.031) { l.to = a.u; l.n++; } else ranges.push({ clip: a.clip, dir: a.dir, from: a.u, to: a.u, n: 1, still_under: a.still_under, expected: a.expected }); });
  console.log(`${PAGE} @${W}x${H}  END=${info.END.toFixed(2)} screens, ready=${info.ready}`);
  console.log(`A) clip fading over the WRONG still: ${ranges.length} range(s)`);
  ranges.forEach(r => console.log(`   ${r.clip} fading ${r.dir} u ${r.from}-${r.to} (${r.n} samples) shows shot ${r.still_under}, should be ${r.expected}`));
  console.log(`B) stretches with only a still showing (no clip, no flare): ${stretches.length}`);
  stretches.forEach(s => console.log(`   u ${s.from}-${s.to} (${(s.to - s.from).toFixed(2)} screens) still of shot ${s.shot}`));
  console.log('page errors:', errs.length ? errs.join(' | ') : 'none');
  await browser.close(); server.close();
})();
