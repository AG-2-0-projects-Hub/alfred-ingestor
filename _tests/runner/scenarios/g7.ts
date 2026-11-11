import { env } from '../lib/env.ts';
import type { ScenarioResult } from '../run.ts';

// G7 — guest-stay-cutoff-01
// Layer 2 (backend API, deployed staging): a guest's chat closes 24 h after check-out
// (item C, 2026-11-09). The host enters calendar dates + a time zone; the backend stores
// ONE instant (check_out = END of the check-out day in that zone) and process_guest_message
// stops answering once check_out + 24 h has passed: the guest gets a "stay ended" notice in
// the guest's language (saved in the chat) and the conversation follows the normal ESCALATION route
// (needs-attention, intervene mode, the "speaking with your host" marker, the host's alert).
//   - POST /api/guests accepts dates (stored as the right UTC instant) or none ("Add later":
//     provisional check_out ~ now + 7 d, stay_timezone NULL); bad/partial dates -> 422;
//     new booking ids end in a 10-char suffix
//   - POST /api/guests/{booking}/stay: no/garbage token -> 401, another host's guest -> 403
//   - a guest of a stay that ended days ago writes -> exactly one `ai` row, the notice;
//     conversation escalated (reason stay_ended); a follow-up is NOT answered again (host in charge)
//   - the notice is in the guest's recorded language (en/es), else the PROPERTY's language (country ->
//     welcome language); the QA property is in Mexico, so the first notice here is Spanish
//   - the host moves the dates forward and resolves -> the NEXT message gets a normal Alfred
//     reply (the earlier notice stays; nothing is rewritten)
//   - a single unknown booking id still answers 404, not 429 (the miss throttle is
//     per client IP, and is deliberately NOT hammered here: it would block this runner)
// Telegram/WhatsApp arrival and the host alert (the QA host has neither channel set up)
// are checked by hand with the founder's own phone/host account.

const API = env.stagingBackend.replace(/\/$/, '');
const PROP = 'aebab5c1-4cf4-4e1d-a3d1-f7c4bc11ff2f'; // QA host's trained property (staging)
const FOREIGN_BOOKING = 'bungalow-63x4ns'; // a booking of another host (never written)
const NOTICE = /estancia ha terminado|stay has ended/i; // either language
const NOTICE_ES = /estancia ha terminado/i; // the QA property is in Mexico
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

export async function runG7(): Promise<ScenarioResult> {
  const start = Date.now();
  const id = 'guest-stay-cutoff-01';
  const name = 'G7: Chat closes 24 h after check-out; host sets the stay dates';
  console.log(`[${id}] starting...`);

  const notes: string[] = [];
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
  const post = (path: string, body: unknown, headers: Record<string, string> = H) =>
    fetch(`${API}${path}`, { method: 'POST', headers, body: JSON.stringify(body) });
  const guestRow = async (b: string) =>
    (await rest(`guests?booking_id=eq.${b}&select=check_in,check_out,stay_timezone`))[0];
  const thread = async (b: string) => {
    const cid = (await rest(`conversations?booking_id=eq.${b}&select=id`))[0]?.id;
    return cid ? rest(`messages?conversation_id=eq.${cid}&select=sender_type,content&order=created_at`) : [];
  };
  const day = (offset: number) => new Date(Date.now() + offset * 86_400_000).toISOString().slice(0, 10);

  const cleanup: string[] = [];
  let status: 'pass' | 'fail' = 'fail';
  let details = '';
  try {
    // 1. /stay is host-only and ownership-checked.
    const stayBody = { check_in_date: day(0), check_out_date: day(2), stay_timezone: 'UTC' };
    const noTok = await post(`/api/guests/${FOREIGN_BOOKING}/stay`, stayBody, { 'Content-Type': 'application/json' });
    const badTok = await post(`/api/guests/${FOREIGN_BOOKING}/stay`, stayBody, { Authorization: 'Bearer garbage', 'Content-Type': 'application/json' });
    const foreign = await post(`/api/guests/${FOREIGN_BOOKING}/stay`, stayBody);
    need('stay auth', noTok.status === 401 && badTok.status === 401 && foreign.status === 403,
      `none ${noTok.status}, garbage ${badTok.status}, other host ${foreign.status}`);

    // 2. Refused dates -> 422 (and no guest row is created).
    const base = { property_id: PROP, guest_name: 'QA-G7-bad' };
    const bad = await Promise.all([
      post('/api/guests', { ...base, check_in_date: day(0) }),
      post('/api/guests', { ...base, check_in_date: day(0), check_out_date: day(2), stay_timezone: 'Not/AZone' }),
      post('/api/guests', { ...base, check_in_date: day(3), check_out_date: day(1), stay_timezone: 'UTC' }),
      post('/api/guests', { ...base, check_in_date: day(0), check_out_date: '2999-01-01', stay_timezone: 'UTC' }),
    ]);
    need('bad dates refused', bad.every((r) => r.status === 422), bad.map((r) => r.status).join(','));

    // 3. Guest A: dates in the PAST (a stay that ended days ago), entered in Mexico City.
    const a = await post('/api/guests', {
      property_id: PROP, guest_name: 'QA-G7-ended',
      check_in_date: '2026-10-01', check_out_date: '2026-10-03', stay_timezone: 'America/Mexico_City',
    });
    need('create guest A', a.ok, String(a.status));
    const A = ((await a.json()) as any).booking_id as string;
    cleanup.push(A);
    need('booking id shape', /-[a-z0-9]{10}$/.test(A) && A.length < 64, A.length + ' chars');
    const rowA = await guestRow(A);
    // End of 3 Oct in Mexico City (UTC-6 all year since 2022) = 4 Oct 06:00 UTC.
    need('A stored as the right instant',
      new Date(rowA.check_out).getTime() === Date.parse('2026-10-04T06:00:00Z') && rowA.stay_timezone === 'America/Mexico_City',
      `${rowA.check_out} ${rowA.stay_timezone}`);

    // 4. Guest B: no dates ("Add later") -> provisional end ~7 d out, zone left NULL.
    const b = await post('/api/guests', { property_id: PROP, guest_name: 'QA-G7-later' });
    need('create guest B', b.ok, String(b.status));
    const B = ((await b.json()) as any).booking_id as string;
    cleanup.push(B);
    const rowB = await guestRow(B);
    const daysOut = (new Date(rowB.check_out).getTime() - Date.now()) / 86_400_000;
    need('B provisional', rowB.stay_timezone === null && daysOut > 6.9 && daysOut < 7.1, `${daysOut.toFixed(2)} d, tz ${rowB.stay_timezone}`);

    // Send one guest message, wait for the answer to land (welcome + one ai row), then give a
    // Gemini reply, if one were going to come, time to show up. Returns the ai rows after the guest's.
    const writeAndWait = async (b: string, message: string) => {
      const sent = await post('/api/messages/web-incoming', { booking_id: b, message }, { 'Content-Type': 'application/json' });
      need(`web-incoming accepted (${b.slice(0, 12)})`, sent.ok, String(sent.status));
      for (let i = 0; i < 20; i++) {
        await sleep(2500);
        if ((await thread(b)).filter((m) => m.sender_type === 'ai').length >= 2) break;
      }
      await sleep(12_000);
      const t = await thread(b);
      return { t, ai: t.slice(t.findIndex((m) => m.sender_type === 'guest') + 1).filter((m) => m.sender_type === 'ai') };
    };

    // 5. A guest of the ended stay writes: exactly one `ai` row, the notice, and the
    //    conversation is escalated like any other escalation.
    const first = await writeAndWait(A, 'What is the wifi password?');
    need('ended stay -> only the notice, in the property language',
      first.ai.length === 1 && NOTICE_ES.test(first.ai[0].content),
      `ai rows after guest: ${first.ai.map((m) => String(m.content).slice(0, 40)).join(' / ')}`);
    const conv = (await rest(`conversations?booking_id=eq.${A}&select=mode,requires_attention,escalation_reason`))[0];
    need('escalated like any escalation',
      conv.mode === 'intervene' && conv.requires_attention === true && conv.escalation_reason === 'stay_ended', JSON.stringify(conv));
    need('"speaking with your host" marker posted', first.t.some((m) => m.sender_type === 'system' && m.content === '__SYS_INTERVENE__'));
    // A follow-up while the host is in charge is not answered (or noticed) again.
    const nBefore = first.t.length;
    await post('/api/messages/web-incoming', { booking_id: A, message: 'Hello? Anyone there?' }, { 'Content-Type': 'application/json' });
    await sleep(14_000);
    const followUp = (await thread(A)).slice(nBefore);
    need('follow-up goes to the host, no second notice',
      followUp.some((m) => m.sender_type === 'guest') && !followUp.some((m) => m.sender_type === 'ai'));

    // 6. Host moves the dates forward and resolves the escalation: applies from the NEXT message.
    const moved = await post(`/api/guests/${A}/stay`, stayBody);
    need('host edits dates', moved.ok, String(moved.status));
    const rowA2 = await guestRow(A);
    need('edit stored (end of day+2 UTC = day+3 00:00Z)',
      new Date(rowA2.check_out).getTime() === Date.parse(`${day(3)}T00:00:00Z`) && rowA2.stay_timezone === 'UTC', rowA2.check_out);
    const resolved = await post('/api/conversations/resolve', { booking_id: A });
    const conv2 = (await rest(`conversations?booking_id=eq.${A}&select=mode,requires_attention`))[0];
    need('host resolves -> back to autopilot', resolved.ok && conv2.mode === 'autopilot' && conv2.requires_attention === false, JSON.stringify(conv2));
    const before = (await thread(A)).length;
    await post('/api/messages/web-incoming', { booking_id: A, message: 'Hi again, what time is check-in?' }, { 'Content-Type': 'application/json' });
    let reply: any;
    for (let i = 0; i < 40; i++) {
      await sleep(3000);
      const t2 = await thread(A);
      reply = t2.slice(before).find((m) => m.sender_type === 'ai');
      if (reply) break;
    }
    need('after the move Alfred answers normally', !!reply && !NOTICE.test(reply.content), reply ? String(reply.content).slice(0, 50) : 'no reply in 120 s');
    need('earlier notice kept', (await thread(A)).some((m) => NOTICE.test(m.content)));

    // 7. One unknown id is a plain 404 (throttle only bites after repeated misses).
    const miss = await post('/api/messages/web-incoming', { booking_id: 'no-such-booking-zzzzzzzzzz', message: 'hi' }, { 'Content-Type': 'application/json' });
    need('single miss is 404', miss.status === 404, String(miss.status));

    status = 'pass';
    details = notes.join(' | ');
  } catch (err) {
    details = `Exception: ${(err as Error).message}. Notes so far: ${notes.join(' | ')}`;
  } finally {
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
  return { id, name, layer: 2, status, duration_ms, details };
}

// Allow running this scenario on its own: npx tsx scenarios/g7.ts
if (import.meta.url === `file://${process.argv[1]}`) {
  runG7().then((r) => {
    console.log(r.details.split(' | ').join('\n'));
    process.exit(r.status === 'pass' ? 0 : 1);
  });
}
