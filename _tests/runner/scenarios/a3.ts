import { chromium } from 'playwright';
import { judgeScreenshot } from '../lib/gemini-judge.ts';
import { hydratePage, loginAs, VP, AUTH } from '../lib/playwright-helpers.ts';
import { env } from '../lib/env.ts';
import type { ScenarioResult } from '../run.ts';

// A3 — auth-login-02
// Layer 2: wrong password → auth screen stays visible, error indicator shown,
// no redirect to dashboard, no session established.

export async function runA3(): Promise<ScenarioResult> {
  const start = Date.now();
  const id = 'auth-login-02';
  const name = 'A3: Host login with invalid credentials';
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
    notes.push('opened staging auth page');

    const vp = page.viewportSize() ?? VP;
    const x = vp.width * AUTH.x;

    await page.mouse.click(x, vp.height * AUTH.emailY);
    await page.waitForTimeout(400);
    await page.keyboard.type(env.testHostEmail, { delay: 30 });

    await page.mouse.click(x, vp.height * AUTH.passwordY);
    await page.waitForTimeout(400);
    await page.keyboard.type('WRONG_PASSWORD_QA_TEST_123', { delay: 30 });

    await page.mouse.click(x, vp.height * AUTH.submitY);
    notes.push('submitted wrong password');
    await page.waitForTimeout(4_000);

    const screenshot = await page.screenshot({ fullPage: true });
    artifacts.screenshot = screenshot.toString('base64');

    const verdict = await judgeScreenshot(
      screenshot,
      'An auth or login screen that is still visible — NOT a dashboard. ' +
      'The page may show an error message, a red snackbar, or a shake animation ' +
      'indicating wrong credentials. Must NOT show property cards, a dashboard ' +
      'header, or any post-login content.',
    );
    artifacts.verdict = verdict.raw;
    notes.push(`judge: ${verdict.pass ? 'PASS' : 'FAIL'} — ${verdict.notes}`);
    status = verdict.pass ? 'pass' : 'fail';
    details = notes.join(' | ');
  } catch (err) {
    status = 'fail';
    details = `Exception: ${(err as Error).message}. Notes: ${notes.join(' | ')}`;
  } finally {
    await browser.close();
  }

  const duration_ms = Date.now() - start;
  console.log(`[${id}] ${status.toUpperCase()} (${duration_ms}ms)`);
  return { id, name, layer: 2, status, duration_ms, details, artifacts };
}
