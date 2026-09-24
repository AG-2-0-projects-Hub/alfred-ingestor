import { chromium } from 'playwright';
import { env } from '../lib/env.ts';
import { judgeScreenshot } from '../lib/screenshot-judge.ts';
import { hydratePage, loginAs, VP } from '../lib/playwright-helpers.ts';
import type { ScenarioResult } from '../run.ts';

// Q1 — welcome-modal-first-login-01
// Layer 2: the first-login "Welcome to Alfred" onboarding modal
// (welcome_walkthrough_dialog.dart, 2026-09-24). Never actually built before
// despite guide.html claiming it existed — see migrations/
// 2026-09-24_welcome_modal_seen.sql and the plan this shipped from.
//
// Uses the shared test host account rather than a new signup (no service-role
// key available to pre-confirm a throwaway account, and staging's
// confirmation-email delivery is a known separate gap — QUEUE.md). Safe
// because the "empty dashboard" state is produced via the same reversible
// soft-delete (`deleted_at`) the app's own Delete-property flow already uses
// (see D9's own softDelete/getProperty pattern) — properties are restored in
// the finally block regardless of outcome, and this suite runs scenarios
// sequentially (run.ts), so there's no concurrent-access window.

async function getAccessToken(): Promise<string> {
  const res = await fetch(`${env.supabaseUrl}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: { apikey: env.supabaseAnonKey, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: env.testHostEmail, password: env.testHostPassword }),
  });
  const json = await res.json();
  if (!res.ok) throw new Error(`auth failed: ${JSON.stringify(json)}`);
  return json.access_token as string;
}

async function getUserId(token: string): Promise<string> {
  const res = await fetch(`${env.supabaseUrl}/auth/v1/user`, {
    headers: { apikey: env.supabaseAnonKey, Authorization: `Bearer ${token}` },
  });
  const json = await res.json();
  if (!res.ok) throw new Error(`auth/v1/user failed: ${JSON.stringify(json)}`);
  return json.id as string;
}

async function getActivePropertyIds(token: string): Promise<string[]> {
  const res = await fetch(`${env.supabaseUrl}/rest/v1/properties?select=id&deleted_at=is.null`, {
    headers: { apikey: env.supabaseAnonKey, Authorization: `Bearer ${token}` },
  });
  const rows = await res.json();
  return (rows as Array<{ id: string }>).map((r) => r.id);
}

async function setDeletedAt(token: string, ids: string[], value: string | null): Promise<void> {
  if (ids.length === 0) return;
  const idList = ids.join(',');
  const res = await fetch(`${env.supabaseUrl}/rest/v1/properties?id=in.(${idList})`, {
    method: 'PATCH',
    headers: {
      apikey: env.supabaseAnonKey,
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
      Prefer: 'return=minimal',
    },
    body: JSON.stringify({ deleted_at: value }),
  });
  if (!res.ok) throw new Error(`setDeletedAt failed: ${res.status} ${await res.text()}`);
}

async function setWelcomeModalSeen(token: string, userId: string, seen: boolean): Promise<void> {
  const res = await fetch(`${env.supabaseUrl}/rest/v1/host_profiles?id=eq.${userId}`, {
    method: 'PATCH',
    headers: {
      apikey: env.supabaseAnonKey,
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
      Prefer: 'return=minimal',
    },
    body: JSON.stringify({ welcome_modal_seen: seen }),
  });
  if (!res.ok) throw new Error(`setWelcomeModalSeen failed: ${res.status} ${await res.text()}`);
}

async function getWelcomeModalSeen(token: string, userId: string): Promise<boolean | null> {
  const res = await fetch(
    `${env.supabaseUrl}/rest/v1/host_profiles?id=eq.${userId}&select=welcome_modal_seen`,
    { headers: { apikey: env.supabaseAnonKey, Authorization: `Bearer ${token}` } },
  );
  const rows = await res.json();
  return (rows as Array<{ welcome_modal_seen: boolean }>)[0]?.welcome_modal_seen ?? null;
}

export async function runQ1(): Promise<ScenarioResult> {
  const start = Date.now();
  const id = 'welcome-modal-first-login-01';
  const name = 'Q1: First-login "Welcome to Alfred" modal shows once, dismisses, persists';
  console.log(`[${id}] starting...`);

  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ viewport: VP });
  const page = await context.newPage();

  const notes: string[] = [];
  let status: 'pass' | 'fail' = 'fail';
  let details = '';
  const artifacts: ScenarioResult['artifacts'] = {};

  const token = await getAccessToken();
  const userId = await getUserId(token);
  let savedIds: string[] = [];

  try {
    savedIds = await getActivePropertyIds(token);
    notes.push(`saved ${savedIds.length} active property id(s) for restore`);
    await setDeletedAt(token, savedIds, new Date().toISOString());
    await setWelcomeModalSeen(token, userId, false);
    notes.push('test host set to zero-properties + welcome_modal_seen=false');

    await hydratePage(page);
    await loginAs(page);
    await page.waitForTimeout(2000);

    const modalShot = await page.screenshot({ fullPage: true });
    artifacts.modalScreenshot = modalShot.toString('base64');
    const modalVerdict = await judgeScreenshot(
      modalShot,
      'A modal titled "Welcome to Alfred" with 5 numbered/iconed steps (Add a property, Upload '
      + 'what Alfred should know, Train Alfred, Share a guest link, Test it yourself), a full-width '
      + '"ADD YOUR FIRST PROPERTY" button, and a "Maybe later" link below it.',
    );
    notes.push(`modal judge: ${modalVerdict.pass ? 'PASS' : 'FAIL'} — ${modalVerdict.notes}`);
    if (!modalVerdict.pass) throw new Error('Welcome modal did not render as expected');

    // "Maybe later" -- centered text button below the primary button. Measured
    // live against a real screenshot this session.
    const vp = page.viewportSize() ?? VP;
    await page.mouse.click(vp.width * 0.5, vp.height * 0.806);
    await page.waitForTimeout(2000);

    const dismissedShot = await page.screenshot({ fullPage: true });
    artifacts.dismissedScreenshot = dismissedShot.toString('base64');
    const dismissedVerdict = await judgeScreenshot(
      dismissedShot,
      'The dashboard background is fully visible and NOT dimmed/greyed-out by any overlay. There '
      + 'is NO popup card floating in front of the page, NO numbered list of 5 steps, and NO '
      + 'all-caps "ADD YOUR FIRST PROPERTY" button or "Maybe later" link anywhere. (A plain, '
      + 'undimmed page that happens to also say "Welcome to Alfred" in its normal background '
      + 'content, with a title-case "Add Your First Property" button, is CORRECT and should PASS '
      + '-- only a popup card in front of a dimmed backdrop counts as the modal still showing.)',
    );
    notes.push(`dismissed judge: ${dismissedVerdict.pass ? 'PASS' : 'FAIL'} — ${dismissedVerdict.notes}`);

    // Reload -- must NOT reappear (permanently dismissed, per founder decision).
    await hydratePage(page);
    await page.waitForTimeout(2000);
    const afterReloadShot = await page.screenshot({ fullPage: true });
    artifacts.afterReloadScreenshot = afterReloadShot.toString('base64');
    const afterReloadVerdict = await judgeScreenshot(
      afterReloadShot,
      'The dashboard background is fully visible and NOT dimmed/greyed-out by any overlay. There '
      + 'is NO popup card floating in front of the page, NO numbered list of 5 steps, and NO '
      + 'all-caps "ADD YOUR FIRST PROPERTY" button or "Maybe later" link anywhere. (A plain, '
      + 'undimmed page that happens to also say "Welcome to Alfred" in its normal background '
      + 'content, with a title-case "Add Your First Property" button, is CORRECT and should PASS '
      + '-- only a popup card in front of a dimmed backdrop counts as the modal reappearing.)',
    );
    notes.push(`no-reappear judge: ${afterReloadVerdict.pass ? 'PASS' : 'FAIL'} — ${afterReloadVerdict.notes}`);

    const seenNow = await getWelcomeModalSeen(token, userId);
    const dbOk = seenNow === true;
    notes.push(`db check: welcome_modal_seen=${seenNow} — ${dbOk ? 'PASS' : 'FAIL'}`);

    status = modalVerdict.pass && dismissedVerdict.pass && afterReloadVerdict.pass && dbOk
      ? 'pass' : 'fail';
    details = notes.join(' | ');
  } catch (err) {
    status = 'fail';
    details = `Exception: ${(err as Error).message}. Notes so far: ${notes.join(' | ')}`;
  } finally {
    // Best-effort restore regardless of how far the scenario got -- never
    // leave the shared test host's real fixture properties soft-deleted.
    try { await setDeletedAt(token, savedIds, null); } catch {}
    try { await setWelcomeModalSeen(token, userId, false); } catch {}
    await browser.close();
  }

  return finishWith();

  function finishWith(): ScenarioResult {
    const duration_ms = Date.now() - start;
    console.log(`[${id}] ${status.toUpperCase()} (${duration_ms}ms)`);
    return { id, name, layer: 2, status, duration_ms, details, artifacts };
  }
}
