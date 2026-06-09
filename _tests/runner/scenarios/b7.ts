import { chromium } from 'playwright';
import { judgeScreenshot } from '../lib/gemini-judge.ts';
import { hydratePage, loginAs, VP, DASHBOARD, ADD_PROPERTY } from '../lib/playwright-helpers.ts';
import type { ScenarioResult } from '../run.ts';

// B7 — ingest-bad-file-01
// Layer 2: dropping an unsupported file type (.exe) on the DropZone widget
// shows an inline rejection message and does NOT add the file to the upload list.
//
// The DropZone (desktop_drop package) listens to native browser DnD events via
// Flutter's flt-glass-pane overlay. We simulate the drop using page.evaluate()
// to dispatch DragEvent + DataTransfer on that overlay element.
//
// If desktop_drop changes its event target this injection may need updating.
// Fallback: run manually (Layer 4) until a more reliable hook exists.

export async function runB7(): Promise<ScenarioResult> {
  const start = Date.now();
  const id = 'ingest-bad-file-01';
  const name = 'B7: Unsupported file dropped is rejected';
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

    // Navigate to Add Property
    const vp = page.viewportSize() ?? VP;
    await page.mouse.click(vp.width * DASHBOARD.addPropertyX, vp.height * DASHBOARD.addPropertyY);
    notes.push('clicked Add Your First Property');
    await page.waitForTimeout(4_000);

    const navSS = await page.screenshot({ fullPage: true });
    const navVerdict = await judgeScreenshot(
      navSS,
      'An "Add Property" screen with an Airbnb URL input and a file drop zone area.',
    );
    artifacts.navVerdict = navVerdict.raw;
    notes.push(`nav judge: ${navVerdict.pass ? 'PASS' : 'FAIL'} — ${navVerdict.notes}`);

    if (!navVerdict.pass) {
      details = `Did not navigate to Add Property screen. ${notes.join(' | ')}`;
      return finish();
    }

    // Simulate dropping malware.exe via browser-native DnD events.
    // desktop_drop registers its listener on flt-glass-pane (Flutter's pointer
    // capture overlay). We dispatch dragenter → dragover → drop at the
    // drop zone's approximate screen position.
    const dropX = vp.width * ADD_PROPERTY.x;
    const dropY = vp.height * ADD_PROPERTY.dropZoneY;

    const dropResult = await page.evaluate(
      ({ x, y }: { x: number; y: number }) => {
        try {
          const dt = new DataTransfer();
          dt.items.add(new File(['MZ malware'], 'malware.exe', { type: 'application/octet-stream' }));

          // desktop_drop in Flutter web attaches to flt-glass-pane or the canvas.
          // Try flt-glass-pane first, fall back to document.body.
          const target =
            (document.querySelector('flt-glass-pane') as HTMLElement) ??
            document.body;

          const opts = (type: string) => ({
            bubbles: true,
            cancelable: true,
            dataTransfer: dt,
            clientX: x,
            clientY: y,
          });

          target.dispatchEvent(new DragEvent('dragenter', opts('dragenter')));
          target.dispatchEvent(new DragEvent('dragover',  opts('dragover')));
          target.dispatchEvent(new DragEvent('drop',      opts('drop')));
          return 'dispatched';
        } catch (e) {
          return `error: ${(e as Error).message}`;
        }
      },
      { x: dropX, y: dropY },
    );
    notes.push(`drop simulation: ${dropResult}`);
    await page.waitForTimeout(2_000);

    const afterSS = await page.screenshot({ fullPage: true });
    artifacts.afterDropScreenshot = afterSS.toString('base64');

    const verdict = await judgeScreenshot(
      afterSS,
      'The Add Property screen showing an inline error or rejection message for ' +
      'an unsupported file type (e.g. ".exe — unsupported file type" or similar ' +
      'red/warning text near the drop zone). The file must NOT appear in any ' +
      '"Files to Ingest" list.',
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

  return finish();

  function finish(): ScenarioResult {
    const duration_ms = Date.now() - start;
    console.log(`[${id}] ${status.toUpperCase()} (${duration_ms}ms)`);
    return { id, name, layer: 2, status, duration_ms, details, artifacts };
  }
}
