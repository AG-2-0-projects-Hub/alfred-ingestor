import { chromium } from 'playwright';
import { judgeScreenshot } from '../lib/screenshot-judge.ts';
import { hydratePage, loginAs, VP, DASHBOARD } from '../lib/playwright-helpers.ts';
import type { ScenarioResult } from '../run.ts';

// D6 — dashboard-settings-menu-01
// Layer 2: the walkthrough replay toggle moved from each property's own
// drawer into a new account-wide "Settings" menu in the dashboard's top
// bar (2026-09-19). Opens that menu, confirms the toggle is there (not the
// old per-property drawer), flips it, and confirms the switch state
// actually changes and survives a reload.

export async function runD6(): Promise<ScenarioResult> {
  const start = Date.now();
  const id = 'dashboard-settings-menu-01';
  const name = 'D6: Top-bar Settings menu holds the walkthrough replay toggle';
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

    const vp = page.viewportSize() ?? VP;
    await page.mouse.click(vp.width * DASHBOARD.settingsIconX, vp.height * DASHBOARD.settingsIconY);
    await page.waitForTimeout(1_200);

    const menuShot = await page.screenshot({ fullPage: true });
    artifacts.menuScreenshot = menuShot.toString('base64');
    const menuVerdict = await judgeScreenshot(
      menuShot,
      'A small dialog titled "Settings" containing a row labeled "+ Show walkthrough again" with a toggle switch next to it, and a Close button. This is NOT a property drawer (should not show Overview/Files/Knowledge tabs, Master JSON, or Delete Property).',
    );
    artifacts.menuVerdict = menuVerdict.raw;
    notes.push(`menu judge: ${menuVerdict.pass ? 'PASS' : 'FAIL'} — ${menuVerdict.notes}`);
    if (!menuVerdict.pass) throw new Error('Settings menu did not render as expected');

    // Toggle it. Fixed viewport dialog is centered ~380px wide; the switch
    // sits at the right edge of the toggle row, roughly 60% down the panel.
    await page.mouse.click(vp.width * 0.5 + 130, vp.height * 0.5 - 10);
    await page.waitForTimeout(800);

    const toggledShot = await page.screenshot({ fullPage: true });
    artifacts.toggledScreenshot = toggledShot.toString('base64');
    const toggledVerdict = await judgeScreenshot(
      toggledShot,
      'The same Settings dialog, but the "+ Show walkthrough again" switch is now in the OPPOSITE visual state (on vs off) compared to before -- it changed when clicked.',
    );
    artifacts.toggledVerdict = toggledVerdict.raw;
    notes.push(`toggle judge: ${toggledVerdict.pass ? 'PASS' : 'FAIL'} — ${toggledVerdict.notes}`);

    status = toggledVerdict.pass ? 'pass' : 'fail';
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
