import { chromium } from 'playwright';
import { env } from '../lib/env.ts';
import { judgeScreenshot } from '../lib/screenshot-judge.ts';
import { hydratePage, loginAs, VP, DASHBOARD } from '../lib/playwright-helpers.ts';
import type { ScenarioResult } from '../run.ts';

// P1 — tgh-connect-01
// Layer 2: the "Connect Telegram" UI in the profile dialog (host-side
// Telegram escalation feature, 2026-09-22/23) -- link/QR generation and the
// "How to use" help panel. Deliberately does NOT attempt a real Telegram
// link (would need an actual Telegram client tapping Start, which
// Playwright can't drive) -- that mechanic is proven live by the founder
// (see _tests/scenarios.md P1's own note) and by the backend logic itself,
// unchanged this session. This scenario only verifies the UI renders and
// behaves correctly up to generating the link/QR and showing/hiding the
// help panel, handling both the unlinked and already-linked account states.

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

async function getUserId(token: string): Promise<string> {
  const res = await fetch(`${env.supabaseUrl}/auth/v1/user`, {
    headers: { apikey: env.supabaseAnonKey, Authorization: `Bearer ${token}` },
  });
  const json = await res.json();
  if (!res.ok) throw new Error(`auth/v1/user failed: ${JSON.stringify(json)}`);
  return json.id as string;
}

async function clearLinkCode(token: string, userId: string): Promise<void> {
  await fetch(`${env.supabaseUrl}/rest/v1/host_profiles?id=eq.${userId}`, {
    method: 'PATCH',
    headers: {
      apikey: env.supabaseAnonKey,
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
      Prefer: 'return=minimal',
    },
    body: JSON.stringify({ telegram_link_code: null, telegram_link_code_expires_at: null }),
  });
}

export async function runP1(): Promise<ScenarioResult> {
  const start = Date.now();
  const id = 'tgh-connect-01';
  const name = 'P1: Connect-Telegram UI (link/QR) + How-to-use help panel';
  console.log(`[${id}] starting...`);

  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ viewport: VP });
  const page = await context.newPage();

  const notes: string[] = [];
  let status: 'pass' | 'fail' = 'fail';
  let details = '';
  const artifacts: ScenarioResult['artifacts'] = {};
  const token = await getAccessToken();
  const userId = await getUserId(token);

  try {
    await hydratePage(page);
    await loginAs(page);
    notes.push('logged in');

    const vp = page.viewportSize() ?? VP;

    // Profile icon -- immediately left of the top-bar Settings gear
    // (DASHBOARD.settingsIconX/Y, one IconButton-width over). No prior
    // calibrated constant existed for this icon; measured live against a
    // real 1440x900 screenshot this session.
    const profileX = DASHBOARD.settingsIconX - 0.036;
    const profileY = DASHBOARD.settingsIconY;
    await page.mouse.click(vp.width * profileX, vp.height * profileY);
    await page.waitForTimeout(1200);

    const profileShot = await page.screenshot({ fullPage: true });
    artifacts.profileScreenshot = profileShot.toString('base64');
    const profileVerdict = await judgeScreenshot(
      profileShot,
      'A "Your profile" dialog with a "Telegram alerts" section, showing either a "Connect Telegram" button or a "Telegram connected" message, and a "How to use" link near it.',
    );
    notes.push(`profile-dialog judge: ${profileVerdict.pass ? 'PASS' : 'FAIL'} — ${profileVerdict.notes}`);
    if (!profileVerdict.pass) throw new Error('Profile dialog with Telegram section did not render as expected');

    // Handle both states: click Connect Telegram only if not already linked.
    const linkedShot = await page.screenshot({ fullPage: true });
    const linkedVerdict = await judgeScreenshot(
      linkedShot,
      'A "Telegram alerts" section that already shows "Telegram connected" (a green checkmark and confirmation text), with NO "Connect Telegram" button visible.',
    );
    const alreadyLinked = linkedVerdict.pass;
    notes.push(`already-linked check: ${alreadyLinked ? 'YES' : 'NO'} — ${linkedVerdict.notes}`);

    // "How to use" sits at a different height depending on whether the
    // QR/link block below it is showing (dialog grows and re-centers) --
    // measured live for both states this session.
    let howToUseY = 0.668;

    if (!alreadyLinked) {
      // Connect Telegram button -- centered button below the Telegram alerts row.
      await page.mouse.click(vp.width * 0.5, vp.height * 0.700);
      await page.waitForTimeout(1500);

      const qrShot = await page.screenshot({ fullPage: true });
      artifacts.qrScreenshot = qrShot.toString('base64');
      const qrVerdict = await judgeScreenshot(
        qrShot,
        'A QR code and a copyable Telegram deep link (starting with https://) displayed in a panel below a "Connect Telegram" button, inside the profile dialog.',
      );
      notes.push(`qr-link judge: ${qrVerdict.pass ? 'PASS' : 'FAIL'} — ${qrVerdict.notes}`);
      if (!qrVerdict.pass) throw new Error('QR code / deep link did not render after clicking Connect Telegram');

      howToUseY = 0.583;
    }

    // How to use -- docks a side panel via CompositedTransformFollower.
    await page.mouse.click(vp.width * 0.614, vp.height * howToUseY);
    await page.waitForTimeout(800);

    const helpShot = await page.screenshot({ fullPage: true });
    artifacts.helpScreenshot = helpShot.toString('base64');
    const helpVerdict = await judgeScreenshot(
      helpShot,
      'A panel titled "How Telegram replies work" with several bullet points, docked beside the "Your profile" dialog (not covering it), with some bold text within the bullets and a close (X) button.',
    );
    notes.push(`help-panel judge: ${helpVerdict.pass ? 'PASS' : 'FAIL'} — ${helpVerdict.notes}`);
    if (!helpVerdict.pass) throw new Error('How-to-use help panel did not render as expected');

    // Close the help panel by clicking "How to use" again (toggle off).
    await page.mouse.click(vp.width * 0.614, vp.height * howToUseY);
    await page.waitForTimeout(500);

    const closedShot = await page.screenshot({ fullPage: true });
    artifacts.closedScreenshot = closedShot.toString('base64');
    const closedVerdict = await judgeScreenshot(
      closedShot,
      'The "Your profile" dialog with NO "How Telegram replies work" help panel visible anywhere -- it has been closed.',
    );
    notes.push(`help-panel-closed judge: ${closedVerdict.pass ? 'PASS' : 'FAIL'} — ${closedVerdict.notes}`);

    status = closedVerdict.pass ? 'pass' : 'fail';
    details = notes.join(' | ');
  } catch (err) {
    status = 'fail';
    details = `Exception: ${(err as Error).message}. Notes so far: ${notes.join(' | ')}`;
  } finally {
    // Best-effort cleanup: don't leave a stale link code on the test host
    // row (harmless either way -- 10min TTL -- but tidy).
    try { await clearLinkCode(token, userId); } catch {}
    await browser.close();
  }

  return finishWith();

  function finishWith(): ScenarioResult {
    const duration_ms = Date.now() - start;
    console.log(`[${id}] ${status.toUpperCase()} (${duration_ms}ms)`);
    return { id, name, layer: 2, status, duration_ms, details, artifacts };
  }
}
