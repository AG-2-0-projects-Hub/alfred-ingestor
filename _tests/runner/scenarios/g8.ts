import { env } from '../lib/env.ts';
import type { ScenarioResult } from '../run.ts';

// G8 — guest-stay-times-01
// Layer 2 (backend API). Item C, second half (2026-11-12): the host types check-in/out DATES + optional
// HH:MM TIMES; the time zone is the LISTING's (coordinates -> country -> the host's browser zone) and is
// never typed. The backend stores one exact instant per end and reads it back as local dates/times so the
// UI does no time-zone math.
//   - GET /api/properties/{id}/stay-defaults: host-only + ownership (401/403); returns the listing's zone and
//     check-in/out times (the QA property: Mexico City, 14:00 / 11:00); the listing wins over browser_tz
//   - POST /api/guests with times: the exact UTC instants (Mexico City, UTC-6); times without dates, malformed
//     times, same-day check-out before check-in -> 422
//   - GET /api/guests/{booking}/stay reads it back as typed (dates, times, closes = check-out + 24 h);
//     no times -> whole days (times null, chat open through the whole day after check-out); "Add later" ->
//     provisional; auth 401/403
//   - POST /api/guests/{booking}/stay with times edits it
//   - the cutoff now follows the check-out TIME: a guest whose check-out TIME was 25 h ago (under the old
//     end-of-day rule usually still answered) gets the "stay ended" notice and the conversation escalates;
//     23 h ago = still open (`ended` false)
// Set G8_API_ONLY=1 to skip the last step (it needs the deployed Cloud Tasks callback, see G7).

const API = env.stagingBackend.replace(/\/$/, '');
const PROP = 'aebab5c1-4cf4-4e1d-a3d1-f7c4bc11ff2f'; // QA host's trained property (Mexico, 14:00 / 11:00)
const FOREIGN_PROP = 'c4ae19af-0a61-43ce-b5f5-3a9dec915e6b'; // another host's property
const FOREIGN_BOOKING = 'bungalow-63x4ns'; // another host's booking (never written)
const NOTICE = /estancia ha terminado|stay has ended/i;
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

export async function runG8(): Promise<ScenarioResult> {
  const start = Date.now();
  const id = 'guest-stay-times-01';
  const name = 'G8: Stay times + listing time zone; cutoff follows the check-out time';
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
  const NOAUTH = { 'Content-Type': 'application/json' };
  const rest = (path: string) =>
    fetch(`${env.supabaseUrl}/rest/v1/${path}`, { headers: { apikey: env.supabaseAnonKey, Authorization: `Bearer ${token}` } })
      .then((r) => r.json() as Promise<any[]>);
  const post = (path: string, body: unknown, headers: Record<string, string> = H) =>
    fetch(`${API}${path}`, { method: 'POST', headers, body: JSON.stringify(body) });
  const get = (path: string, headers: Record<string, string> = H) => fetch(`${API}${path}`, { headers });
  const guestRow = async (b: string) =>
    (await rest(`guests?booking_id=eq.${b}&select=check_in,check_out,stay_timezone`))[0];
  const thread = async (b: string) => {
    const cid = (await rest(`conversations?booking_id=eq.${b}&select=id`))[0]?.id;
    return cid ? rest(`messages?conversation_id=eq.${cid}&select=sender_type,content&order=created_at`) : [];
  };
  const day = (offset: number) => new Date(Date.now() + offset * 86_400_000).toISOString().slice(0, 10);
  const MX = 'America/Mexico_City'; // UTC-6 all year since 2022

  const cleanup: string[] = [];
  let status: 'pass' | 'fail' = 'fail';
  let details = '';
  try {
    // 1. Both new GETs are host-only and ownership-checked.
    const d0 = await get(`/api/properties/${PROP}/stay-defaults`, {});
    const d1 = await get(`/api/properties/${PROP}/stay-defaults`, { Authorization: 'Bearer garbage' });
    const d2 = await get(`/api/properties/${FOREIGN_PROP}/stay-defaults`);
    const s0 = await get(`/api/guests/${FOREIGN_BOOKING}/stay`, {});
    const s1 = await get(`/api/guests/${FOREIGN_BOOKING}/stay`);
    need('GET auth', d0.status === 401 && d1.status === 401 && d2.status === 403 && s0.status === 401 && s1.status === 403,
      `defaults none/garbage/foreign ${d0.status}/${d1.status}/${d2.status}, stay none/foreign ${s0.status}/${s1.status}`);

    // 2. The listing's defaults: zone from the listing (wins over the browser's), times parsed from its text.
    const def = (await (await get(`/api/properties/${PROP}/stay-defaults?browser_tz=Europe/Berlin`)).json()) as any;
    need('listing defaults', def.timezone === MX && ['coordinates', 'country'].includes(def.timezone_source)
      && def.check_in_time === '14:00' && def.check_out_time === '11:00', JSON.stringify(def));

    // 3. Refused input -> 422 (no guest row).
    const base = { property_id: PROP, guest_name: 'QA-G8-bad' };
    const ok3 = { check_in_date: day(10), check_out_date: day(12), stay_timezone: MX };
    const bad = await Promise.all([
      post('/api/guests', { ...base, check_in_time: '15:00', check_out_time: '11:00' }), // times, no dates
      post('/api/guests', { ...base, ...ok3, check_in_time: '25:00' }),
      post('/api/guests', { ...base, ...ok3, check_out_time: '9:5' }),
      post('/api/guests', { ...base, check_in_date: day(10), check_out_date: day(10), stay_timezone: MX, check_in_time: '15:00', check_out_time: '11:00' }),
    ]);
    need('bad times refused', bad.every((r) => r.status === 422), bad.map((r) => r.status).join(','));

    // 4. Guest A: dates + times, entered for the listing's zone. Exact instants, read back as typed.
    const a = await post('/api/guests', { property_id: PROP, guest_name: 'QA-G8-times', ...ok3, check_in_time: '15:00', check_out_time: '11:00' });
    need('create guest A', a.ok, String(a.status));
    const A = ((await a.json()) as any).booking_id as string;
    cleanup.push(A);
    const rowA = await guestRow(A);
    need('A stored as exact instants (UTC-6)',
      new Date(rowA.check_in).getTime() === Date.parse(`${day(10)}T21:00:00Z`)
      && new Date(rowA.check_out).getTime() === Date.parse(`${day(12)}T17:00:00Z`) && rowA.stay_timezone === MX,
      `${rowA.check_in} / ${rowA.check_out}`);
    const gA = (await (await get(`/api/guests/${A}/stay`)).json()) as any;
    need('A read back as typed', gA.provisional === false && gA.timezone === MX && gA.check_in_date === day(10)
      && gA.check_in_time === '15:00' && gA.check_out_date === day(12) && gA.check_out_time === '11:00'
      && gA.closes_date === day(13) && gA.closes_time === '11:00' && gA.ended === false, JSON.stringify(gA));

    // 5. Guest B: dates, NO times = whole days (the earlier behaviour).
    const b = await post('/api/guests', { property_id: PROP, guest_name: 'QA-G8-whole', ...ok3 });
    const B = ((await b.json()) as any).booking_id as string;
    cleanup.push(B);
    const gB = (await (await get(`/api/guests/${B}/stay`)).json()) as any;
    need('B whole days', gB.check_in_time === null && gB.check_out_time === null && gB.check_out_date === day(12)
      && gB.closes_date === day(13) && gB.closes_time === null, JSON.stringify(gB));

    // 6. Guest C: "Add later" -> provisional, no zone; the closing instant is returned.
    const c = await post('/api/guests', { property_id: PROP, guest_name: 'QA-G8-later' });
    const C = ((await c.json()) as any).booking_id as string;
    cleanup.push(C);
    const gC = (await (await get(`/api/guests/${C}/stay`)).json()) as any;
    const closesIn = (Date.parse(gC.closes_at) - Date.now()) / 86_400_000;
    need('C provisional', gC.provisional === true && closesIn > 7.9 && closesIn < 8.1, `closes in ${closesIn.toFixed(2)} d`);

    // 7. Edit with times: applies, reads back.
    const ed = await post(`/api/guests/${C}/stay`, { check_in_date: day(20), check_out_date: day(22), stay_timezone: MX, check_in_time: '16:30', check_out_time: '12:00' });
    need('edit with times', ed.ok, String(ed.status));
    const gC2 = (await (await get(`/api/guests/${C}/stay`)).json()) as any;
    need('edit read back', gC2.provisional === false && gC2.check_in_time === '16:30' && gC2.check_out_time === '12:00'
      && gC2.closes_date === day(23) && gC2.closes_time === '12:00', JSON.stringify(gC2));

    // 8. The cutoff follows the check-out TIME. UTC zone; instants 25 h / 23 h ago.
    const ago = (h: number) => new Date(Date.now() - h * 3_600_000 - 60_000).toISOString(); // minute-rounded below
    const stayAt = async (label: string, h: number) => {
      const iso = ago(h);
      const date = iso.slice(0, 10), time = iso.slice(11, 16);
      const dayBefore = new Date(Date.parse(date) - 86_400_000).toISOString().slice(0, 10);
      const r = await post('/api/guests', { property_id: PROP, guest_name: label, check_in_date: dayBefore, check_out_date: date, stay_timezone: 'UTC', check_out_time: time });
      if (!r.ok) throw new Error(`create ${label} failed: ${r.status} ${await r.text()}`);
      return ((await r.json()) as any).booking_id as string;
    };
    const closed = await stayAt('QA-G8-closed', 25);
    const open = await stayAt('QA-G8-open', 23);
    cleanup.push(closed, open);
    const gClosed = (await (await get(`/api/guests/${closed}/stay`)).json()) as any;
    const gOpen = (await (await get(`/api/guests/${open}/stay`)).json()) as any;
    need('ended flag follows the time', gClosed.ended === true && gOpen.ended === false, `25 h ago ended=${gClosed.ended}, 23 h ago ended=${gOpen.ended}`);

    if (!process.env.G8_API_ONLY) {
      const sent = await post('/api/messages/web-incoming', { booking_id: closed, message: 'What is the wifi password?' }, NOAUTH);
      need('web-incoming accepted', sent.ok, String(sent.status));
      let t: any[] = [];
      for (let i = 0; i < 20; i++) {
        await sleep(2500);
        t = await thread(closed);
        if (t.filter((m) => m.sender_type === 'ai').length >= 2) break;
      }
      const ai = t.slice(t.findIndex((m) => m.sender_type === 'guest') + 1).filter((m) => m.sender_type === 'ai');
      need('check-out 25 h ago -> notice', ai.length === 1 && NOTICE.test(ai[0].content),
        ai.map((m) => String(m.content).slice(0, 40)).join(' / '));
      const conv = (await rest(`conversations?booking_id=eq.${closed}&select=mode,requires_attention,escalation_reason`))[0];
      need('escalated', conv.mode === 'intervene' && conv.requires_attention === true && conv.escalation_reason === 'stay_ended', JSON.stringify(conv));
    } else {
      notes.push('message-path step: SKIPPED (G8_API_ONLY)');
    }

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

// Allow running this scenario on its own: npx tsx scenarios/g8.ts
if (import.meta.url === `file://${process.argv[1]}`) {
  runG8().then((r) => {
    console.log(r.details.split(' | ').join('\n'));
    process.exit(r.status === 'pass' ? 0 : 1);
  });
}
