import { chromium, type Page } from 'playwright';
import { mkdirSync, writeFileSync } from 'node:fs';
import { env } from '../lib/env.ts';
import { judgeScreenshot } from '../lib/screenshot-judge.ts';
import { hydratePage, loginAs, VP } from '../lib/playwright-helpers.ts';
import type { ScenarioResult } from '../run.ts';

// P12 — host-auth-frontend-01
// Layer 2: the backend calls that used to go out with NO token now carry the host's
// session (item B, 2026-10-15) and still work for the owner:
//   - Edit Property's MERGE NOW (POST /api/merge/{id}) -- dev hosts only, so the QA host's own
//     is_dev flag is flipped for that phase and restored in finally
//   - Submit Resolutions       (POST /api/resolve/{id})
// plus the 401 message a host sees if the session is gone ("Your session expired...",
// replacing "Request failed (401)"). Train Now's own POST /api/ingest already sent the token
// and is covered end to end by B1.
// Ground truth is the network (Authorization header on the request, status of the response);
// the vision judge only reads the 401 message off the screen.
// Drives the isolated QA property; its status/master_json are snapshotted and restored.

const API = env.stagingBackend.replace(/\/$/, '');
const PROP = 'aebab5c1-4cf4-4e1d-a3d1-f7c4bc11ff2f';
const SHOTS = process.env.P12_SHOTS_DIR; // debug only

// Fractions of the 1440x900 viewport, measured on real screenshots.
const CARD_BANNER = { x: 0.074, y: 0.609 }; // same as B15
const DRAWER_ACTION = { x: 0.9514, y: 0.2078 }; // same as B15
const RADIO_3PM = { x: 0.276, y: 0.61 }; // Edit Property, first option of the first conflict
const SUBMIT = { x: 0.5, y: 0.748 }; // SUBMIT RESOLUTIONS
const MERGE_NOW = { x: 0.5, y: 0.889 }; // Edit Property, bottom of the page (dev hosts)

type Snap = Record<string, unknown>;
const COLS = 'status,Conflict_status,master_json,resolution_history,resolution_history_json,ingest_heartbeat_at';

async function signIn(): Promise<string> {
  const res = await fetch(`${env.supabaseUrl}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: { apikey: env.supabaseAnonKey, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: env.testHostEmail, password: env.testHostPassword }),
  });
  if (!res.ok) throw new Error(`auth failed: ${res.status}`);
  return ((await res.json()) as any).access_token;
}

export async function runP12(): Promise<ScenarioResult> {
  const start = Date.now();
  const id = 'host-auth-frontend-01';
  const name = 'P12: Merge and Submit Resolutions send the host token and still work; a 401 reads clearly';
  console.log(`[${id}] starting...`);

  const notes: string[] = [];
  const artifacts: ScenarioResult['artifacts'] = {};
  let status: 'pass' | 'fail' = 'fail';
  let details = '';

  const token = await signIn();
  const rest = `${env.supabaseUrl}/rest/v1/properties?id=eq.${PROP}`;
  const H = { apikey: env.supabaseAnonKey, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };
  const original = ((await (await fetch(`${rest}&select=${COLS}`, { headers: H })).json()) as Snap[])[0];
  if (!original) throw new Error('QA property not found');
  const patch = (body: Snap) =>
    fetch(rest, { method: 'PATCH', headers: { ...H, Prefer: 'return=minimal' }, body: JSON.stringify(body) });

  // The QA host's own dev flag (the same one a dev account uses); original value restored in finally.
  const uid = ((await (await fetch(`${env.supabaseUrl}/auth/v1/user`, { headers: H })).json()) as any).id as string;
  const profile = `${env.supabaseUrl}/rest/v1/host_profiles?id=eq.${uid}`;
  const devOriginal = Boolean(((await (await fetch(`${profile}&select=is_dev`, { headers: H })).json()) as any[])[0]?.is_dev);
  const setDev = (v: boolean) =>
    fetch(profile, { method: 'PATCH', headers: { ...H, Prefer: 'return=minimal' }, body: JSON.stringify({ is_dev: v }) });

  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({ viewport: VP });

  type Seen = { path: string; auth: boolean; status: number | null };
  const seen: Seen[] = [];
  page.on('request', (r) => {
    const p = new URL(r.url()).pathname;
    if (r.method() === 'POST' && /^\/api\/(merge|resolve)\//.test(p)) {
      seen.push({ path: p, auth: /^Bearer .{20,}/.test(r.headers()['authorization'] ?? ''), status: null });
    }
  });
  page.on('response', (r) => {
    const p = new URL(r.url()).pathname;
    const s = [...seen].reverse().find((x) => x.path === p && x.status === null);
    if (r.request().method() === 'POST' && s) s.status = r.status();
  });
  let shot = 0;
  const snap = async (label: string) => {
    if (!SHOTS) return;
    mkdirSync(SHOTS, { recursive: true });
    writeFileSync(`${SHOTS}/${String(++shot).padStart(2, '0')}-${label}.png`, await page.screenshot());
  };
  const click = async (fx: number, fy: number) => page.mouse.click(VP.width * fx, VP.height * fy);

  try {
    // ── Phase A: Submit Resolutions ───────────────────────────────────────────
    await patch({
      status: 'Conflict_Pending',
      Conflict_status: 'pending',
      master_json: {
        ...((original.master_json as Snap) ?? {}),
        conflict_report: [{ id: 'q1', question: 'P12 test: what time is check-in?', context: '', options: ['3 PM', '4 PM'] }],
      },
    });
    await hydratePage(page);
    await loginAs(page);
    await click(CARD_BANNER.x, CARD_BANNER.y);
    await page.waitForTimeout(3000);
    await click(DRAWER_ACTION.x, DRAWER_ACTION.y);
    await page.waitForTimeout(3000);
    await snap('edit-property-conflict');

    // The 401 message first: answer the first submit with a 401 and read what the host sees.
    await click(RADIO_3PM.x, RADIO_3PM.y);
    await page.waitForTimeout(500);
    await page.route('**/api/resolve/**', (route) =>
      route.fulfill({ status: 401, contentType: 'application/json', body: '{"detail":"Invalid or expired token"}' }));
    await click(SUBMIT.x, SUBMIT.y);
    await page.waitForTimeout(2500);
    const shot401 = await page.screenshot();
    await snap('after-401');
    const v401 = await judgeScreenshot(
      shot401,
      'A small message bar (snackbar) near the bottom of the screen that says the session expired and ' +
      'to reload the page and sign in again (text like "Your session expired. Reload the page and sign in again."). ' +
      'It must NOT say "Request failed (401)".',
    );
    artifacts.verdict401 = v401.raw;
    notes.push(`401 message: ${v401.pass ? 'PASS' : 'FAIL'} — ${v401.notes}`);
    await page.unroute('**/api/resolve/**');
    await page.waitForTimeout(4500); // let the snackbar go

    // The real submit: must carry the token and succeed.
    await click(SUBMIT.x, SUBMIT.y);
    for (let i = 0; i < 60 && !seen.some((s) => s.path.startsWith('/api/resolve/') && s.status === 200); i++) {
      await page.waitForTimeout(2000);
    }
    await page.waitForTimeout(1500);
    await snap('after-resolve');
    const resolve = seen.filter((s) => s.path === `/api/resolve/${PROP}` && s.status === 200);
    notes.push(`resolve: ${seen.filter((s) => s.path.startsWith('/api/resolve/')).map((s) => `${s.status}${s.auth ? '+token' : ' NO TOKEN'}`).join(', ')}`);

    // ── Phase B: Edit Property's "Merge Now" (dev hosts only: is_dev is flipped for the QA host
    // for this phase and restored in finally; a non-dev host gets the automatic server-side merge) ──
    await setDev(true);
    await patch({ status: 'Ingested', Conflict_status: 'none', ingest_heartbeat_at: new Date().toISOString() });
    await page.reload({ waitUntil: 'networkidle' });
    await page.waitForTimeout(6000);
    await snap('dashboard-ingested');
    await click(0.115, 0.603); // card "Details"
    await page.waitForTimeout(3000);
    await snap('drawer-ingested');
    await click(0.944, 0.209); // drawer "Merge Now" (dev) -> Edit Property
    await page.waitForTimeout(4000);
    await page.mouse.move(VP.width / 2, VP.height / 2);
    await page.mouse.wheel(0, 30000);
    await page.waitForTimeout(1500);
    await snap('edit-property-ingested-bottom');
    await click(MERGE_NOW.x, MERGE_NOW.y);
    for (let i = 0; i < 75 && !seen.some((s) => s.path.startsWith('/api/merge/') && s.status !== null); i++) {
      await page.waitForTimeout(2000);
    }
    await page.waitForTimeout(1500);
    await snap('after-merge');
    const merges = seen.filter((s) => s.path === `/api/merge/${PROP}`);
    notes.push(`merge: ${merges.map((s) => `${s.status}${s.auth ? '+token' : ' NO TOKEN'}`).join(', ') || 'no request'}`);

    // Every merge/resolve request the UI sent carried the session token; the real ones came back 200.
    const allAuth = seen.length > 0 && seen.every((s) => s.auth);
    const resolveOk = resolve.length > 0;
    const mergeOk = merges.some((s) => s.status === 200);
    status = v401.pass && allAuth && resolveOk && mergeOk ? 'pass' : 'fail';
    details = notes.join(' | ');
  } catch (err) {
    status = 'fail';
    details = `Exception: ${(err as Error).message}. Notes so far: ${notes.join(' | ')}`;
  } finally {
    await patch(original as Snap).catch(() => undefined);
    await setDev(devOriginal).catch(() => undefined);
    await browser.close();
  }

  const duration_ms = Date.now() - start;
  console.log(`[${id}] ${status.toUpperCase()} (${duration_ms}ms)`);
  return { id, name, layer: 2, status, duration_ms, details, artifacts };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  runP12().then((r) => {
    console.log(r.details.split(' | ').join('\n'));
    process.exit(r.status === 'pass' ? 0 : 1);
  });
}
