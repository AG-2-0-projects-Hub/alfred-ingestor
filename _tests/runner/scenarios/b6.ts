import { chromium } from 'playwright';
import { judgeScreenshot } from '../lib/gemini-judge.ts';
import { hydratePage, loginAs, VP, DASHBOARD, ADD_PROPERTY } from '../lib/playwright-helpers.ts';
import { supabaseAnon, createAuthedClient } from '../lib/supabase.ts';
import { env } from '../lib/env.ts';
import type { ScenarioResult } from '../run.ts';

// B6 — ingest-invalid-url-01
// Layer 2: pasting a non-Airbnb URL and clicking INGEST NOW shows an error
// message and leaves no orphaned property in a non-terminal state.
//
// Navigation path (qa-test account has no properties → empty-state screen):
//   Dashboard empty-state "Add Your First Property" → Add Property screen
//   → type URL → click INGEST NOW → wait for backend error → judge screenshot.
//
// DB assertion: after the run, no property rows belonging to qa-test are in
// Pending / Ingesting / Ingest_Error state with the test URL.

const INVALID_URL = 'https://example.com/not-an-airbnb-listing';
const QA_TEST_OWNER = '2bf084d9-8ab2-47aa-8788-2d0c7db876d7';

export async function runB6(): Promise<ScenarioResult> {
  const start = Date.now();
  const id = 'ingest-invalid-url-01';
  const name = 'B6: Invalid Airbnb URL returns graceful error';
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

    // Navigate to Add Property (empty-state centred button)
    const vp = page.viewportSize() ?? VP;
    await page.mouse.click(vp.width * DASHBOARD.addPropertyX, vp.height * DASHBOARD.addPropertyY);
    notes.push('clicked Add Your First Property');
    await page.waitForTimeout(4_000);

    const navSS = await page.screenshot({ fullPage: true });
    const navVerdict = await judgeScreenshot(
      navSS,
      'An "Add Property" or property setup screen with an Airbnb URL input field ' +
      'and a file drop zone. Must NOT show the main dashboard.',
    );
    artifacts.navVerdict = navVerdict.raw;
    notes.push(`nav judge: ${navVerdict.pass ? 'PASS' : 'FAIL'} — ${navVerdict.notes}`);

    if (!navVerdict.pass) {
      details = `Did not navigate to Add Property screen. ${notes.join(' | ')}`;
      return finish();
    }

    // Type invalid URL into the Airbnb URL field
    await page.mouse.click(vp.width * ADD_PROPERTY.x, vp.height * ADD_PROPERTY.urlY);
    await page.waitForTimeout(400);
    await page.keyboard.type(INVALID_URL, { delay: 20 });
    notes.push('typed invalid URL');

    // Click INGEST NOW
    await page.mouse.click(vp.width * ADD_PROPERTY.x, vp.height * ADD_PROPERTY.ingestY);
    notes.push('clicked INGEST NOW');

    // Wait for the backend to respond with an error (scraper will reject non-Airbnb URL).
    // The SSE stream errors fast for invalid URLs — 30s is generous.
    await page.waitForTimeout(30_000);

    const errorSS = await page.screenshot({ fullPage: true });
    artifacts.errorScreenshot = errorSS.toString('base64');
    const errorVerdict = await judgeScreenshot(
      errorSS,
      'The Add Property screen still visible, showing an error message, red text, ' +
      'or an error snackbar/banner indicating that the ingest failed or the URL is ' +
      'invalid. Must NOT show a success state or a dashboard with a new property.',
    );
    artifacts.errorVerdict = errorVerdict.raw;
    notes.push(`error judge: ${errorVerdict.pass ? 'PASS' : 'FAIL'} — ${errorVerdict.notes}`);

    // DB assertion: no orphan row with this URL in a non-terminal state.
    // Uses an authenticated client scoped to the qa-test account so that RLS
    // on the properties table only returns rows owned by that account.
    const { data: authData } = await supabaseAnon.auth.signInWithPassword({
      email: env.testHostEmail,
      password: env.testHostPassword,
    });
    const authed = createAuthedClient(authData?.session?.access_token ?? '');

    const { data: orphans } = await authed
      .from('properties')
      .select('id, status')
      .eq('airbnb_url', INVALID_URL)
      .in('status', ['Pending', 'Ingesting']);

    const orphanCount = orphans?.length ?? 0;
    notes.push(`orphan rows in non-terminal state: ${orphanCount}`);
    artifacts.orphanCount = orphanCount;

    // Clean up any rows the ingest may have left (e.g. Ingest_Error)
    await authed
      .from('properties')
      .delete()
      .eq('airbnb_url', INVALID_URL);
    notes.push('cleaned up any test rows');

    status = errorVerdict.pass && orphanCount === 0 ? 'pass' : 'fail';
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
