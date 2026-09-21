import { chromium } from 'playwright';
import { judgeScreenshot } from '../lib/screenshot-judge.ts';
import { hydratePage, loginAs, VP } from '../lib/playwright-helpers.ts';
import { env } from '../lib/env.ts';
import type { ScenarioResult } from '../run.ts';

// B16 — dashboard-completion-popup-01
// Layer 2: the "Alfred is now trained" popup must fire the moment a broken-
// link retry resolves cleanly (no new conflict) -- even when the property's
// coarse status label never changes value (e.g. "Trained" the whole time,
// which is the common case: only the separate scrape_retry field actually
// transitions). Two real bugs found live and fixed together:
//
//   1. The popup was only wired to a status-label transition check, which
//      this exact flow never satisfies -- it used to show a small SnackBar
//      instead, driven by the one signal that IS correct here
//      (scrape_retry pending -> resolved). Now that signal drives the same
//      big popup every other completion flow uses.
//   2. That signal only had one chance to fire: the realtime subscription.
//      Confirmed live (staging) that Supabase's realtime can silently drop
//      a given update -- the dashboard already had a 10s polling fallback
//      for the card's own data for exactly this documented reason, but
//      nothing was wired to also re-run the completion checks against a
//      polled fetch. A dropped realtime event meant the popup simply never
//      fired, even though the card would go on to look correct within 10s.
//
// Drives the DB transitions directly (not through a real, slow, non-
// deterministic live scrape) -- this isolates exactly the frontend logic
// that changed. Runs against the isolated QA property only.

const PROPERTY_ID = 'aebab5c1-4cf4-4e1d-a3d1-f7c4bc11ff2f';
const ORIGINAL = { status: 'Trained', scrape_retry: {} as Record<string, unknown> };
const NEEDS_ATTENTION = {
  status: 'Trained',
  scrape_retry: { attempts: 2, next_retry_at: null, reason: 'unreachable', retrying: false },
};
const RETRYING = {
  status: 'Trained',
  scrape_retry: { attempts: 2, next_retry_at: null, reason: 'unreachable', retrying: true },
};
const RESOLVED = { status: 'Trained', scrape_retry: {} as Record<string, unknown> };

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

async function patchProperty(token: string, fields: Record<string, unknown>): Promise<void> {
  const res = await fetch(`${env.supabaseUrl}/rest/v1/properties?id=eq.${PROPERTY_ID}`, {
    method: 'PATCH',
    headers: {
      apikey: env.supabaseAnonKey,
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
      Prefer: 'return=minimal',
    },
    body: JSON.stringify(fields),
  });
  if (!res.ok) throw new Error(`patch failed: ${res.status} ${await res.text()}`);
}

export async function runB16(): Promise<ScenarioResult> {
  const start = Date.now();
  const id = 'dashboard-completion-popup-01';
  const name = 'B16: Trained popup fires after a clean link-retry, even if realtime drops the event';
  console.log(`[${id}] starting...`);

  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ viewport: VP });
  const page = await context.newPage();
  const notes: string[] = [];
  let status: 'pass' | 'fail' = 'fail';
  let details = '';
  const artifacts: ScenarioResult['artifacts'] = {};

  const token = await getAccessToken();

  try {
    await patchProperty(token, NEEDS_ATTENTION);
    notes.push('DB set to needs-attention (seed)');

    await hydratePage(page);
    await loginAs(page);
    notes.push('logged in, dashboard loaded (seed observation)');

    // Let the realtime subscription fully establish before introducing any
    // change -- this is not what's under test, just avoiding a startup race.
    await page.waitForTimeout(20000);

    await patchProperty(token, RETRYING);
    notes.push('DB: retrying=true');
    // A real retry-scrape takes much longer than this in production (network
    // + Firecrawl + possible Gemini merge) -- staying in this state for a
    // realistic duration, not a few seconds, so there's a real window for
    // either realtime or the 10s poll to actually observe it.
    await page.waitForTimeout(15000);

    await patchProperty(token, RESOLVED);
    notes.push('DB: resolved (scrape_retry cleared, status label unchanged)');
    await page.waitForTimeout(14000);

    const afterResolve = await page.screenshot({ fullPage: true });
    artifacts.popupScreenshot = afterResolve.toString('base64');
    const popupVerdict = await judgeScreenshot(
      afterResolve,
      'A popup/dialog confirming Alfred is now trained and ready, with a "Back to Dashboard" button. Must NOT be a bare dashboard with no dialog.',
    );
    artifacts.popupVerdict = popupVerdict.raw;
    notes.push(`popup judge: ${popupVerdict.pass ? 'PASS' : 'FAIL'} — ${popupVerdict.notes}`);

    let dismissVerdict = { pass: false, notes: 'not reached' };
    if (popupVerdict.pass) {
      const vp = page.viewportSize() ?? VP;
      await page.mouse.click(vp.width * 0.5, vp.height * 0.642);
      await page.waitForTimeout(1500);
      const afterDismiss = await page.screenshot({ fullPage: true });
      artifacts.dismissScreenshot = afterDismiss.toString('base64');
      dismissVerdict = await judgeScreenshot(
        afterDismiss,
        'The plain, bare dashboard with property cards. Must NOT show a dialog/modal popup or a ' +
        'right-aligned drawer/side-panel overlay. A small onboarding hint bubble near the bottom ' +
        'of a property card (e.g. "STEP 0", tips about +Guest/Settings buttons) is expected and OK.',
      );
      notes.push(`dismiss judge: ${dismissVerdict.pass ? 'PASS' : 'FAIL'} — ${dismissVerdict.notes}`);
    }

    status = popupVerdict.pass && dismissVerdict.pass ? 'pass' : 'fail';
    details = notes.join(' | ');
  } catch (err) {
    status = 'fail';
    details = `Exception: ${(err as Error).message}. Notes: ${notes.join(' | ')}`;
  } finally {
    await patchProperty(token, ORIGINAL);
    await browser.close();
  }

  return finish();

  function finish(): ScenarioResult {
    const duration_ms = Date.now() - start;
    console.log(`[${id}] ${status.toUpperCase()} (${duration_ms}ms)`);
    return { id, name, layer: 2, status, duration_ms, details, artifacts };
  }
}
