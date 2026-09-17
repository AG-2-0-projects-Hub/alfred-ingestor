import { chromium } from 'playwright';
import { judgeScreenshot } from '../lib/screenshot-judge.ts';
import { hydratePage, loginAs, VP, APPBAR } from '../lib/playwright-helpers.ts';
import { env } from '../lib/env.ts';
import type { ScenarioResult } from '../run.ts';

// B15 — property-drawer-nav-01
// Layer 2: the property drawer's "go to Edit Property" buttons used to do
// `Navigator.pop()` immediately followed by `Navigator.push()` as two
// separate steps. Live-found (2026-09-17): after resolving a conflict on
// Edit Property and pressing the in-app back arrow, the drawer reappeared
// showing its stale pre-resolve state, with the (already-correct) dashboard
// visible behind it. Fix: a single atomic `Navigator.pushReplacement()` so
// the drawer's own route can never survive underneath Edit Property.
//
// This scenario drives the exact round-trip (dedicated, isolated QA
// property -- never the founder's real data): dashboard -> open the drawer
// via the card's "Resolve conflicts" banner -> click the drawer's own
// "Resolve" action -> Edit Property screen -> in-app back arrow -> assert
// the dashboard shows plainly, with no drawer/side-panel visible.
//
// Uses a direct DB write (not a real scrape/merge cycle) to put the
// property into Conflict_Pending, since only the navigation-survival bug is
// in scope here -- the merge/conflict-detection pipeline itself is covered
// by other scenarios (B12, B13). State is captured before the test and
// restored in `finally` no matter the outcome.

const QA_PROPERTY_ID = 'aebab5c1-4cf4-4e1d-a3d1-f7c4bc11ff2f';
const CARD_RESOLVE_BANNER = { x: 0.074, y: 0.609 };
const DRAWER_RESOLVE_BUTTON = { x: 0.9514, y: 0.2078 };

type PropertySnapshot = {
  status: string | null;
  Conflict_status: string | null;
  master_json: Record<string, unknown> | null;
};

async function getAccessToken(): Promise<string> {
  const res = await fetch(`${env.supabaseUrl}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: { apikey: env.supabaseAnonKey, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: env.testHostEmail, password: env.testHostPassword }),
  });
  const json = await res.json();
  if (!res.ok) throw new Error(`auth failed: ${JSON.stringify(json)}`);
  return json.access_token as string;
}

async function readProperty(token: string): Promise<PropertySnapshot> {
  const res = await fetch(
    `${env.supabaseUrl}/rest/v1/properties?id=eq.${QA_PROPERTY_ID}&select=status,Conflict_status,master_json`,
    { headers: { apikey: env.supabaseAnonKey, Authorization: `Bearer ${token}` } },
  );
  const [row] = await res.json();
  if (!row) throw new Error('QA property not found');
  return row as PropertySnapshot;
}

async function writeProperty(token: string, snapshot: PropertySnapshot): Promise<void> {
  const res = await fetch(`${env.supabaseUrl}/rest/v1/properties?id=eq.${QA_PROPERTY_ID}`, {
    method: 'PATCH',
    headers: {
      apikey: env.supabaseAnonKey,
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
      Prefer: 'return=minimal',
    },
    body: JSON.stringify(snapshot),
  });
  if (!res.ok) throw new Error(`patch failed: ${res.status} ${await res.text()}`);
}

export async function runB15(): Promise<ScenarioResult> {
  const start = Date.now();
  const id = 'property-drawer-nav-01';
  const name = 'B15: Drawer does not reappear after Edit Property back-arrow';
  console.log(`[${id}] starting...`);

  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ viewport: VP });
  const page = await context.newPage();
  const notes: string[] = [];
  let status: 'pass' | 'fail' = 'fail';
  let details = '';
  const artifacts: ScenarioResult['artifacts'] = {};

  const token = await getAccessToken();
  const original = await readProperty(token);
  notes.push(`captured original state: ${original.status}/${original.Conflict_status}`);

  try {
    await writeProperty(token, {
      status: 'Conflict_Pending',
      Conflict_status: 'pending',
      master_json: {
        ...(original.master_json ?? {}),
        conflict_report: [{ id: 'q1', question: 'Test conflict', options: ['A', 'B'] }],
      },
    });
    notes.push('DB set to Conflict_Pending');

    await hydratePage(page);
    await loginAs(page);
    notes.push('logged in');

    const vp = page.viewportSize() ?? VP;
    await page.mouse.click(vp.width * CARD_RESOLVE_BANNER.x, vp.height * CARD_RESOLVE_BANNER.y);
    await page.waitForTimeout(3000);
    notes.push('clicked card Resolve-conflicts banner');

    await page.mouse.click(vp.width * DRAWER_RESOLVE_BUTTON.x, vp.height * DRAWER_RESOLVE_BUTTON.y);
    await page.waitForTimeout(3000);
    notes.push('clicked drawer Resolve action');

    const editSS = await page.screenshot({ fullPage: true });
    const editVerdict = await judgeScreenshot(
      editSS,
      'An "Edit Property" screen with a back arrow top-left, a property name field, ' +
      'and a list of ingested files. Must NOT show the dashboard or a right-aligned side panel.',
    );
    artifacts.editVerdict = editVerdict.raw;
    notes.push(`edit-property judge: ${editVerdict.pass ? 'PASS' : 'FAIL'} — ${editVerdict.notes}`);

    await page.mouse.click(vp.width * APPBAR.backX, vp.height * APPBAR.backY);
    await page.waitForTimeout(3000);
    notes.push('clicked in-app back arrow');

    const backSS = await page.screenshot({ fullPage: true });
    artifacts.backScreenshot = backSS.toString('base64');
    const backVerdict = await judgeScreenshot(
      backSS,
      'The plain dashboard with property cards, filling the full width. Must NOT show ' +
      'a right-aligned drawer/side-panel overlay (a panel occupying roughly the right ' +
      'third of the screen with its own header, tabs, and close button).',
    );
    artifacts.backVerdict = backVerdict.raw;
    notes.push(`post-back judge: ${backVerdict.pass ? 'PASS' : 'FAIL'} — ${backVerdict.notes}`);

    status = editVerdict.pass && backVerdict.pass ? 'pass' : 'fail';
    details = notes.join(' | ');
  } catch (err) {
    status = 'fail';
    details = `Exception: ${(err as Error).message}. Notes: ${notes.join(' | ')}`;
  } finally {
    await writeProperty(token, original);
    await browser.close();
  }

  return finish();

  function finish(): ScenarioResult {
    const duration_ms = Date.now() - start;
    console.log(`[${id}] ${status.toUpperCase()} (${duration_ms}ms)`);
    return { id, name, layer: 2, status, duration_ms, details, artifacts };
  }
}
