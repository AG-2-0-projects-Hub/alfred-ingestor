import { chromium } from 'playwright';
import { mkdirSync, writeFileSync } from 'node:fs';
import { env } from '../lib/env.ts';
import { judgeScreenshot } from '../lib/screenshot-judge.ts';
import { hydratePage, loginAs, VP, DASHBOARD } from '../lib/playwright-helpers.ts';
import type { ScenarioResult } from '../run.ts';

// P9 — host-esc-email-01
// Layer 2: the "Email alerts" section of the Profile dialog, rebuilt 2026-10-02 as a
// DOUBLE OPT-IN that mirrors the Telegram row: type an address -> "Send escalation
// alerts via email" -> the address is stored as PENDING and a confirmation link is
// e-mailed -> the section shows "Waiting for confirmation" (+ Resend / Cancel) -> the
// address's owner opens the link and presses Confirm -> the dialog flips live to
// "Email connected" -> Disconnect clears it. Also checks the "How to use" panel
// carries the spam tip.
//
// Ground truth is the DB and the network (the requests' responses), not the vision
// judge — the judge only confirms what the host would SEE. The test plays the
// mailbox owner with an @example.invalid address (can never receive mail): for
// those, the backend returns the confirm link in the response, which this scenario
// captures off the wire and opens in a second tab exactly like a real inbox click.
// The backend-only rules (hash, expiry, single-use, scanner-safe GET, direct-write
// lock, address switching) are covered by P10; this one proves the UI end-to-end.

const ADDRESS = `qa-ui-${Date.now()}@example.invalid`;
const SHOTS = process.env.P9_SHOTS_DIR; // debug only: also write screenshots to disk

async function signIn(): Promise<{ token: string; uid: string }> {
  const res = await fetch(`${env.supabaseUrl}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: { apikey: env.supabaseAnonKey, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: env.testHostEmail, password: env.testHostPassword }),
  });
  const json = (await res.json()) as any;
  if (!res.ok) throw new Error(`auth failed: ${JSON.stringify(json)}`);
  return { token: json.access_token, uid: json.user.id };
}

async function getSettings(token: string, uid: string) {
  const res = await fetch(
    `${env.supabaseUrl}/rest/v1/host_profiles?id=eq.${uid}` +
      `&select=notification_email,escalation_email_enabled,escalation_email_unsub_token,escalation_email_confirm_expires_at`,
    { headers: { apikey: env.supabaseAnonKey, Authorization: `Bearer ${token}` } },
  );
  return ((await res.json()) as any[])[0] ?? {};
}

// The alert columns can only be changed through the backend (a DB trigger ignores
// the host's own direct writes), so reset goes through the same endpoint the UI uses.
async function resetEscalationEmail(token: string): Promise<void> {
  await fetch(`${env.stagingBackend.replace(/\/$/, '')}/api/host/escalation-email`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ email: '', enabled: false }),
  });
}

export async function runP9(): Promise<ScenarioResult> {
  const start = Date.now();
  const id = 'host-esc-email-01';
  const name = 'P9: Email alerts double opt-in (Profile dialog UI: request, resend, cancel, confirm, connected, disconnect)';
  console.log(`[${id}] starting...`);

  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ viewport: VP });
  const page = await context.newPage();

  const notes: string[] = [];
  let status: 'pass' | 'fail' = 'fail';
  let details = '';
  const artifacts: ScenarioResult['artifacts'] = {};
  const { token, uid } = await signIn();

  const vp = page.viewportSize() ?? VP;
  const at = (p: readonly [number, number]) => page.mouse.click(vp.width * p[0], vp.height * p[1]);
  const shot = async (label: string) => {
    const png = await page.screenshot({ fullPage: true });
    artifacts[label] = png.toString('base64');
    if (SHOTS) {
      mkdirSync(SHOTS, { recursive: true });
      writeFileSync(`${SHOTS}/${label}.png`, png);
    }
    return png;
  };
  const judge = async (label: string, expectation: string) => {
    const verdict = await judgeScreenshot(await shot(label), expectation);
    notes.push(`${label} judge: ${verdict.pass ? 'PASS' : 'FAIL'} — ${verdict.notes}`);
    if (!verdict.pass) throw new Error(`${label}: screen did not match — ${verdict.notes}`);
  };
  const need = (label: string, ok: boolean) => {
    notes.push(`${label}: ${ok ? 'PASS' : 'FAIL'}`);
    if (!ok) throw new Error(`${label} failed`);
  };
  const escalationPost = () =>
    page.waitForResponse(
      (r) => r.url().includes('/api/host/escalation-email') && r.request().method() === 'POST',
      { timeout: 30_000 },
    );

  // Fractions of the 1440x900 viewport, measured on real screenshots of the dialog.
  // The dialog is vertically centred, so its pending/connected state (shorter) sits
  // a little differently from the empty one — hence separate sets.
  const FIELD = [0.5, 0.736] as const; // empty state
  const SEND_BUTTON = [0.5, 0.787] as const; // empty state
  const RESEND = [0.378, 0.778] as const; // pending state
  const CANCEL = [0.421, 0.778] as const; // pending state
  const EMAIL_HOW_TO = [0.614, 0.708] as const; // connected state
  const DISCONNECT = [0.386, 0.778] as const; // connected state

  try {
    await resetEscalationEmail(token);
    notes.push('test host reset to no email-alert config (via the backend)');

    await hydratePage(page);
    await loginAs(page);
    await at([DASHBOARD.settingsIconX - 0.036, DASHBOARD.settingsIconY]); // Profile
    await page.waitForTimeout(1500);

    await judge(
      'empty',
      'A "Your profile" dialog with an "Email alerts" section that has a "How to use" link, an empty email text field, and a button labeled "Send escalation alerts via email" with an envelope icon. There is NO checkbox in that section. The "Telegram alerts" section above it has a "Connect Telegram" button.',
    );

    // Request: type the address, press the button, capture the response off the wire.
    let respPromise = escalationPost();
    await at(FIELD);
    await page.waitForTimeout(300);
    await page.keyboard.type(ADDRESS, { delay: 20 });
    await page.waitForTimeout(300);
    await at(SEND_BUTTON);
    let resp = await respPromise;
    let body = (await resp.json()) as { status?: string; confirm_url?: string };
    need('request answered 200 "pending"', resp.status() === 200 && body.status === 'pending');
    need('confirm link returned for the test address', !!body.confirm_url);
    await page.waitForTimeout(1500);

    const pending = await getSettings(token, uid);
    need(
      'DB: pending, NOT enabled, no alert token yet',
      pending.notification_email === ADDRESS && pending.escalation_email_enabled === false &&
        !!pending.escalation_email_confirm_expires_at && pending.escalation_email_unsub_token == null,
    );
    await judge(
      'pending',
      `The "Email alerts" section says it is waiting for confirmation and mentions the address "${ADDRESS}" (and that the email may land in spam). It shows "Resend" and "Cancel" links. The email text field and the "Send escalation alerts via email" button are gone.`,
    );

    // Resend straight away: the 60 s cooldown answers 429 and changes nothing.
    respPromise = escalationPost();
    await at(RESEND);
    need('immediate Resend -> 429 (cooldown)', (await respPromise).status() === 429);
    need('Resend left the request pending', (await getSettings(token, uid)).escalation_email_confirm_expires_at != null);

    // Cancel clears the request and brings the field back.
    respPromise = escalationPost();
    await at(CANCEL);
    await respPromise;
    await page.waitForTimeout(1500);
    const cancelled = await getSettings(token, uid);
    need(
      'DB: Cancel cleared address and pending state',
      cancelled.notification_email == null && cancelled.escalation_email_enabled === false &&
        cancelled.escalation_email_confirm_expires_at == null,
    );
    await judge(
      'cancelled',
      `The "Email alerts" section shows an email text field (it may still hold the address "${ADDRESS}" so a typo can be corrected) and a button labeled "Send escalation alerts via email". A short red message at the bottom of the screen may be visible.`,
    );

    // Ask again (the field still holds the address) and keep the NEW link.
    respPromise = escalationPost();
    await at(SEND_BUTTON);
    resp = await respPromise;
    body = (await resp.json()) as { status?: string; confirm_url?: string };
    need('second request answered 200 "pending" with a fresh link', resp.status() === 200 && body.status === 'pending' && !!body.confirm_url);
    await page.waitForTimeout(1500);

    // The address's owner opens the link (a second tab = their inbox click).
    const owner = await context.newPage();
    await owner.goto(body.confirm_url!);
    const ownerText = await owner.innerText('body');
    need('link opens a page with a Confirm button naming the address', ownerText.includes('Yes, send me alerts') && ownerText.includes(ADDRESS));
    need('opening the link did NOT confirm', (await getSettings(token, uid)).escalation_email_enabled === false);
    await owner.click('button');
    await owner.waitForLoadState();
    need('pressing Confirm shows "Done"', (await owner.innerText('body')).includes('Done'));
    await owner.close();

    // The dialog notices on its own (it polls every 3 s).
    await page.waitForTimeout(6000);
    const connected = await getSettings(token, uid);
    need(
      'DB: connected (enabled, alert token minted, pending cleared)',
      connected.escalation_email_enabled === true && !!connected.escalation_email_unsub_token &&
        connected.escalation_email_confirm_expires_at == null,
    );
    await judge(
      'connected',
      `The "Email alerts" section shows a green check and text saying email is connected and an alert will arrive at "${ADDRESS}" when a guest needs the host, plus a "Disconnect" link. No email text field.`,
    );

    // "How to use" carries the spam tip.
    await at(EMAIL_HOW_TO);
    await page.waitForTimeout(800);
    await judge(
      'help',
      'A docked help panel titled "How email alerts work" is open beside the profile dialog. Its text tells the host that the confirmation email may land in Spam and to mark it "Not spam".',
    );
    await at(EMAIL_HOW_TO); // close the panel
    await page.waitForTimeout(500);

    // Disconnect clears everything.
    await at(DISCONNECT);
    await page.waitForTimeout(2500);
    const cleared = await getSettings(token, uid);
    need(
      'DB: Disconnect cleared address, flag, token and pending state',
      cleared.notification_email == null && cleared.escalation_email_enabled === false &&
        cleared.escalation_email_unsub_token == null && cleared.escalation_email_confirm_expires_at == null,
    );
    await judge(
      'disconnected',
      `The "Email alerts" section shows an email text field (it may still hold the address "${ADDRESS}" so reconnecting is one tap) and a button labeled "Send escalation alerts via email". There is no green "Email connected" text.`,
    );

    status = 'pass';
    details = notes.join(' | ');
  } catch (err) {
    status = 'fail';
    details = `Exception: ${(err as Error).message}. Notes so far: ${notes.join(' | ')}`;
    try { await shot('failure'); } catch { /* page may be gone */ }
  } finally {
    // Leave the test host with no email-alert config whatever happened.
    try { await resetEscalationEmail(token); } catch { /* best effort */ }
    await browser.close();
  }

  const duration_ms = Date.now() - start;
  console.log(`[${id}] ${status.toUpperCase()} (${duration_ms}ms)`);
  return { id, name, layer: 2, status, duration_ms, details, artifacts };
}

// Allow running this scenario on its own: npx tsx scenarios/p9.ts
if (import.meta.url === `file://${process.argv[1]}`) {
  runP9().then((r) => {
    console.log(r.details.split(' | ').join('\n'));
    process.exit(r.status === 'pass' ? 0 : 1);
  });
}
