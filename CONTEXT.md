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

## Session 2026-04-23 — Debug, QA & Verification

### Bugs Fixed (3)
1. **`supabase_client.py` L47** — `result.data or None` → `result.data if result else None` (guard against AttributeError when `maybe_single()` returns None)
2. **REQ-27 broken** — Render scraper missing `INGESTOR_SUPABASE_URL`/`INGESTOR_SUPABASE_SERVICE_KEY`, so `scraped_markdown` was always null. Fixed by adding `save_scraped_markdown()` to `supabase_client.py` and calling it from `ingest.py` after the scraper response.
3. **REQ-08 broken** — `tabulate` missing from `requirements.txt`; `df.to_markdown()` would raise `ModuleNotFoundError` for any CSV/XLSX. Added `tabulate==0.9.0` (also added undocumented `httpx==0.28.1`).

### QA Results
| Check | Result |
|-------|--------|
| Identical URL → same DB row | ✅ Confirmed (canonical ID resolution works) |
| Voice notes in Files to Ingest | ⚠️ Cannot test from backend (UI-only test) |
| Scraper → `scraped_markdown` in DB | ✅ Now working after fix |
| Dedup skips identical files | ✅ Confirmed (`already_in_db` on re-submission) |
| Hero image after ingestion | ⚠️ Not testable with fake URL; needs real Airbnb listing |

### REQ-08 / REQ-25 Status
- **REQ-08:** Code complete, tabulate installed. No end-to-end test (no CSV in test Storage).
- **REQ-25:** No hallucinations detected in Kitchen.png output. Full spec compliance needs minimal-PDF test.

---

## Known Issues / Pending

### High Priority (User Action Required)
- **Render scraper missing Supabase env vars** — Add `INGESTOR_SUPABASE_URL` and `INGESTOR_SUPABASE_SERVICE_KEY` to the Render scraper service dashboard. Ingestor-side fix compensates but scraper's own write path is still broken.

### Medium Priority
- **New UUID per page load** — if user refreshes, uploaded files are orphaned under the old UUID. Property ID should be persisted (localStorage or URL param).
- **File API files stuck on live app** — fixes deployed in `4dab792`, needs live confirmation with real images/PDFs.

### Low Priority / Unresolved Decisions
- **Prompts C (Audio) and D (Sheets)** — derived from blueprint, no verbatim spec source. Review if canonical versions exist.
- **`gemini-2.5-pro` (ingestor) vs `gemini-3-flash-preview` (scraper)** — confirm both are intended production models.

---

## Next Steps
1. Add `INGESTOR_SUPABASE_URL`/`INGESTOR_SUPABASE_SERVICE_KEY` to Render scraper env (restores REQ-27 primary path)
2. End-to-end REQ-08 test: upload a CSV via UI and trigger ingest
3. End-to-end REQ-25 audit: upload a minimal 1-page PDF, verify sections with no data show "Not provided"
4. Confirm live app heartbeat/file processing after `4dab792` deploy
5. Fix UUID persistence across page refreshes
