import { chromium } from 'playwright';
import { judgeScreenshot } from '../lib/screenshot-judge.ts';
import { hydratePage, loginAs, VP, CARD1 } from '../lib/playwright-helpers.ts';
import type { ScenarioResult } from '../run.ts';

// D7 — dashboard-card-ready-01
// Layer 2: on a Ready property card (2026-09-19 changes) --
//   1. the second action button reads "Details" with a magnifying-glass
//      icon, not "Settings" with a gear
//   2. its status pill (top-right of the photo) is a solid, legible color,
//      not the washed-out translucent badge from before
//   3. tapping the card body still opens the conversations/New Guest Link
//      popup normally, since a Ready property is exactly when that should
//      work

export async function runD7(): Promise<ScenarioResult> {
  const start = Date.now();
  const id = 'dashboard-card-ready-01';
  const name = 'D7: Ready card shows Details + an opaque status pill, and still opens on tap';
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

    const cardShot = await page.screenshot({ fullPage: true });
    artifacts.cardScreenshot = cardShot.toString('base64');
    const cardVerdict = await judgeScreenshot(
      cardShot,
      'A property card whose second action button (next to "+ Guest") reads "Details" with a magnifying-glass icon -- NOT "Settings" with a gear icon. The status badge in the top-right corner of the card photo (likely reading "Ready") must be a solid, opaque, clearly-readable colored pill, not a faint, washed-out, or barely-visible one.',
    );
    artifacts.cardVerdict = cardVerdict.raw;
    notes.push(`card judge: ${cardVerdict.pass ? 'PASS' : 'FAIL'} — ${cardVerdict.notes}`);
    if (!cardVerdict.pass) throw new Error('Card did not show the expected Details button / opaque pill');

    const vp = page.viewportSize() ?? VP;
    await page.mouse.click(vp.width * CARD1.bodyX, vp.height * CARD1.bodyY);
    await page.waitForTimeout(1_000);

    const popupShot = await page.screenshot({ fullPage: true });
    artifacts.popupScreenshot = popupShot.toString('base64');
    const popupVerdict = await judgeScreenshot(
      popupShot,
      'A popup/dialog showing the property name, a "Conversations" section, and a "New Guest Link" button -- opened after tapping a Ready property card.',
    );
    artifacts.popupVerdict = popupVerdict.raw;
    notes.push(`popup judge: ${popupVerdict.pass ? 'PASS' : 'FAIL'} — ${popupVerdict.notes}`);

    status = popupVerdict.pass ? 'pass' : 'fail';
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
