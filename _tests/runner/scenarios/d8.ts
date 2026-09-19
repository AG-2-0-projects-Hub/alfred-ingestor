import { chromium } from 'playwright';
import { env } from '../lib/env.ts';
import { judgeScreenshot } from '../lib/screenshot-judge.ts';
import { hydratePage, loginAs, VP } from '../lib/playwright-helpers.ts';
import type { ScenarioResult } from '../run.ts';

// D8 — add-property-stop-01
// Layer 2: the new Stop button (2026-09-19), first-training-run only.
// Fills the Airbnb URL, clicks Train Now, then clicks Stop almost
// immediately (the dispatcher itself returns in well under a second, so
// the run is genuinely in flight by the time Stop is clicked, not merely
// simulated) -- then confirms both halves of the fix: the form is back to
// its editable state, and the property row itself was actually rolled
// back server-side (ingest_run_id/status cleared, master_json still null,
// airbnb_url preserved), not just the screen. Cleans up the property
// afterward via the same cancel endpoint under test.

const TEST_URL = 'https://airbnb.com/rooms/qa-d8-stop-test';

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
    `${env.supabaseUrl}/rest/v1/properties?id=eq.${id}&select=status,ingest_run_id,master_json,airbnb_url,name`,
    { headers: { apikey: env.supabaseAnonKey, Authorization: `Bearer ${token}` } },
  );
  const rows = await res.json();
  return rows[0] ?? null;
}

async function cancelProperty(token: string, id: string): Promise<void> {
  await fetch(`${env.stagingBackend}/api/property/${id}/cancel-initial-train`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: '{}',
  });
}

async function getActivePropertyCount(token: string): Promise<number> {
  const res = await fetch(`${env.supabaseUrl}/rest/v1/properties?select=id&deleted_at=is.null`, {
    headers: { apikey: env.supabaseAnonKey, Authorization: `Bearer ${token}` },
  });
  return (await res.json()).length;
}

export async function runD8(): Promise<ScenarioResult> {
  const start = Date.now();
  const id = 'add-property-stop-01';
  const name = 'D8: Stop on the first training run rolls back the row, keeps the form filled in';
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
    notes.push('logged in');

    const vp = page.viewportSize() ?? VP;
    // "+ Add Property" tile sits right after the last real (non-deleted)
    // property in the grid -- computed live rather than hardcoded, since a
    // fixed coordinate silently pointed at the wrong card once a previous
    // run's leftover property changed the grid's card count.
    const activeCount = await getActivePropertyCount(token);
    const addTileX = 0.11 + activeCount * 0.194;
    await page.mouse.click(vp.width * addTileX, vp.height * 0.367);
    await page.waitForTimeout(2000);

    // Airbnb URL field, then Train Now (both measured live this session on
    // the actual Add Property screen).
    await page.mouse.click(vp.width * 0.499, vp.height * 0.228);
    await page.waitForTimeout(300);
    await page.keyboard.type(TEST_URL, { delay: 15 });
    await page.mouse.click(vp.width * 0.499, vp.height * 0.903);

    await Promise.race([
      capturedIdPromise,
      new Promise((_, reject) => setTimeout(() => reject(new Error('never saw /api/ingest dispatch')), 8000)),
    ]);
    notes.push(`dispatched, property_id=${capturedId}`);

    // The non-dismissible TrainingWaitDialog covers the screen (including
    // the Stop button underneath it) the instant Train Now is clicked --
    // discovered live this session while measuring these coordinates.
    // "Continue in background" dismisses it without cancelling anything, so
    // the Stop button can actually be reached.
    await page.waitForTimeout(400);
    await page.mouse.click(vp.width * 0.5, vp.height * 0.687);
    await page.waitForTimeout(400);

    // Click Stop as fast as realistically possible after that -- the whole
    // point is proving it works on a genuinely in-flight run, not one
    // that's had time to finish.
    await page.mouse.click(vp.width * 0.5, vp.height * 0.960);
    await page.waitForTimeout(1500);

    const afterStop = await page.screenshot({ fullPage: true });
    artifacts.afterStopScreenshot = afterStop.toString('base64');
    const uiVerdict = await judgeScreenshot(
      afterStop,
      'The Add Property form, back to its normal editable state: a "TRAIN NOW" button (not a spinner, not "Stop"), with the Airbnb URL field still showing a filled-in URL (not empty).',
    );
    artifacts.uiVerdict = uiVerdict.raw;
    notes.push(`UI judge: ${uiVerdict.pass ? 'PASS' : 'FAIL'} — ${uiVerdict.notes}`);

    // Give the backend write a moment to land, then check the row directly.
    await new Promise((r) => setTimeout(r, 1500));
    const row = capturedId ? await getProperty(token, capturedId) : null;
    const dbOk = !!row &&
      row.status == null &&
      row.ingest_run_id == null &&
      row.master_json == null &&
      row.airbnb_url === TEST_URL;
    notes.push(`db check: ${dbOk ? 'PASS' : 'FAIL'} — row=${JSON.stringify(row)}`);

    status = uiVerdict.pass && dbOk ? 'pass' : 'fail';
    details = notes.join(' | ');
  } catch (err) {
    status = 'fail';
    details = `Exception: ${(err as Error).message}. Notes so far: ${notes.join(' | ')}`;
  } finally {
    if (capturedId) {
      try { await cancelProperty(token, capturedId); } catch {}
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
