# Session Context
**Created:** 2026-04-14
**Last Session:** 2026-04-15
**Accomplished:**
- Supabase project live: `gcxxilzfhwlsjcvtpsvj` — `properties` table + `Property_assets` bucket created
- Both `.env` files corrected (SUPABASE_URL was pointing to wrong project)
- Frontend UI fully redesigned (flat form, UUID-based IDs, Airbnb URL field, markdown renderer)
- Backend updated to accept `property_name` + `airbnb_url` in POST /api/ingest
- Flutter web-server workaround in place (`run_dev.sh`)
- Full deployment complete (2026-04-15): Render + Vercel, auto-deploy on push to main

**Live URLs:**
- Backend: https://the-ingestor.onrender.com (`/health` → 200 ✓)
- Frontend: https://alfred-ingestor.vercel.app
- GitHub: https://github.com/AG-2-0-projects-Hub/alfred-ingestor (auto-deploy both platforms)

**Pending:** End-to-end test on live deployment
**Unresolved Decisions:**
- Prompts C (Audio) and D (Sheets) are NOT present verbatim in any spec document. Derived from blueprint's document-extraction pattern. Replace in `backend/services/gemini_client.py` if canonical versions exist.
- Model is set to `gemini-2.5-pro`. Confirm vs `gemini-3-pro-preview`.
- `hash_guard.py` persists hashes to local `.processed_hashes`. Resets on Render restart (in-memory only in prod). Needs Supabase store for persistent dedup across deploys.

---

## Supabase Project
| Key | Value |
|---|---|
| Project URL | `https://gcxxilzfhwlsjcvtpsvj.supabase.co` |
| Anon key | in `frontend/.env` |
| Service role key | in `backend/.env` |
| Table | `public.properties` (RLS disabled) |
| Bucket | `Property_assets` (private) |

## What Was Built

### Backend (`backend/`)
| File | Purpose |
|---|---|
| `main.py` | FastAPI app, CORS from `FRONTEND_URL` env var |
| `routers/ingest.py` | `POST /api/ingest` — accepts property_id, property_name, airbnb_url; SSE stream |
| `services/supabase_client.py` | insert_property(id, name, airbnb_url), list_upload_files, download_file, update_status, append_ingested_markdown |
| `services/hash_guard.py` | SHA-256 duplicate detection, file-persisted |
| `services/gemini_client.py` | Prompts A/B/C/D, upload_file, delete_file, generate wrappers |
| `services/file_processor.py` | Route by extension → correct Gemini call |

### Frontend (`frontend/`)
| File | Purpose |
|---|---|
| `lib/main.dart` | Supabase init, app entry |
| `lib/screens/ingest_screen.dart` | Flat form: name, airbnb_url, drop zone, voice recorder, INGEST NOW, SSE status, markdown display |
| `lib/widgets/drop_zone.dart` | Drag & drop + file picker, upload to Storage |
| `lib/widgets/voice_recorder.dart` | Browser audio recording → upload as .m4a |
| `lib/widgets/file_status_list.dart` | Live SSE status display |

---

## Next Steps (Test Checklist)
1. `cd frontend && flutter pub get` (picks up flutter_markdown)
2. `bash run_dev.sh` — open http://localhost:8080
3. `cd backend && uvicorn main:app --reload` (backend must be running)
4. Fill in Property Name, add files, click INGEST NOW
5. Verify SSE status ticks Queued → Processing → Done
6. Verify "Extracted Knowledge" markdown section appears after completion
