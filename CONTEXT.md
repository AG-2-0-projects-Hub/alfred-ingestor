# Session Context
**Created:** 2026-04-14
**Last Session:** 2026-04-17

---

## Live URLs
| Service | URL |
|---|---|
| Backend | https://the-ingestor.onrender.com |
| Frontend | https://alfred-ingestor.vercel.app |
| GitHub | https://github.com/AG-2-0-projects-Hub/alfred-ingestor |
| Auto-deploy | Yes — both Render + Vercel on push to `main` |

## Supabase Project
| Key | Value |
|---|---|
| MCP name | `supabase-the-ingestor` |
| project_ref | `gcxxilzfhwlsjcvtpsvj` |
| Project URL | `https://gcxxilzfhwlsjcvtpsvj.supabase.co` |
| Anon key | in `frontend/.env` |
| Service role key | in `backend/.env` |
| Table | `public.properties` (RLS disabled) |
| Bucket | `Property_assets` (private) |

---

## Stack
- **Backend:** FastAPI + uvicorn, Python 3.12 (pyenv at `~/.pyenv/versions/3.12.0`), deployed on Render
- **Frontend:** Flutter web, deployed on Vercel
- **AI:** google-genai SDK, model `gemini-2.5-pro`
- **Storage/DB:** Supabase (Storage + Postgres)

---

## What Was Built

### Backend (`backend/`)
| File | Purpose |
|---|---|
| `main.py` | FastAPI app, CORS from `FRONTEND_URL` env var (comma-separated) |
| `routers/ingest.py` | `POST /api/ingest` — SSE stream, sequential file processing |
| `services/supabase_client.py` | insert_property, list_upload_files, download_file, update_status, append_ingested_markdown |
| `services/hash_guard.py` | SHA-256 duplicate detection, persisted to `.processed_hashes` file |
| `services/gemini_client.py` | Prompts A/B/C/D, upload_file (BytesIO), delete_file, _generate |
| `services/file_processor.py` | Route by extension → correct Gemini prompt |

### Frontend (`frontend/`)
| File | Purpose |
|---|---|
| `lib/main.dart` | Supabase init, app entry |
| `lib/screens/ingest_screen.dart` | Flat form: name, airbnb_url, drop zone, voice recorder, INGEST NOW, SSE status, markdown display |
| `lib/widgets/drop_zone.dart` | Drag & drop + file picker, upload to Supabase Storage |
| `lib/widgets/voice_recorder.dart` | Browser audio recording → upload as .m4a |
| `lib/widgets/file_status_list.dart` | Live SSE status display (queued/processing/done/skipped/error/timeout) |

---

## Processing Architecture
- **Sequential** — one file at a time, A→Z order
- **Per-file error isolation** — one failure emits "error" and continues to next file
- **File routing:** PDF → Prompt A (File API) | Images → Prompt B (File API) | Audio → Prompt C (File API) | DOCX → Prompt A (text) | XLSX/CSV → Prompt D (text)
- **SSE events:** `queued` → `processing` → `heartbeat` (every 10s) → `done` / `skipped` / `error`

---

## Session 2026-04-17 — Bugs Fixed & Commits

### Commit `82d0396` — `Fix: pass BytesIO to Gemini File API upload instead of raw bytes`
**File:** `backend/services/gemini_client.py`
- Added `import io`
- `client.files.upload(file=data)` → `client.files.upload(file=io.BytesIO(data))`
- **Root cause:** google-genai SDK interprets the `file=` argument as a file path, not raw bytes

### Commit `4dab792` — `Fix: SSE heartbeat, CancelledError handling, frontend timeout detection`
**Files:** `backend/routers/ingest.py`, `frontend/lib/screens/ingest_screen.dart`, `frontend/lib/widgets/file_status_list.dart`

**Backend:**
- `process_file` wrapped in `asyncio.create_task`; `asyncio.shield` + `wait_for(timeout=10)` loop yields `heartbeat` events every 10s during Gemini processing
- Outer `except BaseException` catches `CancelledError` (not caught by `except Exception`), cancels in-flight task, re-raises — prevents zombie thread-pool threads on client disconnect

**Frontend:**
- SSE stream wrapped in `.timeout(90s, onTimeout: close)` — heartbeats reset the timer; 90s silence = backend dead
- `_markPendingFilesAsTimeout()` called in `finally` — any file still `queued`/`processing` when stream ends becomes `timeout` with "No response — try again"
- `_handleSseEvent` filters `heartbeat` and `stream_closed` statuses (must not overwrite spinner)
- `file_status_list.dart`: added `timeout` status (orange `timer_off` icon, "Timeout — try again" label)

---

## Verified Working (local test 2026-04-17)
- `upload_file` + `process_with_prompt_b` (Kitchen.png) → full Gemini response ✓
- Full end-to-end via API: `POST /api/ingest` → SSE `queued → processing → done` → markdown written to Supabase ✓
- DOCX processing confirmed working on live app (Bungalow Airbnb Convos history.docx)

---

## Known Issues / Pending

### High Priority
- **File API files (images/PDFs/audio) stuck in Processing on live app** — root causes identified, fixes deployed in `4dab792`, awaiting live test confirmation. Most likely: tenacity retrying 429s from Gemini on the old API key; new key is in place.

### Medium Priority
- **hash_guard.py persists to local `.processed_hashes` file** — resets on every Render restart. Needs Supabase table for persistent dedup across deploys.
- **New UUID per page load** — if user refreshes, uploaded files are orphaned under the old UUID. Property ID should be persisted (localStorage or URL param).

### Low Priority / Unresolved Decisions
- **Prompts C (Audio) and D (Sheets)** are NOT verbatim from any spec — derived from blueprint's document-extraction pattern. Replace in `gemini_client.py` if canonical versions exist.
- **Model** set to `gemini-2.5-pro`. Confirm this is the intended production model.
- **hash_guard `.processed_hashes` file** will accumulate on Render's ephemeral disk. Fine for now, needs cleanup strategy long-term.

---

## Next Steps
1. Confirm live app works after `4dab792` deploy (trigger ingest with images/PDFs, watch for heartbeats)
2. Fix hash_guard persistence (write processed hashes to Supabase `properties` table or dedicated table)
3. Fix UUID persistence across page refreshes
4. Decide on model version and prompts C/D canonicality
