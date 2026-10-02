import { chromium } from 'playwright';
import { judgeScreenshot } from '../lib/screenshot-judge.ts';
import { hydratePage, loginAs, openAddPropertyFromDashboard, VP, ADD_PROPERTY } from '../lib/playwright-helpers.ts';
import { supabaseAnon, createAuthedClient } from '../lib/supabase.ts';
import { env } from '../lib/env.ts';
import type { ScenarioResult } from '../run.ts';

// B6 — ingest-invalid-url-01
// Layer 2: a non-Airbnb URL cannot start training. The Add Property screen
// keeps Train Now disabled until the URL contains "airbnb." (rewritten
// 2026-10-01 -- this scenario used to expect a server-side error after the
// click, from before the client-side guard existed).
//
// Navigation path: Dashboard → "+ Add Property" tile → Add Property screen
//   → type URL → judge the button looks disabled → click it anyway.
//
// Assertions: zero POST /api/ingest requests, and no property row at all for
// the test URL. (A bogus URL that DOES contain "airbnb." goes through the
// scrape-failure path -- tracked under R3 in scenarios.md, not here.)

const INVALID_URL = 'https://example.com/not-an-airbnb-listing';
const QA_TEST_OWNER = '2bf084d9-8ab2-47aa-8788-2d0c7db876d7';

export async function runB6(): Promise<ScenarioResult> {
  const start = Date.now();
  const id = 'ingest-invalid-url-01';
  const name = 'B6: Non-Airbnb URL cannot start training (Train Now stays disabled)';
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

    // Navigate to Add Property (the "+ Add Property" tile after the last card)
    const vp = page.viewportSize() ?? VP;
    await openAddPropertyFromDashboard(page);
    notes.push('clicked the Add Property tile');
    await page.waitForTimeout(2_000);

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

    // The tips card makes the form taller than one viewport, so scroll the
    // button into view first -- same as D8/D9.
    await page.mouse.wheel(0, 1400);
    await page.waitForTimeout(400);

    // The Add Property screen guards the URL client-side: Train Now stays
    // disabled until the text contains "airbnb." (add_property_screen.dart
    // `canIngest`, added so a typo no longer runs the multi-minute flow and
    // dies with a generic scrape error). Click it anyway -- a disabled button
    // must do nothing: no dispatch, no property row.
    let ingestDispatches = 0;
    page.on('request', (req) => {
      if (req.url().includes('/api/ingest') && req.method() === 'POST') ingestDispatches++;
    });
    const errorSS = await page.screenshot({ fullPage: true });
    artifacts.errorScreenshot = errorSS.toString('base64');
    const errorVerdict = await judgeScreenshot(
      errorSS,
      'The Add Property screen with a TRAIN NOW button that is greyed out / disabled ' +
      '(flat grey, low contrast, not the vivid purple of an enabled primary button). ' +
      'It must NOT be on a dashboard and must NOT show a success state.',
    );
    artifacts.errorVerdict = errorVerdict.raw;
    notes.push(`disabled-button judge: ${errorVerdict.pass ? 'PASS' : 'FAIL'} — ${errorVerdict.notes}`);

    await page.mouse.click(vp.width * ADD_PROPERTY.x, vp.height * 0.863);
    notes.push('clicked the disabled TRAIN NOW anyway');
    await page.waitForTimeout(4_000);
    notes.push(`/api/ingest dispatches after the click: ${ingestDispatches}`);
    artifacts.ingestDispatches = ingestDispatches;

    // DB assertion: no property row with this URL exists at all (any status).
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
      .eq('airbnb_url', INVALID_URL);

    const orphanCount = orphans?.length ?? 0;
    notes.push(`property rows created for the invalid URL: ${orphanCount}`);
    artifacts.orphanCount = orphanCount;

    // Clean up any rows that slipped through
    await authed
      .from('properties')
      .delete()
      .eq('airbnb_url', INVALID_URL);
    notes.push('cleaned up any test rows');

    status = errorVerdict.pass && ingestDispatches === 0 && orphanCount === 0 ? 'pass' : 'fail';
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
