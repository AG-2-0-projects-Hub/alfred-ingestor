import { readFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { env } from '../lib/env.ts';
import type { ScenarioResult } from '../run.ts';

// B1 — ingest-train-now-e2e-01
// Layer 3 (backend end-to-end, no browser): the core Train Now flow against the
// REAL deployed staging stack — Storage upload -> POST /api/ingest (sub-second
// dispatcher) -> Cloud Tasks workers (scrape + per-file ingest + auto-merge) ->
// terminal status, observed only through the DB, exactly like the frontend's
// realtime/poll path. Drives the API directly because Flutter's canvas-rendered
// file picker can't be driven by Playwright (confirmed 2026-09-21: native
// file-chooser intercept and synthetic drag-drop both failed).
//
// Covers, in one real run: the worker rewrite (per-file state), the scraper's
// JSON-native structuring (location/hero image), UNIVERSAL_FIELDS (country/city),
// photo-triage persistence (curated_photos reaches the DB), the official-name
// fallback, and the Gemini model pin (a 100%-failure model fails every file).
//
// Fixtures are the founder's real Bungalow listing files, read from the
// gitignored _Context/ harness (local-only by design — contains real guest chat).

const __dirname = dirname(fileURLToPath(import.meta.url));
const FIXTURE_DIR = resolve(
  __dirname,
  '../../../_Context/full_fidelity_harness/real_property_files/Bungalow',
);
const FIXTURE_FILES = [
  'Basic Airbnb Bungalow automated messages.docx',
  'PXL_20251126_171327592_2.jpg',
  'PXL_20251126_171311559_2.jpg',
];
const LISTING_URL = 'https://www.airbnb.com/rooms/781332019922885278';
const BUCKET = 'Property_assets';
const TERMINAL = new Set(['Trained', 'Conflict_Pending', 'Merged', 'Ingest_Error']);
const POLL_MS = 6_000;
const DEADLINE_MS = 9 * 60_000;

const MIME: Record<string, string> = {
  docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  jpg: 'image/jpeg',
};

async function signIn(): Promise<{ token: string }> {
  const res = await fetch(`${env.supabaseUrl}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: { apikey: env.supabaseAnonKey, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: env.testHostEmail, password: env.testHostPassword }),
  });
  const json = await res.json();
  if (!res.ok) throw new Error(`auth failed: ${JSON.stringify(json)}`);
  return { token: json.access_token as string };
}

const authHeaders = (token: string) => ({
  apikey: env.supabaseAnonKey,
  Authorization: `Bearer ${token}`,
});

async function uploadFile(token: string, propertyId: string, filename: string) {
  const bytes = await readFile(resolve(FIXTURE_DIR, filename));
  const safe = filename.replace(/[^\w.\- ]/g, '_');
  const ext = safe.split('.').pop()!.toLowerCase();
  const res = await fetch(
    `${env.supabaseUrl}/storage/v1/object/${BUCKET}/${propertyId}/user_uploads/${encodeURIComponent(safe)}`,
    {
      method: 'POST',
      headers: {
        ...authHeaders(token),
        'Content-Type': MIME[ext] ?? 'application/octet-stream',
        'x-upsert': 'true',
      },
      body: bytes,
    },
  );
  if (!res.ok) throw new Error(`upload ${safe} failed: ${res.status} ${await res.text()}`);
}

async function getRow(token: string, propertyId: string): Promise<Record<string, any> | null> {
  const res = await fetch(
    `${env.supabaseUrl}/rest/v1/properties?id=eq.${propertyId}` +
      `&select=status,ingest_stage,ingest_files,master_json,curated_photos,scraped_markdown,scrape_retry`,
    { headers: authHeaders(token) },
  );
  const rows = await res.json();
  return Array.isArray(rows) ? (rows[0] ?? null) : null;
}

async function heroImageExists(token: string, propertyId: string): Promise<boolean> {
  const res = await fetch(`${env.supabaseUrl}/storage/v1/object/list/${BUCKET}`, {
    method: 'POST',
    headers: { ...authHeaders(token), 'Content-Type': 'application/json' },
    body: JSON.stringify({ prefix: `${propertyId}/hero_image`, limit: 10 }),
  });
  const items = await res.json();
  return Array.isArray(items) && items.some((i: any) => i.name === 'main.jpg');
}

export async function runB1(): Promise<ScenarioResult> {
  const start = Date.now();
  const id = 'ingest-train-now-e2e-01';
  const name = 'B1: Train Now end-to-end (scrape + files + merge) on deployed staging';
  console.log(`[${id}] starting...`);

  const notes: string[] = [];
  const failures: string[] = [];
  let status: 'pass' | 'fail' = 'fail';
  let details = '';
  const artifacts: ScenarioResult['artifacts'] = {};
  let token = '';
  const propertyId = randomUUID();

  try {
    ({ token } = await signIn());
    notes.push('signed in');

    for (const f of FIXTURE_FILES) await uploadFile(token, propertyId, f);
    notes.push(`uploaded ${FIXTURE_FILES.length} real files`);

    const dispatchRes = await fetch(`${env.stagingBackend}/api/ingest`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        property_id: propertyId,
        property_name: `QA-B1-${Date.now()}`,
        airbnb_url: LISTING_URL,
      }),
    });
    const dispatchMs = Date.now() - start;
    const dispatchJson = await dispatchRes.json().catch(() => ({}));
    if (!dispatchRes.ok || dispatchJson.property_id !== propertyId) {
      throw new Error(`dispatch failed: ${dispatchRes.status} ${JSON.stringify(dispatchJson)}`);
    }
    notes.push(`dispatched (run ${String(dispatchJson.run_id).slice(0, 8)})`);

    let row: Record<string, any> | null = null;
    const deadline = Date.now() + DEADLINE_MS;
    while (Date.now() < deadline) {
      await new Promise(r => setTimeout(r, POLL_MS));
      row = await getRow(token, propertyId);
      if (row && TERMINAL.has(row.status)) break;
    }
    if (!row || !TERMINAL.has(row.status)) {
      throw new Error(`never reached a terminal status in ${DEADLINE_MS / 60000} min (last: ${row?.status})`);
    }
    notes.push(`terminal status ${row.status} after ${Math.round((Date.now() - start) / 1000)}s`);
    artifacts.finalStatus = row.status;

    if (!['Trained', 'Conflict_Pending', 'Merged'].includes(row.status)) {
      failures.push(`status is ${row.status}, expected Trained/Conflict_Pending`);
    }

    const files = (row.ingest_files ?? {}) as Record<string, { state?: string }>;
    const notDone = Object.entries(files).filter(([, v]) => v.state !== 'done').map(([k]) => k);
    if (Object.keys(files).length !== FIXTURE_FILES.length) {
      failures.push(`ingest_files has ${Object.keys(files).length} entries, expected ${FIXTURE_FILES.length}`);
    }
    if (notDone.length) failures.push(`files not done: ${notDone.join(', ')}`);

    const master = row.master_json ?? {};
    const loc = master.location ?? {};
    for (const k of ['country', 'city']) {
      if (typeof loc[k] !== 'string' || !loc[k].trim()) failures.push(`master_json.location.${k} missing`);
    }
    const propName = master.property_identity?.property_name;
    if (typeof propName !== 'string' || !propName.trim() || /not specified/i.test(propName)) {
      failures.push(`property_name missing or placeholder: ${JSON.stringify(propName)}`);
    }

    // media.thumbnail_url is an optional LLM field (omitted ~40% of runs), so the
    // hero image must come from the backend's fallback chain -- assert the stored
    // result, never the model's field. The completeness label must stay inside
    // the enum so the Low-only retries can fire.
    let completeness: string | null = null;
    try {
      completeness = JSON.parse(row.scraped_markdown ?? '{}')?.meta?.data_completeness ?? null;
    } catch {
      failures.push('scraped_markdown is not valid JSON');
    }
    if (!['High', 'Medium', 'Low'].includes(completeness ?? '')) {
      failures.push(`meta.data_completeness ${JSON.stringify(completeness)} outside High/Medium/Low`);
    }
    if (!(await heroImageExists(token, propertyId))) failures.push('hero_image/main.jpg not uploaded');

    const curated = Array.isArray(row.curated_photos) ? row.curated_photos.length : 0;
    if (curated < 1) failures.push('curated_photos empty (photo triage did not persist)');
    if (row.scrape_retry && Object.keys(row.scrape_retry).length > 0) {
      failures.push(`scrape_retry set: ${JSON.stringify(row.scrape_retry)}`);
    }

    if (dispatchMs > 30_000) failures.push(`dispatch+upload took ${dispatchMs}ms (dispatcher should be fast)`);
    artifacts.curatedPhotos = curated;
    artifacts.country = loc.country;
    artifacts.city = loc.city;

    status = failures.length === 0 ? 'pass' : 'fail';
    details = `${notes.join(' | ')}${failures.length ? ` | FAILURES: ${failures.join('; ')}` : ''}`;
  } catch (err) {
    status = 'fail';
    details = `Exception: ${(err as Error).message}. Notes: ${notes.join(' | ')}`;
  } finally {
    if (token) {
      const del = await fetch(`${env.stagingBackend}/api/property/${propertyId}/soft-delete`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${token}` },
      }).catch(() => null);
      notes.push(`cleanup soft-delete: ${del?.status ?? 'no response'}`);
    }
  }

  const duration_ms = Date.now() - start;
  console.log(`[${id}] ${status.toUpperCase()} (${duration_ms}ms)`);
  return { id, name, layer: 3, status, duration_ms, details, artifacts };
}
