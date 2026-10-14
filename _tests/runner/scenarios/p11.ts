import { chromium, type Page } from 'playwright';
import { mkdirSync, writeFileSync } from 'node:fs';
import { env, stagingUrlWithBypass } from '../lib/env.ts';
import { judgeScreenshot } from '../lib/screenshot-judge.ts';
import { hydratePage, loginAs, VP } from '../lib/playwright-helpers.ts';
import type { ScenarioResult } from '../run.ts';

// P11 — host-alert-link-01
// Layer 2: the escalation alert's "Open full conversation" link (/chat-live?booking=...).
// Found 2026-10-02: anyone who wasn't signed in as the property's owner saw an empty
// "No messages yet / Autopilot / Alfred is handling this conversation" screen for a
// conversation that was really in `intervene` with a live EMERGENCY (RLS is owner-scoped,
// so a non-owner reads zero rows and the screen rendered its defaults). Now:
//   - owner: full thread (unchanged); owner with a guest who hasn't written yet (only
//     Alfred's welcome): the normal Autopilot view (must not be mistaken for "no access")
//   - logged out: sign-in screen with a notice, and after signing in the SAME conversation
//   - signed in as a different host: "You don't have access to this conversation."
//   - the guest lookup failing: "Couldn't load" + Try again, which recovers
// Ground truth is the network (rows each REST read returned); the vision judge only
// confirms what the person would SEE, phrased as positive text to look for.
// FOREIGN_BOOKING is an existing staging booking owned by another host (read-only here;
// if it is ever deleted the case still shows the same message, it just loses the
// "real other host" meaning).

const API = env.stagingBackend.replace(/\/$/, '');
const PROP = 'aebab5c1-4cf4-4e1d-a3d1-f7c4bc11ff2f'; // QA host's trained property (staging)
const FOREIGN_BOOKING = 'bungalow-63x4ns';
const SHOTS = process.env.P11_SHOTS_DIR; // debug only

// Fractions of the 1440x900 viewport, measured on real screenshots.
const LINK_LOGIN = { x: 0.75, emailY: 0.5, passwordY: 0.555 } as const; // sign-in screen WITH the notice
const CENTER_BUTTON = [0.5, 0.58] as const; // "Back to dashboard" / "Try again"

async function signIn(): Promise<string> {
  const res = await fetch(`${env.supabaseUrl}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: { apikey: env.supabaseAnonKey, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: env.testHostEmail, password: env.testHostPassword }),
  });
  const json = (await res.json()) as any;
  if (!res.ok) throw new Error(`auth failed: ${res.status}`);
  return json.access_token;
}

type Read = { table: string; status: number; rows: number };
function watch(page: Page): Read[] {
  const reads: Read[] = [];
  page.on('response', async (res) => {
    const u = res.url();
    const m = u.match(/\/rest\/v1\/(guests|conversations|messages)\?/);
    if (!m || res.request().method() !== 'GET') return;
    let rows = -1;
    try { rows = ((await res.json()) as unknown[]).length; } catch { /* not JSON */ }
    reads.push({ table: m[1], status: res.status(), rows });
  });
  return reads;
}
const rowsOf = (reads: Read[], table: string) =>
  reads.filter((r) => r.table === table && r.status === 200).map((r) => r.rows);

export async function runP11(): Promise<ScenarioResult> {
  const start = Date.now();
  const id = 'host-alert-link-01';
  const name = 'P11: Alert link opens the conversation for the owner and says the truth to everyone else';
  console.log(`[${id}] starting...`);

  const notes: string[] = [];
  const artifacts: ScenarioResult['artifacts'] = {};
  let status: 'pass' | 'fail' = 'fail';
  let details = '';
  const token = await signIn();
  const H = { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };
  const rest = (path: string) =>
    fetch(`${env.supabaseUrl}/rest/v1/${path}`, { headers: { apikey: env.supabaseAnonKey, Authorization: `Bearer ${token}` } })
      .then((r) => r.json() as Promise<any[]>);
  const newGuest = async (label: string) => {
    const r = await fetch(`${API}/api/guests`, { method: 'POST', headers: H, body: JSON.stringify({ property_id: PROP, guest_name: label }) });
    if (!r.ok) throw new Error(`create guest ${r.status}`);
    return ((await r.json()) as any).booking_id as string;
  };

  const need = (label: string, ok: boolean, extra = '') => {
    notes.push(`${label}: ${ok ? 'PASS' : 'FAIL'}${extra ? ` (${extra})` : ''}`);
    if (!ok) throw new Error(`${label} failed${extra ? ` (${extra})` : ''}`);
  };

  const browser = await chromium.launch({ headless: true });
  const cleanup: string[] = []; // booking ids to resolve + archive
  const shot = async (page: Page, label: string) => {
    const png = await page.screenshot({ fullPage: true });
    artifacts[label] = png.toString('base64');
    if (SHOTS) { mkdirSync(SHOTS, { recursive: true }); writeFileSync(`${SHOTS}/${label}.png`, png); }
    return png;
  };
  const judge = async (page: Page, label: string, expectation: string) => {
    const v = await judgeScreenshot(await shot(page, label), expectation);
    notes.push(`${label} judge: ${v.pass ? 'PASS' : 'FAIL'} — ${v.notes}`);
    if (!v.pass) throw new Error(`${label}: screen did not match — ${v.notes}`);
  };
  const open = async (page: Page, booking: string) => {
    await page.goto(stagingUrlWithBypass(`/chat-live?booking=${booking}&property=${PROP}`), { waitUntil: 'networkidle', timeout: 60_000 });
    await page.waitForTimeout(8_000);
  };
  const threadExpectation =
    'A "Live Chat" screen. The left column shows a conversation containing a red-outlined guest message about a fire in the kitchen and a red Alfred reply labeled EMERGENCY. The right panel shows an "Intervene" mode toggle that is active and a purple "Mark Issue as Resolved" button.';

  try {
    // Fixture A: a real emergency, so the conversation really is in `intervene`.
    const A = await newGuest('P11 emergency guest');
    cleanup.push(A);
    await fetch(`${API}/api/messages/web-incoming`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ booking_id: A, message: 'There is a fire in the kitchen! Emergency, please help right now!' }),
    });
    let mode = '';
    for (let i = 0; i < 20 && mode !== 'intervene'; i++) {
      mode = (await rest(`conversations?booking_id=eq.${A}&select=mode`))[0]?.mode ?? '';
      if (mode !== 'intervene') await new Promise((r) => setTimeout(r, 3000));
    }
    need('fixture: conversation A is in intervene (DB)', mode === 'intervene');
    // Fixture B: a guest link nobody has used yet (only Alfred's welcome message).
    const B = await newGuest('P11 quiet guest');
    cleanup.push(B);

    // 1 + 2. The owner (signed in as the QA host).
    const ownerCtx = await browser.newContext({ viewport: VP });
    const owner = await ownerCtx.newPage();
    await hydratePage(owner);
    await loginAs(owner);
    let reads = watch(owner);
    await open(owner, A);
    need('owner: guest row readable', rowsOf(reads, 'guests').includes(1), JSON.stringify(rowsOf(reads, 'guests')));
    need('owner: thread loaded (>=3 messages)', rowsOf(reads, 'messages').some((n) => n >= 3), JSON.stringify(rowsOf(reads, 'messages')));
    await judge(owner, 'owner-thread', threadExpectation);

    reads.length = 0;
    await open(owner, B);
    need('owner, guest hasn\'t written yet: guest row readable', rowsOf(reads, 'guests').includes(1));
    await judge(
      owner,
      'owner-quiet',
      'A "Live Chat" screen. The left column under "Conversation" shows one grey Alfred message, a welcome greeting that starts with "Bienvenido". There is no red message. The right panel shows the "Autopilot" mode toggle active and the text "Alfred is handling this conversation." The right panel also has a "Guest Chat Link" box.',
    );

    // 5. The guest lookup fails once (connection drops / backend error): honest message, retry recovers.
    let failedOnce = false;
    await owner.route('**/rest/v1/guests?*', (route) => {
      if (!failedOnce) { failedOnce = true; return route.abort('failed'); }
      return route.continue();
    });
    await open(owner, A);
    need('load failure: the guest lookup was blocked once', failedOnce);
    await judge(
      owner,
      'load-failed',
      'A centered message reading "Couldn\'t load this conversation." with the line "Check your connection and try again." and a "Try again" button.',
    );
    await owner.mouse.click(VP.width * CENTER_BUTTON[0], VP.height * CENTER_BUTTON[1]);
    await owner.waitForTimeout(6_000);
    await judge(owner, 'load-recovered', threadExpectation);
    await owner.unroute('**/rest/v1/guests?*');

    // 4. Signed in, but the booking belongs to another host.
    reads.length = 0;
    await open(owner, FOREIGN_BOOKING);
    need('non-owner: the guest read returned 0 rows (RLS)', rowsOf(reads, 'guests').length > 0 && rowsOf(reads, 'guests').every((n) => n === 0), JSON.stringify(rowsOf(reads, 'guests')));
    await judge(
      owner,
      'no-access',
      'A centered message reading "You don\'t have access to this conversation." with the line "Are you signed in as this property\'s host?" and a "Back to dashboard" button. The screen does not show a conversation or a mode toggle.',
    );
    await owner.mouse.click(VP.width * CENTER_BUTTON[0], VP.height * CENTER_BUTTON[1]);
    await owner.waitForTimeout(4_000);
    await judge(owner, 'back-to-dashboard', 'The host dashboard: a top app bar and a grid of property cards (one card is titled "Beautiful House with Cascade Pool").');
    await ownerCtx.close();

    // 3. Logged out (a phone that isn't signed in): sign in, land on the SAME conversation.
    const outCtx = await browser.newContext({ viewport: VP });
    const out = await outCtx.newPage();
    reads = watch(out);
    await open(out, A);
    need('logged out: nothing was read before signing in', reads.length === 0, JSON.stringify(reads));
    await judge(
      out,
      'logged-out',
      'The Alfred sign-in screen: a notice reading "Sign in to open this conversation." above an Email field and a Password field with a sign-in button. No conversation is shown.',
    );
    await out.mouse.click(VP.width * LINK_LOGIN.x, VP.height * LINK_LOGIN.emailY);
    await out.keyboard.type(env.testHostEmail, { delay: 30 });
    await out.mouse.click(VP.width * LINK_LOGIN.x, VP.height * LINK_LOGIN.passwordY);
    await out.keyboard.type(env.testHostPassword, { delay: 30 });
    await out.keyboard.press('Enter');
    await out.waitForTimeout(9_000);
    need('logged out -> signed in: landed on the conversation (guest row + thread read)',
      rowsOf(reads, 'guests').includes(1) && rowsOf(reads, 'messages').some((n) => n >= 3), JSON.stringify(reads));
    await judge(out, 'after-sign-in', threadExpectation);
    await outCtx.close();

    status = 'pass';
    details = notes.join(' | ');
  } catch (err) {
    status = 'fail';
    details = `Exception: ${(err as Error).message}. Notes so far: ${notes.join(' | ')}`;
  } finally {
    // Leave no open emergencies behind.
    for (const b of cleanup) {
      try {
        await fetch(`${API}/api/conversations/resolve`, { method: 'POST', headers: H, body: JSON.stringify({ booking_id: b }) });
        const cid = (await rest(`conversations?booking_id=eq.${b}&select=id`))[0]?.id;
        if (cid) await fetch(`${API}/api/conversations/archive`, { method: 'POST', headers: H, body: JSON.stringify({ conversation_id: cid }) });
      } catch { /* best effort */ }
    }
    await browser.close();
  }

  const duration_ms = Date.now() - start;
  console.log(`[${id}] ${status.toUpperCase()} (${duration_ms}ms)`);
  return { id, name, layer: 2, status, duration_ms, details, artifacts };
}

// Allow running this scenario on its own: npx tsx scenarios/p11.ts
if (import.meta.url === `file://${process.argv[1]}`) {
  runP11().then((r) => {
    console.log(r.details.split(' | ').join('\n'));
    process.exit(r.status === 'pass' ? 0 : 1);
  });
}
