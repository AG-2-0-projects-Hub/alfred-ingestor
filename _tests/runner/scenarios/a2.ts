import { chromium } from 'playwright';
import { writeFile, mkdir } from 'node:fs/promises';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { env, stagingUrlWithBypass } from '../lib/env.ts';
import { judgeScreenshot } from '../lib/gemini-judge.ts';
import type { ScenarioResult } from '../run.ts';

const __dirname = dirname(fileURLToPath(import.meta.url));
const reportsDir = resolve(__dirname, '../../reports');

// A2 — auth-login-01
// Layer 2: opens staging frontend, logs in with test credentials, asks Gemini
// to confirm the dashboard renders post-login.

export async function runA2(): Promise<ScenarioResult> {
  const start = Date.now();
  const id = 'auth-login-01';
  const name = 'A2: Host login with valid credentials';
  console.log(`[${id}] starting...`);

  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await context.newPage();

  const notes: string[] = [];
  let status: 'pass' | 'fail' = 'fail';
  let details = '';
  const artifacts: ScenarioResult['artifacts'] = {};

  try {
    // 1. Open staging URL with Vercel bypass (if configured) and let Flutter hydrate.
    //    The bypass query params drop a cookie on first response so subsequent
    //    navigations in this browser context flow through transparently.
    const url = stagingUrlWithBypass();
    await page.goto(url, { waitUntil: 'networkidle', timeout: 60_000 });
    await page.waitForTimeout(6_000); // Flutter web hydration can be slow
    notes.push(`opened staging${env.vercelBypassToken ? ' (with Vercel bypass)' : ''}`);

    // Save raw auth screenshot for debugging (regardless of pass/fail)
    await mkdir(reportsDir, { recursive: true });
    const debugPath = resolve(reportsDir, `a2-debug-auth-${Date.now()}.png`);
    await page.screenshot({ path: debugPath, fullPage: true });
    notes.push(`auth screenshot: ${debugPath}`);

    // 2. Flutter web uses a "single roving input" pattern: only one real HTML
    //    <input> exists at a time, positioned over whichever Flutter TextField
    //    has focus. Position-based selectors don't work. Instead:
    //      a) click the visible label/field to focus
    //      b) type via the keyboard (Playwright sends keystrokes to whatever
    //         element has focus, which is the roving input)
    //      c) Tab to advance to the next Flutter field, repeat
    notes.push('using Flutter focus+type strategy (roving input)');

    // 3. Flutter exposes semantic markup (<flt-semantics> with ARIA roles).
    //    First we need to enable Flutter's accessibility — it ships dormant
    //    until something requests it. The standard trigger is to query the
    //    /flutter_service_worker.js or wait for a11y nodes. Playwright's
    //    getByRole queries usually wake the a11y tree on its own.
    //
    //    Strategy: use getByRole to find the email + password textboxes by
    //    accessible name, then click+type. If that fails (no semantic tree),
    //    fall back to Tab-focus then type.

    // Coordinate-based clicking. Flutter CanvasKit doesn't expose form fields
    // via the DOM in any way Playwright can reliably target, so we click at
    // visual coordinates measured from the auth screenshot (1440x900 viewport).
    // The right-half wide layout positions fields consistently across deploys.
    const vp = page.viewportSize();
    if (!vp) {
      details = `No viewport size — cannot compute click coords. ${notes.join(' | ')}`;
      return finishWith();
    }

    // Field centers as fractions of viewport (measured from the auth screenshot
    // at 1440x900). Form sits in right column ~75% across; fields are clustered
    // around the vertical center of the right pane.
    const emailX = vp.width * 0.75;
    const emailY = vp.height * 0.46;      // ~415/900 — email field center
    const passwordY = vp.height * 0.515;  // ~465/900 — password field center
    const signInY = vp.height * 0.60;     // ~540/900 — Sign In button center

    // 3. Click email field, type
    await page.mouse.click(emailX, emailY);
    await page.waitForTimeout(400);
    await page.keyboard.type(env.testHostEmail, { delay: 30 });
    notes.push(`clicked email at (${emailX|0},${emailY|0}) + typed`);

    // 4. Click password field, type
    await page.mouse.click(emailX, passwordY);
    await page.waitForTimeout(400);
    await page.keyboard.type(env.testHostPassword, { delay: 30 });
    notes.push(`clicked password at (${emailX|0},${passwordY|0}) + typed`);

    // 5. Click Sign In button
    await page.mouse.click(emailX, signInY);
    notes.push(`clicked Sign In at (${emailX|0},${signInY|0})`);

    // 5. Wait for navigation / dashboard hydration
    await page.waitForTimeout(6_000);

    // 6. Capture full-page screenshot, save to disk for debugging, then judge
    const postLogin = await page.screenshot({ fullPage: true });
    const postLoginPath = resolve(reportsDir, `a2-debug-postlogin-${Date.now()}.png`);
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
