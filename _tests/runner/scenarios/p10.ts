import { env } from '../lib/env.ts';
import type { ScenarioResult } from '../run.ts';

// P10 — host-esc-email-gate-01
// Layer 3 (backend, no browser): the email-escalation CONFIRMATION GATE
// (2026-10-02). Alerts may only ever go to an address whose owner confirmed it:
//   request -> pending (alerts still off) -> owner opens the link (a page with a
//   button; a prefetching mail scanner must not confirm) -> owner presses the
//   button -> connected. Also proves the DB trigger that stops a host's own
//   session from writing the alert-email columns directly (the bypass FIX_VERIFY
//   Step 0 reproduced), the one-time/garbage-token behavior, resend cooldown,
//   address switching, cancel and auth.
// Addresses on the reserved @example.invalid TLD never receive mail, and for
// those the backend returns the confirm link in the response — that is how this
// scenario plays the mailbox owner (see _TEST_ONLY_ADDRESS_SUFFIX in messages.py).
// NOT covered here (each verified by hand, see the commit's Verified line):
//   - the per-address cooldown across DIFFERENT hosts (needs a second host)
//   - the 48 h expiry (the host can't write the expiry column, by design)
//   - "confirmation email could not be sent -> 502 and nothing left pending":
//     SendGrid accepts every address the app's regex allows, so a failure can only
//     be forced with a deliberately broken key on a zero-traffic tagged revision.

const API = env.stagingBackend.replace(/\/$/, '');
const COLS =
  'notification_email,escalation_email_enabled,escalation_email_unsub_token,' +
  'escalation_email_confirm_hash,escalation_email_confirm_expires_at';

async function signIn(): Promise<{ token: string; uid: string }> {
  const res = await fetch(`${env.supabaseUrl}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: { apikey: env.supabaseAnonKey, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: env.testHostEmail, password: env.testHostPassword }),
  });
  const json = (await res.json()) as any;
  if (!res.ok) throw new Error(`auth failed: ${res.status}`);
  return { token: json.access_token, uid: json.user.id };
}

async function row(token: string, uid: string): Promise<Record<string, any>> {
  const res = await fetch(`${env.supabaseUrl}/rest/v1/host_profiles?id=eq.${uid}&select=${COLS}`, {
    headers: { apikey: env.supabaseAnonKey, Authorization: `Bearer ${token}` },
  });
  return ((await res.json()) as any[])[0] ?? {};
}

async function call(method: string, url: string, token: string | null, body?: unknown) {
  const headers: Record<string, string> = {};
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  if (token) headers.Authorization = `Bearer ${token}`;
  const res = await fetch(url, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  let json: any = null;
  try { json = JSON.parse(text); } catch { /* HTML page */ }
  return { status: res.status, text, json };
}

const request = (token: string | null, email: string, enabled = true) =>
  call('POST', `${API}/api/host/escalation-email`, token, { email, enabled });

export async function runP10(): Promise<ScenarioResult> {
  const start = Date.now();
  const id = 'host-esc-email-gate-01';
  const name = 'P10: Email-alert confirmation gate (backend) on deployed staging';
  console.log(`[${id}] starting...`);

  const failures: string[] = [];
  const notes: string[] = [];
  const check = (label: string, ok: boolean, extra = '') => {
    notes.push(`${ok ? 'PASS' : 'FAIL'} ${label}${extra ? ` (${extra})` : ''}`);
    if (!ok) failures.push(label);
  };

  let token = '';
  let uid = '';
  try {
    ({ token, uid } = await signIn());
    await request(token, '', false); // start clean
    const addrA = `qa-gate-a-${Date.now()}@example.invalid`;
    const addrB = `qa-gate-b-${Date.now()}@example.invalid`;

    // Auth
    check('no token -> 401', (await request(null, addrA)).status === 401);
    check('garbage token -> 401', (await request('garbage', addrA)).status === 401);

    // The DB trigger: a host's own session cannot write the alert columns directly.
    await fetch(`${env.supabaseUrl}/rest/v1/host_profiles?id=eq.${uid}`, {
      method: 'PATCH',
      headers: {
        apikey: env.supabaseAnonKey,
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        notification_email: addrA,
        escalation_email_enabled: true,
        escalation_email_unsub_token: 'direct-write',
      }),
    });
    let r = await row(token, uid);
    check(
      'direct REST write of email/enabled/token is ignored',
      r.notification_email == null && r.escalation_email_enabled === false && r.escalation_email_unsub_token == null,
    );

    // Validation
    check('invalid address -> 400', (await request(token, 'not-an-email')).status === 400);

    // Request -> pending, alerts still off
    const req1 = await request(token, addrA.toUpperCase());
    check('request -> 200 pending', req1.status === 200 && req1.json?.status === 'pending', `status ${req1.status}`);
    const confirmUrl: string = req1.json?.confirm_url ?? '';
    check('test address returns the confirm link', confirmUrl.includes('/api/host/escalation-email/confirm?token='));
    const rawToken = confirmUrl.split('token=')[1] ?? '';
    r = await row(token, uid);
    check('address stored lower-cased, still NOT enabled', r.notification_email === addrA && r.escalation_email_enabled === false);
    check('pending: expiry set, no alert token yet', !!r.escalation_email_confirm_expires_at && r.escalation_email_unsub_token == null);
    check(
      'only a hash of the token is stored (host can read the row)',
      typeof r.escalation_email_confirm_hash === 'string' && r.escalation_email_confirm_hash.length === 64 && r.escalation_email_confirm_hash !== rawToken,
    );

    // Resend spam
    check('immediate resend -> 429', (await request(token, addrA)).status === 429);

    // A mail scanner opening the link must not confirm
    const page = await call('GET', confirmUrl, null);
    check(
      'GET shows a Confirm button naming the address',
      page.status === 200 && page.text.includes('Yes, send me alerts') && page.text.includes(addrA),
    );
    r = await row(token, uid);
    check('GET did not confirm anything', r.escalation_email_enabled === false && !!r.escalation_email_confirm_expires_at);

    // Garbage tokens change nothing
    const bad = `${API}/api/host/escalation-email/confirm?token=garbage`;
    check('garbage GET -> 400', (await call('GET', bad, null)).status === 400);
    check('garbage POST -> 400', (await call('POST', bad, null)).status === 400);
    r = await row(token, uid);
    check('garbage POST changed nothing', r.escalation_email_enabled === false);

    // The owner presses the button
    const ok = await call('POST', confirmUrl, null);
    check('POST confirm -> 200 "Done"', ok.status === 200 && ok.text.includes('Done'));
    r = await row(token, uid);
    check(
      'connected: enabled, alert token minted, pending cleared',
      r.escalation_email_enabled === true && !!r.escalation_email_unsub_token &&
        r.escalation_email_confirm_hash == null && r.escalation_email_confirm_expires_at == null,
    );
    check('link is single-use (second POST -> 400)', (await call('POST', confirmUrl, null)).status === 400);
    check('requesting the same confirmed address is a no-op', (await request(token, addrA)).json?.status === 'connected');

    // Switching address cuts the old one off at once
    const sw = await request(token, addrB);
    r = await row(token, uid);
    check(
      'new address -> pending and the old one stops immediately',
      sw.status === 200 && r.notification_email === addrB && r.escalation_email_enabled === false && r.escalation_email_unsub_token == null,
    );

    // Cancel clears everything and kills the pending link
    const pendingUrl: string = sw.json?.confirm_url ?? '';
    check('cancel -> 200', (await request(token, '', false)).status === 200);
    r = await row(token, uid);
    check(
      'cancel cleared address, flag and pending state',
      r.notification_email == null && r.escalation_email_enabled === false &&
        r.escalation_email_confirm_hash == null && r.escalation_email_confirm_expires_at == null,
    );
    check('cancelled link is dead', (await call('GET', pendingUrl, null)).status === 400);

  } catch (err) {
    failures.push(`exception: ${(err as Error).message}`);
  } finally {
    try { if (token) await request(token, '', false); } catch { /* best effort */ }
  }

  const status: 'pass' | 'fail' = failures.length === 0 ? 'pass' : 'fail';
  const duration_ms = Date.now() - start;
  console.log(`[${id}] ${status.toUpperCase()} (${duration_ms}ms)`);
  return { id, name, layer: 3, status, duration_ms, details: notes.join(' | ') + (failures.length ? ` || FAILED: ${failures.join('; ')}` : '') };
}

// Allow running this scenario on its own: npx tsx scenarios/p10.ts
if (import.meta.url === `file://${process.argv[1]}`) {
  runP10().then((r) => {
    console.log(r.details.split(' | ').join('\n'));
    process.exit(r.status === 'pass' ? 0 : 1);
  });
}
