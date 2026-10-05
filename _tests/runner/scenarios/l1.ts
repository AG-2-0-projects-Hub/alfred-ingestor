import { chromium, type Page } from 'playwright';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { dirname, extname, join, normalize, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { supabaseAnon } from '../lib/supabase.ts';
import type { ScenarioResult } from '../run.ts';

// L1 — landing-waitlist-01
// Layer 2: the Mayordommo landing's waitlist form with double opt-in (landing/site/index.html) against the STAGING
// backend (backend/routers/waitlist.py). The landing is served from disk by a throwaway local server; the page talks
// to whatever backend address it carries (the API constant in index.html). To test a local backend instead, set
// L1_BACKEND=http://localhost:8099: page requests to the page's own backend address are then rerouted there.
//
// UI side: invalid email (nothing sent), valid QA address + homes chip (one call, "Revisa tu correo"), same address
// again after confirming (success, no new link), re-signup after unsubscribing (new link), honeypot (success screen,
// nothing sent), double submit (exactly one call), network failure (inline error, address kept, retry possible),
// instant submit under 2.5 s (success screen, nothing sent), nav shows the log-in pill pointing at the app, page is noindex.
// Link side (QA addresses end in @example.invalid, so the backend hands back the confirm/unsubscribe links instead of
// emailing): GET confirm twice changes nothing, POST confirms, POST again is refused, same for unsubscribe, garbage
// tokens are refused. Public key limits: cannot read, insert, or call the old join_waitlist function.
// What this CANNOT prove: that SendGrid really delivers (QA addresses skip sending; a real mailbox is checked by hand),
// and the rows themselves (no service-role key here): after a run the expected rows are checked with a real SQL query
// through the Supabase MCP: exactly two rows, emailA (homes 2-5, pending) and emailC (pending); none for B, D, E.
// Test rows are wl-qa-<timestamp>-*@example.invalid so a scoped cleanup can find them.

const __dirname = dirname(fileURLToPath(import.meta.url));
const SITE = resolve(__dirname, '../../../landing/site');
const TYPES: Record<string, string> = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.css': 'text/css', '.webp': 'image/webp',
  '.svg': 'image/svg+xml', '.mp4': 'video/mp4', '.webm': 'video/webm', '.jpg': 'image/jpeg', '.png': 'image/png',
};

function serveSite(): Promise<{ url: string; close: () => void }> {
  return new Promise((ok) => {
    const srv = createServer(async (req, res) => {
      const rel = normalize(decodeURIComponent((req.url ?? '/').split('?')[0])).replace(/^(\.\.[/\\])+/, '');
      try {
        const file = rel === '/' ? 'index.html' : rel;
        const body = await readFile(join(SITE, file));
        res.writeHead(200, { 'Content-Type': TYPES[extname(file)] ?? 'application/octet-stream' });
        res.end(body);
      } catch {
        res.writeHead(404);
        res.end();
      }
    }).listen(0, '127.0.0.1', () => {
      const port = (srv.address() as { port: number }).port;
      ok({ url: `http://127.0.0.1:${port}/`, close: () => srv.close() });
    });
  });
}

export async function runL1(): Promise<ScenarioResult> {
  const start = Date.now();
  const id = 'landing-waitlist-01';
  const name = 'L1: landing waitlist (double opt-in) stores one signup per email and never fakes success on failure';
  console.log(`[${id}] starting...`);

  const html = await readFile(join(SITE, 'index.html'), 'utf8');
  const pageApi = /var API='([^']+)'/.exec(html)?.[1] ?? '';
  const appUrl = /APP_URL='([^']+)'/.exec(html)?.[1] ?? '';
  const backend = (process.env.L1_BACKEND ?? pageApi).replace(/\/$/, '');
  const stamp = Date.now();
  const mail = (k: string) => `wl-qa-${stamp}-${k}@example.invalid`;
  const [emailA, emailB, emailC, emailD, emailE] = ['a', 'b', 'c', 'd', 'e'].map(mail);
  const problems: string[] = [];
  const notes: string[] = [];
  const check = (cond: boolean, msg: string) => { if (!cond) problems.push(msg); };
  const abs = (u: string) => (u.startsWith('/') ? backend + u : u);
  const txt = (h: string) => h.replace(/<[^>]*>/g, ' ').replace(/\s+/g, ' ');

  const server = await serveSite();
  const browser = await chromium.launch();
  try {
    const page: Page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
    if (pageApi && backend !== pageApi.replace(/\/$/, '')) {
      await page.route(`${pageApi.replace(/\/$/, '')}/**`, async (route) => {
        const u = new URL(route.request().url());
        await route.fulfill({ response: await route.fetch({ url: backend + u.pathname + u.search }) });
      });
    }
    type Post = { status: number; body: Record<string, unknown> };
    const posts: Promise<Post>[] = [];
    page.on('response', (r) => {
      if (r.request().method() === 'POST' && /\/api\/waitlist$/.test(new URL(r.url()).pathname)) {
        posts.push(r.json().then((body) => ({ status: r.status(), body })).catch(() => ({ status: r.status(), body: {} })));
      }
    });
    const sent = () => posts.length;
    const lastPost = async () => posts[posts.length - 1];
    const openForm = async () => {
      await page.goto(server.url, { waitUntil: 'load' });
      await page.locator('#email').scrollIntoViewIfNeeded();
      await page.waitForTimeout(600);
    };
    const again = async () => { await page.locator('#wl-again').click(); await page.waitForTimeout(100); };
    const okVisible = (ms = 25000) => page.locator('#wl-ok').waitFor({ state: 'visible', timeout: ms }).then(() => true).catch(() => false);
    const submit = async (e: string) => { await page.fill('#email', e); await page.click('#wl-btn'); };

    // A) open and wait out the 2.5 s bot window once; the page shape: log-in pill + noindex
    await openForm();
    await page.waitForTimeout(2800);
    check(await page.locator('#login').isVisible(), 'A: the log-in pill is not visible at 1440 wide');
    check((await page.locator('#login').getAttribute('href')) === appUrl && appUrl.startsWith('https://'), `A: log-in pill points at ${await page.locator('#login').getAttribute('href')}, expected ${appUrl}`);
    check(/noindex/.test((await page.locator('meta[name=robots]').getAttribute('content')) ?? ''), 'A: page is not noindex');
    check(/X-Robots-Tag/.test(await readFile(join(SITE, 'vercel.json'), 'utf8')), 'A: vercel.json does not send X-Robots-Tag');

    // B) invalid email: inline error, nothing sent
    await submit('nope');
    await page.waitForTimeout(400);
    check(await page.locator('#email-err').isVisible(), 'B: invalid email did not show the inline error');
    check(sent() === 0, `B: invalid email sent a request (${sent()})`);

    // C) QA address + homes chip: one call, "Revisa tu correo", links handed back
    await page.fill('#email', emailA);
    await page.locator('label.pick', { hasText: '2 a 5' }).click();
    await page.click('#wl-btn');
    check(await okVisible(), 'C: no success screen for a valid email');
    const c = await lastPost();
    check(sent() === 1 && c?.status === 200 && c.body.status === 'ok', `C: expected one 200 ok call, got ${sent()} / ${JSON.stringify(c)}`);
    check(((await page.locator('#wl-ok h3').textContent()) ?? '').includes('Revisa tu correo'), 'C: success title is not "Revisa tu correo"');
    check(((await page.locator('#wl-ok-msg').textContent()) ?? '').includes(emailA), 'C: success text does not show the address');
    const confirmUrl = abs(String(c?.body.confirm_url ?? ''));
    const unsubUrl = abs(String(c?.body.unsubscribe_url ?? ''));
    check(/\/api\/waitlist\/confirm\?token=/.test(confirmUrl) && /\/api\/waitlist\/unsubscribe\?token=/.test(unsubUrl), 'C: the backend did not hand back the confirm/unsubscribe links for a QA address');

    // D) the confirm link: GET twice changes nothing, POST confirms, POST again is refused
    const g1 = await fetch(confirmUrl); const g1t = await g1.text();
    const g2 = await fetch(confirmUrl);
    check(g1.status === 200 && g2.status === 200 && g1t.includes('guarda mi lugar'), 'D: GET confirm is not a read-only page with a button (twice)');
    check(g1.headers.get('content-type')?.includes('text/html') === true, 'D: confirm page is not HTML');
    const p1 = await fetch(confirmUrl, { method: 'POST' }); const p1t = txt(await p1.text());
    check(p1.status === 200 && p1t.includes('tu lugar está guardado') && p1t.includes(emailA), `D: POST confirm did not confirm (${p1.status})`);
    const p2 = await fetch(confirmUrl, { method: 'POST' });
    check(p2.status === 400, `D: second POST confirm should be refused, got ${p2.status}`);
    const g3 = await fetch(confirmUrl);
    check(g3.status === 400, `D: GET confirm after use should say invalid, got ${g3.status}`);

    // E) confirmed address asks again (capitals, spaces): same success screen, NO new link
    await again();
    await page.fill('#email', `  ${emailA.toUpperCase()} `);
    await page.click('#wl-btn');
    check(await okVisible(), 'E: no success screen for an already-confirmed address');
    const e = await lastPost();
    check(sent() === 2 && e?.status === 200 && e.body.status === 'ok' && !('confirm_url' in (e?.body ?? {})), `E: a confirmed address must get the same ok and no new link, got ${JSON.stringify(e)}`);

    // F) unsubscribe: GET shows a button and changes nothing, POST unsubscribes (idempotent); asking again is a fresh request with a new link
    const u1 = await fetch(unsubUrl); const u1t = await u1.text();
    check(u1.status === 200 && u1t.includes('quítame de la lista'), 'F: GET unsubscribe is not a button page');
    const u2 = await fetch(unsubUrl, { method: 'POST' }); const u2t = txt(await u2.text());
    check(u2.status === 200 && u2t.includes('no te escribiremos más'), `F: POST unsubscribe failed (${u2.status})`);
    const u3 = await fetch(unsubUrl, { method: 'POST' });
    check(u3.status === 200, `F: unsubscribing twice should stay fine, got ${u3.status}`);
    await again();
    await page.fill('#email', emailA);
    await page.click('#wl-btn');
    check(await okVisible(), 'F: no success screen for a re-signup after unsubscribing');
    const f = await lastPost();
    const confirmUrl2 = abs(String(f?.body.confirm_url ?? ''));
    check(sent() === 3 && f?.status === 200 && confirmUrl2 !== '' && confirmUrl2 !== confirmUrl, `F: re-signup after unsubscribing must mint a NEW link, got ${JSON.stringify(f)}`);

    // G) honeypot filled: normal success screen, nothing sent
    await again();
    const beforeG = sent();
    await page.fill('#email', emailB);
    await page.evaluate(() => { (document.querySelector('#company') as HTMLInputElement).value = 'Acme'; });
    await page.click('#wl-btn');
    check(await okVisible(), 'G: honeypot case did not show the normal success screen');
    check(sent() === beforeG, `G: honeypot case sent a request (${sent() - beforeG})`);

    // H) double submit (click then Enter while the first call is slow): exactly one call
    await again();
    const beforeH = sent();
    await page.route('**/api/waitlist', async (route) => { await new Promise((r) => setTimeout(r, 1200)); await route.fallback(); });
    await page.fill('#email', emailC);
    await page.click('#wl-btn');
    await page.press('#email', 'Enter');
    check(await okVisible(), 'H: double submit never reached the success screen');
    check(sent() - beforeH === 1, `H: double submit sent ${sent() - beforeH} calls, expected 1`);
    await page.unroute('**/api/waitlist');

    // I) network failure: inline error, address kept, button usable, never a false success
    await again();
    await page.route('**/api/waitlist', (route) => route.abort());
    await page.fill('#email', emailD);
    await page.click('#wl-btn');
    await page.locator('#wl-err').waitFor({ state: 'visible', timeout: 25000 }).catch(() => undefined);
    check(await page.locator('#wl-err').isVisible(), 'I: network failure did not show the inline error');
    check(!(await page.locator('#wl-ok').isVisible()), 'I: network failure showed a false success screen');
    check((await page.inputValue('#email')) === emailD, 'I: the address was not kept after a failure');
    check(await page.locator('#wl-btn').isEnabled(), 'I: the button stayed disabled after a failure');
    await page.unroute('**/api/waitlist');

    // J) instant submit (inside 2.5 s of loading): success screen, nothing sent
    await page.goto(server.url, { waitUntil: 'load' });
    const beforeJ = sent();
    await page.evaluate((x) => {
      (document.querySelector('#email') as HTMLInputElement).value = x;
      (document.querySelector('#wl') as HTMLFormElement).requestSubmit();
    }, emailE);
    // (after a reload the card is still hidden by its scroll reveal, so ask for the state, not for visibility)
    const shownJ = await page.waitForFunction(() => !(document.querySelector('#wl-ok') as HTMLElement).hidden, null, { timeout: 15000 }).then(() => true).catch(() => false);
    check(shownJ, 'J: instant submit did not show the normal success screen');
    check(sent() === beforeJ, `J: instant submit sent a request (${sent() - beforeJ})`);

    // K) backend directly: validation and bad links; the answer carries the open CORS header
    const post = (b: unknown) => fetch(`${backend}/api/waitlist`, { method: 'POST', headers: { 'Content-Type': 'text/plain;charset=UTF-8' }, body: JSON.stringify(b) });
    const k1 = await post({ email: 'not-an-email' });
    check(k1.status === 400 && (await k1.json()).detail === 'invalid_email', `K: a bad email was not refused (${k1.status})`);
    const k2 = await post({ email: mail('homes'), homes: '9' });
    check(k2.status === 400 && (await k2.json()).detail === 'invalid_homes', `K: a bad homes value was not refused (${k2.status})`);
    check(k1.headers.get('access-control-allow-origin') === '*', 'K: the backend answer lacks Access-Control-Allow-Origin: *');
    for (const path of ['confirm', 'unsubscribe']) {
      const gar = `${backend}/api/waitlist/${path}?token=garbage-${stamp}`;
      check((await fetch(gar)).status === 400 && (await fetch(gar, { method: 'POST' })).status === 400, `K: a garbage ${path} token was not refused`);
    }

    // L) public key limits (no browser): cannot read, insert, or call the old direct function
    const read = await supabaseAnon.from('waitlist_signups').select('email').limit(5);
    check(!!read.error || (read.data ?? []).length === 0, `L: public key could read signups (${read.data?.length} rows)`);
    const direct = await supabaseAnon.from('waitlist_signups').insert({ email: `wl-qa-${stamp}-direct@example.invalid` });
    check(!!direct.error, 'L: public key could insert straight into the table');
    const old = await supabaseAnon.rpc('join_waitlist', { p_email: `wl-qa-${stamp}-old@example.invalid` });
    check(!!old.error, 'L: public key can still call the old join_waitlist function');

    notes.push(`backend under test: ${backend}`);
    notes.push(`browser calls to /api/waitlist: ${posts.length}`);
    notes.push(`rows expected after this run: ${emailA} (homes 2-5, pending after the re-signup), ${emailC} (pending); none for B, D, E, direct, old, homes`);
  } catch (err) {
    problems.push(`scenario threw: ${(err as Error).message}`);
  } finally {
    await browser.close();
    server.close();
  }

  const duration_ms = Date.now() - start;
  const status: 'pass' | 'fail' = problems.length === 0 ? 'pass' : 'fail';
  const details = status === 'pass'
    ? `All checks passed. ${notes.join(' | ')}`
    : `FAILED: ${problems.join(' | ')} | ${notes.join(' | ')}`;
  console.log(`[${id}] ${status.toUpperCase()} (${duration_ms}ms)`);
  return { id, name, layer: 2, status, duration_ms, details, artifacts: { emailA, emailC, stamp } };
}
