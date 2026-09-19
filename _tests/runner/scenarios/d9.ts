import { chromium } from 'playwright';
import { env } from '../lib/env.ts';
import { judgeScreenshot } from '../lib/screenshot-judge.ts';
import { hydratePage, loginAs, VP } from '../lib/playwright-helpers.ts';
import type { ScenarioResult } from '../run.ts';

// D9 — dashboard-delete-processing-01
// Layer 2: the new x button on a Processing card (2026-09-19) -- the
// general "kill it, I'm starting over" escape hatch, available for ANY
// processing state (unlike Stop, which only applies to a first run still
// on the Add Property screen). Starts a real training run (so the card
// genuinely reaches Processing, not a simulated one), opens the dashboard,
// clicks x on that card, confirms the destructive dialog, and checks both
// halves: the card disappears from the live dashboard (same mechanism D5
// already proved for soft-deleted properties) and the row is actually
// soft-deleted server-side (deleted_at set).

const TEST_URL = 'https://airbnb.com/rooms/qa-d9-delete-test';

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

async function getProperty(token: string, id: string): Promise<Record<string, unknown> | null> {
  const res = await fetch(
    `${env.supabaseUrl}/rest/v1/properties?id=eq.${id}&select=deleted_at,status`,
    { headers: { apikey: env.supabaseAnonKey, Authorization: `Bearer ${token}` } },
  );
  const rows = await res.json();
  return rows[0] ?? null;
}

async function getActivePropertyCount(token: string): Promise<number> {
  const res = await fetch(`${env.supabaseUrl}/rest/v1/properties?select=id&deleted_at=is.null`, {
    headers: { apikey: env.supabaseAnonKey, Authorization: `Bearer ${token}` },
  });
  return (await res.json()).length;
}

async function softDelete(token: string, id: string): Promise<void> {
  await fetch(`${env.stagingBackend}/api/property/${id}/soft-delete`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: '{}',
  });
}

export async function runD9(): Promise<ScenarioResult> {
  const start = Date.now();
  const id = 'dashboard-delete-processing-01';
  const name = 'D9: x on a Processing card cancels the run and soft-deletes the property';
  console.log(`[${id}] starting...`);

  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ viewport: VP });
  const page = await context.newPage();

  const notes: string[] = [];
  let status: 'pass' | 'fail' = 'fail';
  let details = '';
  const artifacts: ScenarioResult['artifacts'] = {};
  let capturedId: string | null = null;
  const token = await getAccessToken();

  try {
    let capturedIdResolve: ((v: string) => void) | null = null;
    const capturedIdPromise = new Promise<string>((resolve) => { capturedIdResolve = resolve; });
    page.on('request', (req) => {
      if (req.url().includes('/api/ingest') && req.method() === 'POST') {
        try {
          const body = JSON.parse(req.postData() ?? '{}');
          if (body.property_id) { capturedId = body.property_id; capturedIdResolve?.(body.property_id); }
        } catch {}
      }
    });

    await hydratePage(page);
    await loginAs(page);

    const vp = page.viewportSize() ?? VP;
    const activeCount = await getActivePropertyCount(token);
    const addTileX = 0.11 + activeCount * 0.194;
    await page.mouse.click(vp.width * addTileX, vp.height * 0.367);
    await page.waitForTimeout(2000);

    await page.mouse.click(vp.width * 0.499, vp.height * 0.228);
    await page.waitForTimeout(300);
    await page.keyboard.type(TEST_URL, { delay: 15 });
    await page.mouse.click(vp.width * 0.499, vp.height * 0.903);

    await Promise.race([
      capturedIdPromise,
      new Promise((_, reject) => setTimeout(() => reject(new Error('never saw /api/ingest dispatch')), 8000)),
    ]);
    notes.push(`dispatched, property_id=${capturedId}`);

    // Back to the dashboard: a plain reload rather than the in-app back
    // arrow, which pops a second "Leave while training?" confirmation of
    // its own (discovered live) -- reloading is what a host closing/
    // reopening the tab would do anyway, and it's the same load path
    // hydratePage already uses.
    await page.waitForTimeout(400);
    await hydratePage(page);

    const dashboardShot = await page.screenshot({ fullPage: true });
    artifacts.dashboardScreenshot = dashboardShot.toString('base64');
    const cardVerdict = await judgeScreenshot(
      dashboardShot,
      'A dashboard property card showing "Processing..." with a small x (close) icon next to it.',
    );
    notes.push(`processing-card judge: ${cardVerdict.pass ? 'PASS' : 'FAIL'} — ${cardVerdict.notes}`);
    if (!cardVerdict.pass) throw new Error('Processing card with x button not found on dashboard');

    // The new property sorts first (most-recently-updated) -- click its x,
    // measured live: bottom-left of the first card's action row.
    await page.mouse.click(vp.width * 0.179, vp.height * 0.601);
    await page.waitForTimeout(1000);

    const confirmShot = await page.screenshot({ fullPage: true });
    artifacts.confirmScreenshot = confirmShot.toString('base64');
    const confirmVerdict = await judgeScreenshot(
      confirmShot,
      'A confirmation dialog asking whether to stop and delete a property, warning this can\'t be undone, with a red "Delete Forever" button and a "Cancel" button.',
    );
    notes.push(`confirm-dialog judge: ${confirmVerdict.pass ? 'PASS' : 'FAIL'} — ${confirmVerdict.notes}`);
    if (!confirmVerdict.pass) throw new Error('Delete confirmation dialog did not appear as expected');

    // Confirm the delete -- red "Delete Forever" button (measured live:
    // bottom-right of the dialog, not centered -- the dialog sizes to its
    // content and sits left-of-center on this viewport).
    await page.mouse.click(vp.width * 0.877, vp.height * 0.546);
    // Realtime can silently drop an event (documented elsewhere in this
    // suite -- see B16, and D4's safety-net timer) -- the dashboard's own
    // 10s polling backstop is what actually catches it when that happens,
    // so the wait has to clear that, not just realtime's usual latency. 5s
    // wasn't enough on a real run (DB was already correctly deleted while
    // the card was still showing) -- comfortably past 10s instead.
    await page.waitForTimeout(13000);

    const afterDeleteShot = await page.screenshot({ fullPage: true });
    artifacts.afterDeleteScreenshot = afterDeleteShot.toString('base64');
    const goneVerdict = await judgeScreenshot(
      afterDeleteShot,
      'The plain dashboard, with NO card showing "Processing..." or a "qa-d9-delete-test" property -- it has been removed.',
    );
    notes.push(`card-gone judge: ${goneVerdict.pass ? 'PASS' : 'FAIL'} — ${goneVerdict.notes}`);

    const row = capturedId ? await getProperty(token, capturedId) : null;
    const dbOk = !!row && row.deleted_at != null;
    notes.push(`db check: ${dbOk ? 'PASS' : 'FAIL'} — row=${JSON.stringify(row)}`);

    status = goneVerdict.pass && dbOk ? 'pass' : 'fail';
    details = notes.join(' | ');
  } catch (err) {
    status = 'fail';
    details = `Exception: ${(err as Error).message}. Notes so far: ${notes.join(' | ')}`;
  } finally {
    // Best-effort cleanup regardless of how far the scenario got.
    if (capturedId) {
      try { await softDelete(token, capturedId); } catch {}
    }
    await browser.close();
  }

  return finishWith();

  function finishWith(): ScenarioResult {
    const duration_ms = Date.now() - start;
    console.log(`[${id}] ${status.toUpperCase()} (${duration_ms}ms)`);
    return { id, name, layer: 2, status, duration_ms, details, artifacts };
  }
}
