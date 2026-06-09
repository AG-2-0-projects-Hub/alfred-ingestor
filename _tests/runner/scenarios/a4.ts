import { chromium } from 'playwright';
import { judgeScreenshot } from '../lib/gemini-judge.ts';
import { hydratePage, loginAs, VP, DASHBOARD } from '../lib/playwright-helpers.ts';
import type { ScenarioResult } from '../run.ts';

// A4 — auth-logout-01
// Layer 2: after logout the user lands on the auth screen and a hard refresh
// does not restore the session.
//
// Logout button: TextButton.icon("Logout") in AppBar trailing section.
// Wide viewport (1440px) → text button visible, not the icon-only variant.
// Coordinate: top-right area of AppBar (~93% across, ~3.5% from top).

export async function runA4(): Promise<ScenarioResult> {
  const start = Date.now();
  const id = 'auth-logout-01';
  const name = 'A4: Host logout clears session';
  console.log(`[${id}] starting...`);

  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ viewport: VP });
  const page = await context.newPage();
  const notes: string[] = [];
  let status: 'pass' | 'fail' = 'fail';
  let details = '';
  const artifacts: ScenarioResult['artifacts'] = {};

  try {
    await hydratePage(page);
    await loginAs(page);
    notes.push('logged in');

    // Take a quick pre-logout screenshot to confirm we really were on the dashboard
    const preSS = await page.screenshot({ fullPage: true });
    const preVerdict = await judgeScreenshot(
      preSS,
      'A logged-in dashboard showing property cards or an empty-state prompt to add a property. Must NOT show a login form.',
    );
    artifacts.preLogoutVerdict = preVerdict.raw;
    notes.push(`pre-logout judge: ${preVerdict.pass ? 'PASS' : 'FAIL'} — ${preVerdict.notes}`);

    if (!preVerdict.pass) {
      details = `Login did not reach dashboard — cannot test logout. ${notes.join(' | ')}`;
      return finish();
    }

    // Click the Logout button (top-right AppBar, TextButton.icon)
    const vp = page.viewportSize() ?? VP;
    await page.mouse.click(vp.width * DASHBOARD.logoutX, vp.height * DASHBOARD.logoutY);
    notes.push('clicked logout');
    await page.waitForTimeout(3_000);

    // Assert 1: auth screen is now visible
    const postLogoutSS = await page.screenshot({ fullPage: true });
    artifacts.postLogoutScreenshot = postLogoutSS.toString('base64');
    const postVerdict = await judgeScreenshot(
      postLogoutSS,
      'An auth or login screen with email and password fields. Must NOT show a ' +
      'dashboard, property cards, or any authenticated content.',
    );
    artifacts.postLogoutVerdict = postVerdict.raw;
    notes.push(`post-logout judge: ${postVerdict.pass ? 'PASS' : 'FAIL'} — ${postVerdict.notes}`);

    if (!postVerdict.pass) {
      details = `Logout did not navigate to auth screen. ${notes.join(' | ')}`;
      return finish();
    }

    // Assert 2: hard refresh does not restore session
    await page.reload({ waitUntil: 'networkidle' });
    await page.waitForTimeout(5_000);
    const refreshSS = await page.screenshot({ fullPage: true });
    artifacts.refreshScreenshot = refreshSS.toString('base64');
    const refreshVerdict = await judgeScreenshot(
      refreshSS,
      'An auth or login screen — same as before. Must NOT show the dashboard or ' +
      'any post-login content, confirming the session was cleared.',
    );
    artifacts.refreshVerdict = refreshVerdict.raw;
    notes.push(`post-refresh judge: ${refreshVerdict.pass ? 'PASS' : 'FAIL'} — ${refreshVerdict.notes}`);

    status = refreshVerdict.pass ? 'pass' : 'fail';
    details = notes.join(' | ');
  } catch (err) {
    status = 'fail';
    details = `Exception: ${(err as Error).message}. Notes: ${notes.join(' | ')}`;
  } finally {
    await browser.close();
  }

  return finish();

  function finish(): ScenarioResult {
    const duration_ms = Date.now() - start;
    console.log(`[${id}] ${status.toUpperCase()} (${duration_ms}ms)`);
    return { id, name, layer: 2, status, duration_ms, details, artifacts };
  }
}
