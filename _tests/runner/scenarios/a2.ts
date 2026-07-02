import { chromium } from 'playwright';
import { writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { env } from '../lib/env.ts';
import { judgeScreenshot } from '../lib/gemini-judge.ts';
import { hydratePage, loginAs, saveScreenshot, REPORTS_DIR, VP, AUTH } from '../lib/playwright-helpers.ts';
import type { ScenarioResult } from '../run.ts';

// A2 — auth-login-01
// Layer 2: opens staging frontend, logs in with test credentials, asks Gemini
// to confirm the dashboard renders post-login.

export async function runA2(): Promise<ScenarioResult> {
  const start = Date.now();
  const id = 'auth-login-01';
  const name = 'A2: Host login with valid credentials';
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
    notes.push(`opened staging${env.vercelBypassToken ? ' (with Vercel bypass)' : ''}`);

    const debugPath = await saveScreenshot(page, 'a2-debug-auth');
    notes.push(`auth screenshot: ${debugPath}`);

    await loginAs(page);
    notes.push('login submitted via shared loginAs helper');

    const postLogin = await page.screenshot({ fullPage: true });
    const postLoginPath = resolve(REPORTS_DIR, `a2-debug-postlogin-${Date.now()}.png`);
    await writeFile(postLoginPath, postLogin);
    notes.push(`post-login screenshot: ${postLoginPath}`);
    artifacts.postLoginScreenshot = postLogin.toString('base64');

    const verdict = await judgeScreenshot(
      postLogin,
      'A logged-in dashboard or home screen. Could show: property cards/tiles, an empty-state inviting the user to add a property, a top navigation bar, account-specific UI, or a sidebar. Should NOT show a login form with visible email and password input fields.',
    );
    artifacts.postLoginVerdict = verdict.raw;
    notes.push(`post-login judge: ${verdict.pass ? 'PASS' : 'FAIL'} — ${verdict.notes}`);

    status = verdict.pass ? 'pass' : 'fail';
    details = notes.join(' | ');
  } catch (err) {
    status = 'fail';
    details = `Exception: ${(err as Error).message}. Notes so far: ${notes.join(' | ')}`;
  } finally {
    await browser.close();
  }

  return finishWith();

  function finishWith(): ScenarioResult {
    const duration_ms = Date.now() - start;
    console.log(`[${id}] ${status.toUpperCase()} (${duration_ms}ms)`);
    return { id, name, layer: 2, status, duration_ms, details, artifacts };
  }
}
