import { chromium } from 'playwright';
import { env } from '../lib/env.ts';
import { judgeScreenshot } from '../lib/screenshot-judge.ts';
import { hydratePage, loginAs, VP, DASHBOARD } from '../lib/playwright-helpers.ts';
import type { ScenarioResult } from '../run.ts';

// P8 — tgh-disconnect-01
// Layer 2: the "Disconnect Telegram" UI in the profile dialog (2026-09-25).
// Forces the test host into a connected state via a direct REST PATCH (same
// technique P1 uses for cleanup), then drives the real UI: Disconnect link ->
// confirm dialog -> confirm -> reverts to "Connect Telegram". Also verifies
// the DB write directly via REST, not just the screenshot judge, since a
// silently-failed write with an optimistic UI flip would otherwise pass a
// visual-only check.

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

async function setTelegramConnected(token: string, userId: string): Promise<void> {
  await fetch(`${env.supabaseUrl}/rest/v1/host_profiles?id=eq.${userId}`, {
    method: 'PATCH',
    headers: {
      apikey: env.supabaseAnonKey,
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
      Prefer: 'return=minimal',
    },
    body: JSON.stringify({ telegram_chat_id: '999999999', active_conversation_booking_id: null }),
  });
}

async function getTelegramChatId(token: string, userId: string): Promise<string | null> {
  const res = await fetch(
    `${env.supabaseUrl}/rest/v1/host_profiles?id=eq.${userId}&select=telegram_chat_id`,
    { headers: { apikey: env.supabaseAnonKey, Authorization: `Bearer ${token}` } },
  );
  const rows = await res.json();
  return rows[0]?.telegram_chat_id ?? null;
}

async function resetTelegram(token: string, userId: string): Promise<void> {
  await fetch(`${env.supabaseUrl}/rest/v1/host_profiles?id=eq.${userId}`, {
    method: 'PATCH',
    headers: {
      apikey: env.supabaseAnonKey,
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
      Prefer: 'return=minimal',
    },
    body: JSON.stringify({ telegram_chat_id: null, active_conversation_booking_id: null }),
  });
}

export async function runP8(): Promise<ScenarioResult> {
  const start = Date.now();
  const id = 'tgh-disconnect-01';
  const name = 'P8: Disconnect-Telegram UI (confirm dialog + state revert)';
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

  try {
    await setTelegramConnected(token, userId);
    notes.push('test host forced into connected state');

    await hydratePage(page);
    await loginAs(page);
    notes.push('logged in');

    const vp = page.viewportSize() ?? VP;
    const profileX = DASHBOARD.settingsIconX - 0.036;
    const profileY = DASHBOARD.settingsIconY;
    await page.mouse.click(vp.width * profileX, vp.height * profileY);
    await page.waitForTimeout(1200);

    const connectedShot = await page.screenshot({ fullPage: true });
    artifacts.connectedScreenshot = connectedShot.toString('base64');
    const connectedVerdict = await judgeScreenshot(
      connectedShot,
      'A "Telegram alerts" section showing "Telegram connected" (green checkmark) with a red "Disconnect" text link visible below it.',
    );
    notes.push(`connected-state judge: ${connectedVerdict.pass ? 'PASS' : 'FAIL'} — ${connectedVerdict.notes}`);
    if (!connectedVerdict.pass) throw new Error('Connected state with Disconnect link did not render as expected');

    // "Disconnect" text link, directly below the connected-state row.
    await page.mouse.click(vp.width * 0.386, vp.height * 0.724);
    await page.waitForTimeout(700);

    const confirmShot = await page.screenshot({ fullPage: true });
    artifacts.confirmScreenshot = confirmShot.toString('base64');
    const confirmVerdict = await judgeScreenshot(
      confirmShot,
      'A confirmation dialog titled "Disconnect Telegram?" with body text about stopping guest alerts, and Cancel / Disconnect buttons.',
    );
    notes.push(`confirm-dialog judge: ${confirmVerdict.pass ? 'PASS' : 'FAIL'} — ${confirmVerdict.notes}`);
    if (!confirmVerdict.pass) throw new Error('Disconnect confirmation dialog did not render as expected');

    // Confirm dialog's "Disconnect" button (filled, bottom-right of the dialog).
    await page.mouse.click(vp.width * 0.613, vp.height * 0.546);
    await page.waitForTimeout(1500);

    const revertedShot = await page.screenshot({ fullPage: true });
    artifacts.revertedScreenshot = revertedShot.toString('base64');
    const revertedVerdict = await judgeScreenshot(
      revertedShot,
      'The "Telegram alerts" section showing a "Connect Telegram" button, with NO "Telegram connected" text and NO "Disconnect" link visible anywhere.',
    );
    notes.push(`reverted-state judge: ${revertedVerdict.pass ? 'PASS' : 'FAIL'} — ${revertedVerdict.notes}`);

    // Direct DB check -- catches a silently-failed write an optimistic UI
    // flip would otherwise hide from a visual-only check.
    const chatIdAfter = await getTelegramChatId(token, userId);
    const dbCleared = chatIdAfter === null;
    notes.push(`db check: telegram_chat_id ${dbCleared ? 'is null (PASS)' : `still "${chatIdAfter}" (FAIL)`}`);

    status = revertedVerdict.pass && dbCleared ? 'pass' : 'fail';
    details = notes.join(' | ');
  } catch (err) {
    status = 'fail';
    details = `Exception: ${(err as Error).message}. Notes so far: ${notes.join(' | ')}`;
  } finally {
    // Best-effort cleanup: leave the test host's Telegram fields cleared
    // regardless of where the scenario failed, so a false "connected" state
    // doesn't leak into other scenarios or sessions.
    try { await resetTelegram(token, userId); } catch {}
    await browser.close();
  }

  return finishWith();

  function finishWith(): ScenarioResult {
    const duration_ms = Date.now() - start;
    console.log(`[${id}] ${status.toUpperCase()} (${duration_ms}ms)`);
    return { id, name, layer: 2, status, duration_ms, details, artifacts };
  }
}
