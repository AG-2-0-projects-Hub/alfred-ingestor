# Session Context
**Created:** 2026-04-14
**Last Session:** 2026-05-07 (updated)

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

## Session 2026-05-07 (Part 3) — UI Upgrade Implemented + Bug Fixes

### Status
UI overhaul complete and bug-fixed. Awaiting commit/push + Supabase manual steps below.

### Supabase Step A — DONE
- Email auth enabled ✅
- RLS enabled on `properties` ✅
- `owner_only` policy created ✅
- `UPDATE properties SET owner_id = 'f86ebcae-683d-4914-837b-caaedca6a19d';` — **pending** (run without angle brackets)

### Supabase Auth config — PENDING (fix broken session/upload state)
- **Disable "Confirm email"** (Auth → Email) — removes broken confirmation redirect
- **Site URL** (Auth → URL Configuration) → `https://alfred-ingestor.vercel.app`
- **Add Redirect URL** → `https://alfred-ingestor.vercel.app/**`
- **Delete test account** and sign up fresh after these are applied

### Supabase Storage policies — PENDING (required for frontend file uploads)
```sql
CREATE POLICY "allow_authenticated_uploads" ON storage.objects
FOR INSERT TO authenticated WITH CHECK (bucket_id = 'Property_assets');

CREATE POLICY "allow_authenticated_reads" ON storage.objects
FOR SELECT TO authenticated USING (bucket_id = 'Property_assets');

CREATE POLICY "allow_authenticated_updates" ON storage.objects
FOR UPDATE TO authenticated USING (bucket_id = 'Property_assets');
```

### Supabase Step B — PENDING (do before testing guest link generation)
- Add `guest_chat_url` + `host_chat_url` columns to `guests` table (see plan §1 Step B)
- Add RLS policy on `guests` table (optional but recommended)

### What was built (commit `721dd3e`)
| File | Change |
|---|---|
| `backend/services/supabase_client.py` | `insert_property()` gets `owner_id` param; added `update_master_json()`, `create_guest()`, `get_guests_for_property()` |
| `backend/services/gemini_merge_resolve.py` | Added `run_knowledge_injection()` (Knowledge Injector prompt) |
| `backend/routers/ingest.py` | Auth header extraction + `owner_id` stamping; new `POST /api/ingest/add-knowledge` |
| `backend/routers/messages.py` | New `POST /api/guests` endpoint (slug-based booking ID generation) |
| `frontend/lib/main.dart` | Auth guard + all new routes; `_AuthWatcher` for logout redirect |
| `frontend/lib/screens/auth_screen.dart` | NEW — login/signup card |
| `frontend/lib/screens/dashboard_screen.dart` | NEW — responsive property grid |
| `frontend/lib/screens/add_property_screen.dart` | NEW — refactored IngestScreen with auth token + back button |
| `frontend/lib/screens/host_panel_screen.dart` | NEW — per-property conversation list |
| `frontend/lib/widgets/property_card.dart` | NEW — state-aware card (Processing/Conflict/Ready/Error states) |
| `frontend/lib/widgets/property_detail_drawer.dart` | NEW — 4-tab side drawer (Overview/Files/Knowledge/Resolve) |
| `frontend/lib/widgets/generate_guest_link_dialog.dart` | NEW — 2-step dialog: name input → copy-able URLs |

### Bug fixes (uncommitted — commit after Supabase steps done)
| File | Fix |
|---|---|
| `frontend/lib/main.dart` | Session restored on page reload: `onAuthStateChange` subscription in `initState` triggers rebuild after Supabase restores session from localStorage asynchronously |
| `frontend/lib/screens/auth_screen.dart` | `emailRedirectTo: Uri.base.scheme + Uri.base.host` added to `signUp` call |
| `frontend/lib/screens/add_property_screen.dart` | "Merge Now" only shown when `_ingestedMarkdown` is non-empty (not just when scraper ran with no uploaded files) |
| `frontend/lib/screens/ingest_screen.dart` | Same "Merge Now" guard applied |

---

## Session 2026-05-07 — Messenger Phase 1 Verified

### Commits deployed
- `ea6e6d3` — fix: replace onPostgresChanges with .stream() API in both chat screens (already pushed to origin/main, Vercel auto-deployed)

### Test data inserted (Supabase)
- **guests:** `booking_id=TEST-001`, `property_id=9bea38ea-ac14-4e3a-abbc-b31ab9774e32` (dos rios), `preferred_language=english`
- **conversations:** pre-created row for TEST-001 (id: `12b4ec10-efe3-44cb-848a-009cbf6e0475`)

### E2E audit results (2026-05-07)
| Check | Result |
|---|---|
| Backend health (`/health`) | ✅ 200 OK |
| Vercel frontend | ✅ 200 OK |
| `ea6e6d3` pushed & deployed | ✅ Confirmed (git up to date with origin) |
| `POST /api/messages/web-incoming` (TEST-001) | ✅ 200 OK, ~11s, Alfred replied correctly |
| Guest message written to messages table | ✅ Confirmed |
| AI reply written with sentiment | ✅ `sentiment: "positive"` |
| Properties with master_json | `dos rios` (Trained), `Bungalow bot` (Ingesting) |
| Realtime `.stream()` fix | Code verified — cannot test realtime without browser |

### Chat test URLs
- Guest view: `https://alfred-ingestor.vercel.app/chat?booking=TEST-001`
- Host live panel: `https://alfred-ingestor.vercel.app/chat-live?booking=TEST-001&property=9bea38ea-ac14-4e3a-abbc-b31ab9774e32`

---

## Session 2026-05-07 (Part 4) — Dashboard Property Card Enhancements

### What was built (uncommitted — pending user push)

#### New files
| File | Purpose |
|---|---|
| `frontend/lib/widgets/archived_chats_dialog.dart` | Dialog listing all past guests for a property (booking ID + name + date), tapping opens HostPanelScreen |
| `frontend/lib/screens/edit_property_screen.dart` | Edit mode: shows ingested files with per-file delete + drop zone for new files + RE-INGEST → merge flow |

#### Modified files
| File | Change |
|---|---|
| `frontend/lib/widgets/property_card.dart` | + `activeChatCount` (green badge if > 0), + calendar icon (placeholder), + chat history icon — both always visible in an info row between name and actions |
| `frontend/lib/screens/dashboard_screen.dart` | Loads guest count per property after loading properties; wires `onCalendar` (placeholder dialog) and `onArchivedChats` to PropertyCard |
| `frontend/lib/widgets/property_detail_drawer.dart` | **Files tab**: "Edit Property / Add Files" button at top → navigates to EditPropertyScreen, refreshes on return. **Knowledge tab**: "Delete Property" danger button at bottom — confirmation dialog with bold warning, deletes only `properties` row (chat history preserved) |

### Edit Property — file delete behaviour
- Deleting a file: removes from `Property_assets` storage + `file_fingerprints` DB field
- Deleted file stays visible in the list with strikethrough + "Removed" chip
- Amber warning banner appears: "The knowledge database still contains data extracted from removed files. Add new files below and re-ingest to keep the knowledge base up to date."
- **Known limitation:** deleted file's content remains in `ingested_markdown` until a full re-ingest of remaining files is done (backend constraint — not a bug)

### Active chat count
- Defined as: number of guests rows for the property (all bookings, not filtered by recency)
- Loaded via a second Supabase query after properties load; stored in `_chatCounts` map

---

---

## Session 2026-05-10 — UI/UX Full Redesign (Alfred Design System)

### What was built

#### New files
| File | Purpose |
|---|---|
| `frontend/lib/theme/app_theme.dart` | Alfred Design System — full ThemeData + design tokens |

#### Modified files
| File | Change |
|---|---|
| `frontend/pubspec.yaml` | + `google_fonts: ^6.2.1` (resolved to 6.3.3) |
| `frontend/lib/main.dart` | `AppTheme.light` replaces `ColorScheme.fromSeed(Colors.indigo)` |
| `frontend/lib/screens/auth_screen.dart` | Full rewrite: two-panel desktop layout (brand left, form right), dot-grid painter, Poppins headings, password show/hide toggle |
| `frontend/lib/screens/dashboard_screen.dart` | Teal app bar with icon badge, Inter/Poppins typography, 4-column responsive grid (>1100px), slate-50 background |
| `frontend/lib/widgets/property_card.dart` | Full rewrite: animated hover shadow, sky→teal gradient placeholder, status badge overlay on hero image, active chat badge, `_CardAction` pill buttons, `_ReadyActions` layout |
| `frontend/lib/widgets/property_detail_drawer.dart` | Teal gradient header with property icon + status subtitle, sky/teal hero placeholder, teal→primary KB chat bubbles with tail corners, `AppTheme.drawerShadow`, Google Fonts throughout |
| `frontend/lib/screens/chat_live_screen.dart` | Teal app bar with booking subtitle, pill-mode toggle, directional chat bubbles with tail corners, `AppTheme` colors throughout |
| `frontend/lib/widgets/archived_chats_dialog.dart` | Full rewrite: teal icon badge header, proper empty state, `AppTheme` colors throughout |

### Design System (AppTheme)
- **Primary**: `#0F766E` teal-700 — trust, property management
- **Accent**: `#0EA5E9` sky-500 — freedom, openness (brand promise)
- **Background**: `#F8FAFC` slate-50, **Surface**: white, **Text**: slate-800/500/400 scale
- **Typography**: Poppins (headings/labels) + Inter (body) via `google_fonts`
- **Card radius**: 16px, **Button radius**: 10px, **Badge radius**: 20px
- **Hover shadows**: tinted teal glow on cards, heavy teal shadow on drawer

### Phase 2 (future) — knowledge base chat will also include "learned knowledge" from voice notes, not just master_json

---

## Next Steps

### Immediate
1. **Commit + push** all new/modified files → Vercel auto-deploys
2. **Browser verify** full redesign on live URL

### Pending Supabase (if not done yet)
- Disable "Confirm email" in Auth → Email settings
- Set Site URL → `https://alfred-ingestor.vercel.app`
- Add Redirect URL → `https://alfred-ingestor.vercel.app/**`
- Run Storage policies (3 `CREATE POLICY` statements — see session 2026-05-07 Part 3 above)
- Run `UPDATE properties SET owner_id = 'f86ebcae-683d-4914-837b-caaedca6a19d';`
- `ALTER TABLE guests ADD COLUMN guest_chat_url text; ALTER TABLE guests ADD COLUMN host_chat_url text;` (required for guest link generation)

### Lower priority
- **Add** `INGESTOR_SUPABASE_URL`/`INGESTOR_SUPABASE_SERVICE_KEY` to Render scraper env
- **End-to-end REQ-08 test** (CSV upload)
- **Fix UUID persistence** across page refreshes (localStorage or URL param)
- **Reservations calendar** — placeholder button exists on every property card; wire up real data
- **Active chat definition** — currently counts all guests; refine to recent activity if needed
