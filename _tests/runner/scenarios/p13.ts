import { chromium, type Browser, type Page } from 'playwright';
import { env, stagingUrlWithBypass } from '../lib/env.ts';
import { judgeScreenshot } from '../lib/screenshot-judge.ts';
import { hydratePage, loginAs, saveScreenshot, VP, CARD1 } from '../lib/playwright-helpers.ts';
import type { ScenarioResult } from '../run.ts';

// P13 — guest-stay-dates-ui-01
// Layer 2 (Playwright UI + REST ground truth). Item C UI (2026-11-12): the host types the stay in
//   1. the New Guest Link dialog: check-in/out DATES (empty at first, typed YYYY-MM-DD) + TIMES (pre-filled
//      from the listing, editable); no time zone field (it is the listing's); "Add later" makes a link
//      without dates; a check-out before check-in shows an error and keeps Generate off; the very first
//      link's walkthrough opens with the dates filled so its tip ("hit Generate Link") still works
//   2. the live-chat screen's "Stay" block (the alert link /chat-live) and the dashboard's live-chat
//      dialog: summary, "dates not set" with Set dates -> editor -> Save, and "Stay ended"
// Ground truth is the guests row read back over REST (exact UTC instants, zone, provisional end), not the
// pixels. Needs a backend that has the stay-defaults / stay endpoints (local or deployed staging).

const PROP = 'aebab5c1-4cf4-4e1d-a3d1-f7c4bc11ff2f'; // QA host's trained property (Mexico City, 14:00 / 11:00)
const API = env.stagingBackend.replace(/\/$/, '');
const MX_OFFSET_H = 6; // Mexico City is UTC-6 all year since 2022

// Coordinates measured on a real 1440x900 screenshot (2026-11-12).
// The popup's rows shift with the number of conversations, so the dialog is opened with the card's
// "+ Guest" button instead; the first conversation row's y is computed from the active-chat count
// (measured: 1 chat -> 440, each extra row moves it up 30).
const firstRowY = (activeChats: number) => 440 - 30 * (activeChats - 1);
const DLG = {
  name: { x: 720, y: 396 },
  inDate: { x: 650, y: 452 }, inTime: { x: 835, y: 452 },
  outDate: { x: 650, y: 504 }, outTime: { x: 835, y: 504 },
  addLater: { x: 574, y: 556 }, generate: { x: 833, y: 556 },
};
const PANEL = { // the 320 px "Stay" block on the alert-link screen (provisional + editing)
  setDates: { x: 1194, y: 306 },
  inDate: { x: 1220, y: 290 }, outDate: { x: 1220, y: 340 },
  save: { x: 1360, y: 387 },
};

const localDay = (offset: number) => {
  const d = new Date(Date.now() + offset * 86_400_000);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
};
const mxInstant = (date: string, hhmm: string) => Date.parse(`${date}T${hhmm}:00Z`) + MX_OFFSET_H * 3_600_000;
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

export async function runP13(): Promise<ScenarioResult> {
  const start = Date.now();
  const id = 'guest-stay-dates-ui-01';
  const name = 'P13: New Guest Link takes dates + times (listing zone); Stay block in the live chat';
  console.log(`[${id}] starting...`);

  const notes: string[] = [];
  const artifacts: ScenarioResult['artifacts'] = {};
  const need = (label: string, ok: boolean, extra = '') => {
    notes.push(`${label}: ${ok ? 'PASS' : 'FAIL'}${extra ? ` (${extra})` : ''}`);
    if (!ok) throw new Error(`${label} failed${extra ? ` (${extra})` : ''}`);
  };

  const auth = await fetch(`${env.supabaseUrl}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: { apikey: env.supabaseAnonKey, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: env.testHostEmail, password: env.testHostPassword }),
  });
  if (!auth.ok) throw new Error(`QA host sign-in failed: ${auth.status}`);
  const token = ((await auth.json()) as any).access_token as string;
  const H = { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };
  const rest = (path: string) =>
    fetch(`${env.supabaseUrl}/rest/v1/${path}`, { headers: { apikey: env.supabaseAnonKey, Authorization: `Bearer ${token}` } })
      .then((r) => r.json() as Promise<any[]>);
  const post = (path: string, body: unknown) => fetch(`${API}${path}`, { method: 'POST', headers: H, body: JSON.stringify(body) });
  // Only guests created by THIS run (earlier runs / other scenarios may use the same names).
  const since = encodeURIComponent(new Date(start - 5_000).toISOString());
  const guestNamed = async (n: string, wantStayChange = false) => {
    for (let i = 0; i < 12; i++) {
      const row = (await rest(`guests?name=eq.${encodeURIComponent(n)}&created_at=gte.${since}&order=created_at.desc&limit=1&select=booking_id,check_in,check_out,stay_timezone`))[0];
      // after an edit the row already exists: wait until a zone is stored (provisional rows have none)
      if (row && (!wantStayChange || row.stay_timezone)) return row;
      await sleep(1500);
    }
    return undefined;
  };

  const cleanup: string[] = [];
  const browser: Browser = await chromium.launch({ headless: true });
  let status: 'pass' | 'fail' = 'fail';
  let details = '';

  const openDialog = async (walkthroughSeen: boolean): Promise<Page> => {
    const ctx = await browser.newContext({ viewport: VP });
    if (walkthroughSeen) await ctx.addInitScript(() => localStorage.setItem('flutter.guest_link_walkthrough_seen', 'true'));
    const page = await ctx.newPage();
    await hydratePage(page);
    await loginAs(page);
    await page.mouse.click(VP.width * CARD1.guestX, VP.height * CARD1.actionsY); // "+ Guest"
    await page.waitForTimeout(2_500);
    return page;
  };
  const type = async (page: Page, at: { x: number; y: number }, text: string) => {
    await page.mouse.click(at.x, at.y);
    await page.waitForTimeout(250);
    await page.keyboard.press('Control+A');
    await page.keyboard.type(text, { delay: 25 });
    await page.waitForTimeout(250);
  };
  const judge = async (page: Page, label: string, expected: string) => {
    const shot = await page.screenshot({ fullPage: true });
    artifacts[label] = shot.toString('base64');
    const v = await judgeScreenshot(shot, expected);
    notes.push(`${label}: ${v.pass ? 'PASS' : 'FAIL'} — ${v.notes}`);
    if (!v.pass) {
      notes.push(`screenshot: ${await saveScreenshot(page, `p13-${label}`)}`);
      throw new Error(`${label} judge failed: ${v.notes}`);
    }
  };

  try {
    // Sweep: archive stray conversations of earlier (failed) runs, so the popup/dialog layout is stable.
    for (const g of await rest(`guests?property_id=eq.${PROP}&or=(name.eq.Test walkthrough,name.like.QA-P13-*)&select=booking_id`)) {
      await post('/api/conversations/resolve', { booking_id: g.booking_id });
      const cid = (await rest(`conversations?booking_id=eq.${g.booking_id}&select=id`))[0]?.id;
      if (cid) await post('/api/conversations/archive', { conversation_id: cid });
    }

    // ── A. The very first link (walkthrough): dates pre-filled, Generate works ──
    let page = await openDialog(false);
    await judge(page, 'walkthrough-dialog',
      'A "New Guest Link" dialog with a Guest name field containing "Test walkthrough", then "Check-in" and "Check-out" rows that each have a date filled in (like 2026-11-12) and a Time field (14:00 and 11:00), a faded "Add later" button, and a highlighted purple "Generate Link" button. A small tip panel on the right says "Generate a guest link".');
    await page.mouse.click(DLG.generate.x, DLG.generate.y);
    const wt = await guestNamed('Test walkthrough');
    need('walkthrough guest created', !!wt);
    cleanup.push(wt!.booking_id);
    need('walkthrough stay = today..+2, 14:00 / 11:00 listing times, listing zone',
      new Date(wt!.check_in).getTime() === mxInstant(localDay(0), '14:00')
      && new Date(wt!.check_out).getTime() === mxInstant(localDay(2), '11:00')
      && wt!.stay_timezone === 'America/Mexico_City', `${wt!.check_in} / ${wt!.check_out} / ${wt!.stay_timezone}`);
    await page.context().close();

    // ── B. Typed dates + a customised time, with the error state ──
    page = await openDialog(true);
    await judge(page, 'empty-dialog',
      'A "New Guest Link" dialog with an empty Guest name field, EMPTY "Check-in" and "Check-out" date fields (just those words as placeholders, each with a small calendar icon), two Time fields showing 14:00 and 11:00 with clock icons, a "Add later" link-style button on the left, a "Cancel" button and a GREYED-OUT / disabled-looking "Generate Link" button. There is NO time zone field.');
    await page.mouse.move(DLG.inTime.x, DLG.inTime.y);
    await page.waitForTimeout(1_200);
    await judge(page, 'time-tooltip', 'A small dark tooltip bubble near the check-in Time field that mentions times coming from the listing.');
    await type(page, DLG.name, 'QA-P13-dates');
    await type(page, DLG.inDate, localDay(10));
    await type(page, DLG.outDate, localDay(8)); // before check-in
    await judge(page, 'order-error',
      'A "New Guest Link" dialog with a RED error line reading "Check-out is before check-in." under the date rows, and a greyed-out / disabled "Generate Link" button.');
    await type(page, DLG.outDate, localDay(12));
    await type(page, DLG.outTime, '15:30');
    await judge(page, 'valid-dialog',
      'A "New Guest Link" dialog with Guest name "QA-P13-dates", both a Check-in and a Check-out date filled in, a Time next to each, NO red error text anywhere, and an enabled (solid purple) "Generate Link" button.');
    await page.mouse.click(DLG.generate.x, DLG.generate.y);
    const typed = await guestNamed('QA-P13-dates');
    need('typed guest created', !!typed);
    cleanup.push(typed!.booking_id);
    need('typed stay stored exactly (day+10 14:00 -> day+12 15:30, listing zone)',
      new Date(typed!.check_in).getTime() === mxInstant(localDay(10), '14:00')
      && new Date(typed!.check_out).getTime() === mxInstant(localDay(12), '15:30')
      && typed!.stay_timezone === 'America/Mexico_City', `${typed!.check_in} / ${typed!.check_out}`);
    await page.context().close();

    // ── C. "Add later" ──
    page = await openDialog(true);
    await type(page, DLG.name, 'QA-P13-later');
    await page.mouse.click(DLG.addLater.x, DLG.addLater.y);
    const later = await guestNamed('QA-P13-later');
    need('add-later guest created', !!later);
    cleanup.push(later!.booking_id);
    const days = (new Date(later!.check_out).getTime() - Date.now()) / 86_400_000;
    need('add-later = provisional (no zone, ends ~7 d out)', later!.stay_timezone === null && days > 6.9 && days < 7.1, `${days.toFixed(2)} d, tz ${later!.stay_timezone}`);
    await page.context().close();

    // ── D. Live-chat screen (alert link): "dates not set" -> Set dates -> Save ──
    const ctx = await browser.newContext({ viewport: VP });
    await ctx.addInitScript(() => localStorage.setItem('flutter.guest_link_walkthrough_seen', 'true'));
    page = await ctx.newPage();
    await hydratePage(page);
    await loginAs(page);
    const live = async (b: string) => {
      await page.goto(stagingUrlWithBypass(`/chat-live?booking=${b}&property=${PROP}`), { waitUntil: 'networkidle', timeout: 60_000 });
      await page.waitForTimeout(6_000);
    };
    await live(later!.booking_id);
    await judge(page, 'panel-not-set',
      'The right-hand panel of a live chat screen has an AMBER/yellow box titled "Stay — dates not set" with a line "Chat closes <date>" and a purple "Set dates" button.');
    await page.mouse.click(PANEL.setDates.x, PANEL.setDates.y);
    await page.waitForTimeout(2_000);
    await type(page, PANEL.inDate, localDay(20));
    await type(page, PANEL.outDate, localDay(22));
    await judge(page, 'panel-editing',
      'The right-hand panel has a "Stay" box with Check-in and Check-out date fields filled in, Time fields (14:00 and 11:00), and "Cancel" and "Save dates" buttons, the Save button enabled (purple).');
    await page.mouse.click(PANEL.save.x, PANEL.save.y);
    await page.waitForTimeout(3_000);
    const saved = await guestNamed('QA-P13-later', true);
    need('panel save stored (day+20 14:00 -> day+22 11:00, listing zone)',
      new Date(saved!.check_in).getTime() === mxInstant(localDay(20), '14:00')
      && new Date(saved!.check_out).getTime() === mxInstant(localDay(22), '11:00')
      && saved!.stay_timezone === 'America/Mexico_City', `${saved!.check_in} / ${saved!.check_out} / ${saved!.stay_timezone}`);
    await judge(page, 'panel-set',
      'The right-hand panel has a neutral (not yellow, not red) "Stay" box with an "Edit" link, a line of two dates joined by an arrow like "12 Dec 14:00 → 14 Dec 11:00", and a smaller line starting "Chat closes".');

    // ── F. The dashboard's live-chat dialog shows the same block ──
    await page.goto(stagingUrlWithBypass(''), { waitUntil: 'networkidle', timeout: 60_000 });
    await page.waitForTimeout(6_000);
    await page.mouse.click(VP.width * CARD1.bodyX, VP.height * CARD1.bodyY);
    await page.waitForTimeout(1_500);
    const active = (await rest(`conversations?property_id=eq.${PROP}&archived_at=is.null&select=id`)).length;
    await page.mouse.click(720, firstRowY(active));
    await page.waitForTimeout(3_500);
    await judge(page, 'dialog-panel',
      'A large live-chat dialog with the conversation on the left and a right-hand panel containing "Guest Chat Link" and, below it, a box titled "Stay" (any state: yellow, grey or red).');

    // ── E. Stay ended: the host sees it ──
    const past = await post(`/api/guests/${later!.booking_id}/stay`, {
      check_in_date: localDay(-6), check_out_date: localDay(-4), stay_timezone: 'America/Mexico_City', check_in_time: '14:00', check_out_time: '11:00',
    });
    need('move the stay into the past (API)', past.ok, String(past.status));
    await live(later!.booking_id);
    await judge(page, 'panel-ended',
      'The right-hand panel has a RED/pink box titled "Stay ended" with an "Edit" link, two dates joined by an arrow, and a line starting "Chat closed".');
    await page.context().close();

    status = 'pass';
    details = notes.join(' | ');
  } catch (err) {
    details = `Exception: ${(err as Error).message}. Notes so far: ${notes.join(' | ')}`;
  } finally {
    await browser.close();
    for (const b of cleanup) {
      try {
        await post('/api/conversations/resolve', { booking_id: b });
        const cid = (await rest(`conversations?booking_id=eq.${b}&select=id`))[0]?.id;
        if (cid) await post('/api/conversations/archive', { conversation_id: cid });
      } catch { /* best effort */ }
    }
  }

  const duration_ms = Date.now() - start;
  console.log(`[${id}] ${status.toUpperCase()} (${duration_ms}ms)`);
  return { id, name, layer: 2, status, duration_ms, details, artifacts };
}

// Allow running this scenario on its own: STAGING_FRONTEND_URL=http://localhost:3000 npx tsx scenarios/p13.ts
if (import.meta.url === `file://${process.argv[1]}`) {
  runP13().then((r) => {
    console.log(r.details.split(' | ').join('\n'));
    process.exit(r.status === 'pass' ? 0 : 1);
  });
}
