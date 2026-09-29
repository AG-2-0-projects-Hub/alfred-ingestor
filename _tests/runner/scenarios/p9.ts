import { chromium } from 'playwright';
import { env } from '../lib/env.ts';
import { judgeScreenshot } from '../lib/screenshot-judge.ts';
import { hydratePage, loginAs, VP, DASHBOARD } from '../lib/playwright-helpers.ts';
import type { ScenarioResult } from '../run.ts';

// P9 — host-esc-email-01
// Layer 2: the "Email alerts" section in the profile dialog (host-escalation
// email fallback, 2026-09-29) -- a beta-tester incident (host never linked
// Telegram, so an escalated guest got no response for days) with no
// fallback channel. This proves the Profile dialog UI end-to-end: typing an
// email, checking the opt-in box, saving, and that the write actually went
// through the new backend endpoint (POST /api/host/escalation-email) rather
// than the profile's plain RLS-direct upsert -- asserted via
// escalation_email_unsub_token being non-null, since only that endpoint ever
// mints one. Does not attempt to prove a real email arrives (no
// RESEND_API_KEY configured on staging yet); that's a separate, later check
// once the founder has a Resend account.

const TEST_EMAIL = 'sans.lighthouse@gmail.com';

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

async function getEscalationEmailSettings(token: string, userId: string) {
  const res = await fetch(
    `${env.supabaseUrl}/rest/v1/host_profiles?id=eq.${userId}` +
      `&select=notification_email,escalation_email_enabled,escalation_email_unsub_token`,
    { headers: { apikey: env.supabaseAnonKey, Authorization: `Bearer ${token}` } },
  );
  const rows = await res.json();
  return rows[0] ?? {};
}

async function resetEscalationEmail(token: string, userId: string): Promise<void> {
  await fetch(`${env.supabaseUrl}/rest/v1/host_profiles?id=eq.${userId}`, {
    method: 'PATCH',
    headers: {
      apikey: env.supabaseAnonKey,
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
      Prefer: 'return=minimal',
    },
    body: JSON.stringify({
      notification_email: null,
      escalation_email_enabled: false,
      escalation_email_unsub_token: null,
    }),
  });
}

export async function runP9(): Promise<ScenarioResult> {
  const start = Date.now();
  const id = 'host-esc-email-01';
  const name = 'P9: Email-alerts opt-in UI (Profile dialog) + backend write proof';
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
    await resetEscalationEmail(token, userId);
    notes.push('test host reset to no email-escalation config');

    await hydratePage(page);
    await loginAs(page);
    notes.push('logged in');

    const vp = page.viewportSize() ?? VP;
    const profileX = DASHBOARD.settingsIconX - 0.036;
    const profileY = DASHBOARD.settingsIconY;
    await page.mouse.click(vp.width * profileX, vp.height * profileY);
    await page.waitForTimeout(1200);

    const emptyShot = await page.screenshot({ fullPage: true });
    artifacts.emptyShot = emptyShot.toString('base64');
    const emptyVerdict = await judgeScreenshot(
      emptyShot,
      'A "Your profile" dialog with an "Email alerts" section: an empty email text field with placeholder text about escalation alerts, an UNCHECKED checkbox labeled "Send escalation notifications via Email", and small text mentioning an unsubscribe link.',
    );
    notes.push(`empty-state judge: ${emptyVerdict.pass ? 'PASS' : 'FAIL'} — ${emptyVerdict.notes}`);
    if (!emptyVerdict.pass) throw new Error('Email alerts section did not render as expected');

    // Email TextField -- directly below the "Email alerts" label.
    await page.mouse.click(vp.width * 0.5, vp.height * 0.736);
    await page.waitForTimeout(300);
    await page.keyboard.type(TEST_EMAIL, { delay: 20 });
    await page.waitForTimeout(300);

    // Checkbox -- "Send escalation notifications via Email".
    await page.mouse.click(vp.width * 0.375, vp.height * 0.782);
    await page.waitForTimeout(500);

    const filledShot = await page.screenshot({ fullPage: true });
    artifacts.filledShot = filledShot.toString('base64');
    const filledVerdict = await judgeScreenshot(
      filledShot,
      `An "Email alerts" section with the email text field containing "${TEST_EMAIL}" and a CHECKED checkbox labeled "Send escalation notifications via Email".`,
    );
    notes.push(`filled-state judge: ${filledVerdict.pass ? 'PASS' : 'FAIL'} — ${filledVerdict.notes}`);
    if (!filledVerdict.pass) throw new Error('Email field/checkbox did not reflect input as expected');

    // Save -- bottom-right filled button.
    await page.mouse.click(vp.width * 0.613, vp.height * 0.929);
    await page.waitForTimeout(2000);

    // Direct DB check -- the real proof point. notification_email/enabled
    // could in principle be set by a plain RLS-direct upsert like the other
    // profile fields, but escalation_email_unsub_token can ONLY be minted by
    // the new POST /api/host/escalation-email endpoint (never written by the
    // frontend directly) -- so a non-null token proves that endpoint really
    // ran, not just that some write happened.
    const settingsAfter = await getEscalationEmailSettings(token, userId);
    const emailMatches = settingsAfter.notification_email === TEST_EMAIL;
    const enabledTrue = settingsAfter.escalation_email_enabled === true;
    const tokenMinted = typeof settingsAfter.escalation_email_unsub_token === 'string'
      && settingsAfter.escalation_email_unsub_token.length > 0;
    notes.push(
      `db check: email ${emailMatches ? 'matches (PASS)' : `mismatch "${settingsAfter.notification_email}" (FAIL)`}, ` +
      `enabled ${enabledTrue ? 'true (PASS)' : 'false (FAIL)'}, ` +
      `unsub_token ${tokenMinted ? 'minted (PASS -- proves backend endpoint ran)' : 'MISSING (FAIL)'}`,
    );

    status = emailMatches && enabledTrue && tokenMinted ? 'pass' : 'fail';
    details = notes.join(' | ');
  } catch (err) {
    status = 'fail';
    details = `Exception: ${(err as Error).message}. Notes so far: ${notes.join(' | ')}`;
  } finally {
    // Best-effort cleanup: leave the test host's email-escalation fields
    // cleared regardless of where the scenario failed (same pattern as
    // P1/P8), so a stale config doesn't leak into other scenarios/sessions
    // or falsely surface as a new WF-style item in a future feedback run.
    try { await resetEscalationEmail(token, userId); } catch {}
    await browser.close();
  }

  return finishWith();

  function finishWith(): ScenarioResult {
    const duration_ms = Date.now() - start;
    console.log(`[${id}] ${status.toUpperCase()} (${duration_ms}ms)`);
    return { id, name, layer: 2, status, duration_ms, details, artifacts };
  }
}
