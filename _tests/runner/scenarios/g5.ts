import { randomUUID } from 'node:crypto';
import { env } from '../lib/env.ts';
import type { ScenarioResult } from '../run.ts';

// G5 — sec-host-endpoints-01
// Layer 2 (backend API, deployed staging): every host endpoint refuses a caller
// that is not the property's/conversation's host. The backend runs as service
// role (RLS bypassed), so these routes must police themselves. For each:
//   - no token and a garbage token -> 401
//   - a valid host token against ANOTHER host's property/booking -> 403
//   - the owning host, same token -> NOT refused (the guard lets them through)
// Item B (2026-10-15) added merge, resolve, add-knowledge, query-knowledge and
// /ingest (existing ids) to the guarded set and made resume/retry-scrape check
// ownership, not just the token.
//
// "Another host" targets are a soft-deleted staging property and a real booking
// of another host (read-only here). A failing guard on the tombstone can do no
// real harm. delete-account is only probed WITHOUT a valid token, never with one.

const API = env.stagingBackend.replace(/\/$/, '');
const FOREIGN_PROP = 'c4ae19af-0a61-43ce-b5f5-3a9dec915e6b'; // tombstone of another host
const FOREIGN_BOOKING = 'bungalow-63x4ns'; // booking of another host
const NO_CONV = randomUUID(); // a conversation id that is not the QA host's

type Req = { path: string; body?: unknown; form?: boolean };

async function call(r: Req, token?: string): Promise<number> {
  const headers: Record<string, string> = token ? { Authorization: `Bearer ${token}` } : {};
  let body: BodyInit;
  if (r.form) {
    const fd = new FormData();
    fd.append('file', new Blob([new Uint8Array([0xff, 0xd8, 0xff, 0xd9])], { type: 'image/jpeg' }), 'a.jpg');
    body = fd;
  } else {
    headers['Content-Type'] = 'application/json';
    body = JSON.stringify(r.body ?? {});
  }
  const res = await fetch(`${API}${r.path}`, { method: 'POST', headers, body });
  return res.status;
}

export async function runG5(): Promise<ScenarioResult> {
  const start = Date.now();
  const id = 'sec-host-endpoints-01';
  const name = 'G5: Host endpoints require host auth + ownership';
  console.log(`[${id}] starting...`);

  const fails: string[] = [];
  const notes: string[] = [];
  const check = (label: string, got: number, want: number | ((n: number) => boolean)) => {
    const ok = typeof want === 'number' ? got === want : want(got);
    if (!ok) fails.push(`${label}: got ${got}`);
  };

  let token = '';
  let prop = '';
  try {
    const auth = await fetch(`${env.supabaseUrl}/auth/v1/token?grant_type=password`, {
      method: 'POST',
      headers: { apikey: env.supabaseAnonKey, 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: env.testHostEmail, password: env.testHostPassword }),
    });
    if (!auth.ok) throw new Error(`QA host sign-in failed: ${auth.status}`);
    token = ((await auth.json()) as any).access_token;

    // Throwaway property owned by the QA host (empty url, no files: the run just ends in Ingest_Error).
    prop = randomUUID();
    const setup: Req = { path: '/api/ingest', body: { property_id: prop, property_name: `QA-G5-${Date.now()}`, airbnb_url: '' } };
    check('owner creates throwaway via /ingest', await call(setup, token), 200);
    await new Promise((r) => setTimeout(r, 4000));

    // 1. Every host endpoint: no token / garbage token -> 401.
    const everyRoute: Req[] = [
      { path: '/api/ingest', body: { property_id: prop, property_name: 'x', airbnb_url: '' } },
      { path: `/api/ingest/${prop}/resume` },
      { path: `/api/ingest/${prop}/retry-scrape`, body: { airbnb_url: '' } },
      { path: '/api/ingest/add-knowledge', body: { property_id: prop, text: 'x' } },
      { path: '/api/ingest/query-knowledge', body: { property_id: prop, question: 'x' } },
      { path: `/api/merge/${prop}` },
      { path: `/api/resolve/${prop}`, body: { resolutions: [] } },
      { path: '/api/messages/host-send', body: { conversation_id: NO_CONV, message: 'x' } },
      { path: '/api/conversations/resolve', body: { booking_id: FOREIGN_BOOKING } },
      { path: '/api/conversations/archive', body: { conversation_id: NO_CONV } },
      { path: '/api/conversations/announce-transition', body: { conversation_id: NO_CONV, kind: 'resume' } },
      { path: '/api/guests', body: { property_id: prop, guest_name: 'x' } },
      { path: '/api/host/avatar', form: true },
      { path: '/api/host/delete-account' },
      { path: '/api/host/escalation-email', body: { email: 'x@example.com', enabled: false } },
      { path: '/api/host/telegram/link-code' },
      { path: `/api/property/${prop}/soft-delete` },
      { path: `/api/property/${prop}/cancel-initial-train` },
    ];
    for (const r of everyRoute) {
      check(`no token ${r.path}`, await call(r), 401);
      check(`garbage token ${r.path}`, await call(r, 'garbage.token.value'), 401);
    }

    // 2. A valid token against another host's property/booking -> 403.
    const crossHost: Req[] = [
      { path: '/api/ingest', body: { property_id: FOREIGN_PROP, property_name: 'x', airbnb_url: '' } },
      // same, with the caller's OWN property name: must not move the foreign property's files in
      { path: '/api/ingest', body: { property_id: FOREIGN_PROP, property_name: 'QA-G5-own-name', airbnb_url: '' } },
      { path: `/api/ingest/${FOREIGN_PROP}/resume` },
      { path: `/api/ingest/${FOREIGN_PROP}/retry-scrape`, body: { airbnb_url: '' } },
      { path: '/api/ingest/add-knowledge', body: { property_id: FOREIGN_PROP, text: 'x' } },
      { path: '/api/ingest/query-knowledge', body: { property_id: FOREIGN_PROP, question: 'x' } },
      { path: `/api/merge/${FOREIGN_PROP}` },
      { path: `/api/resolve/${FOREIGN_PROP}`, body: { resolutions: [] } },
      { path: '/api/guests', body: { property_id: FOREIGN_PROP, guest_name: 'x' } },
      { path: '/api/messages/host-send', body: { conversation_id: NO_CONV, message: 'x' } },
      { path: '/api/conversations/resolve', body: { booking_id: FOREIGN_BOOKING } },
      { path: '/api/conversations/archive', body: { conversation_id: NO_CONV } },
      { path: '/api/conversations/announce-transition', body: { conversation_id: NO_CONV, kind: 'resume' } },
      { path: `/api/property/${FOREIGN_PROP}/soft-delete` },
      { path: `/api/property/${FOREIGN_PROP}/cancel-initial-train` },
    ];
    for (const r of crossHost) {
      const body = r.body ? ` ${JSON.stringify(r.body).slice(0, 60)}` : '';
      check(`other host ${r.path}${body}`, await call(r, token), 403);
    }

    // 3. The owner is not refused (and the add-knowledge storage_path must be this property's own folder).
    check('owner add-knowledge', await call({ path: '/api/ingest/add-knowledge', body: { property_id: prop, text: 'The wifi password is G5probe.' } }, token), 200);
    check('owner query-knowledge', await call({ path: '/api/ingest/query-knowledge', body: { property_id: prop, question: 'What is the wifi password?' } }, token), 200);
    check('owner add-knowledge, storage_path in ANOTHER property folder', await call({ path: '/api/ingest/add-knowledge', body: { property_id: prop, storage_path: `${FOREIGN_PROP}/user_uploads/x.m4a` } }, token), 422);
    check('owner merge (guard passes; status not mergeable)', await call({ path: `/api/merge/${prop}` }, token), 422);
    check('owner resolve (guard passes; status not resolvable)', await call({ path: `/api/resolve/${prop}`, body: { resolutions: [] } }, token), 422);
    check('owner re-/ingest same id (idempotent retry)', await call(setup, token), 200);
    check('owner resume', await call({ path: `/api/ingest/${prop}/resume` }, token), 200);
    check('owner retry-scrape', await call({ path: `/api/ingest/${prop}/retry-scrape`, body: { airbnb_url: '' } }, token), 200);

    notes.push(`${everyRoute.length * 2} unauthenticated + ${crossHost.length} cross-host + 8 owner probes`);
  } catch (err) {
    fails.push(`Exception: ${(err as Error).message}`);
  } finally {
    if (token && prop) {
      const del = await call({ path: `/api/property/${prop}/soft-delete` }, token).catch(() => 0);
      notes.push(`cleanup soft-delete: ${del}`);
    }
  }

  const status: 'pass' | 'fail' = fails.length === 0 ? 'pass' : 'fail';
  const details = fails.length ? `FAILED: ${fails.join(' | ')}` : notes.join(' | ');
  const duration_ms = Date.now() - start;
  console.log(`[${id}] ${status.toUpperCase()} (${duration_ms}ms)`);
  return { id, name, layer: 2, status, duration_ms, details };
}

// Allow running this scenario on its own: npx tsx scenarios/g5.ts
if (import.meta.url === `file://${process.argv[1]}`) {
  runG5().then((r) => {
    console.log(r.details.split(' | ').join('\n'));
    process.exit(r.status === 'pass' ? 0 : 1);
  });
}
