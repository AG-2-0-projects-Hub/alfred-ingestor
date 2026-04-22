# BLAST Phase 1: The Ingestor Mini-Project Implementation Plan

This is a comprehensive step-by-step plan for Claude Code to execute the native rebuild of the "Supabase Alfred Airbnb - B2 - The Ingestor" workflow.

## 1. MCP & Skill Setup

Before writing code, ensure the following skills and MCP tools are appropriately mapped and active.

### Skills to Utilize
- **`gemini-api-dev`**: 
  - **Why**: Required to guarantee optimal integration with the modern `google-genai` SDK and Gemini 2.5 Pro. Crucial for the Gemini File API usage (uploading PDFs, Audio, Images) and generating responses using the structured prompts.
- **Find Skills** (`npx skills find`):
  - **Why**: Use if additional boilerplate is needed for FastAPI, Flutter, or Supabase handling, but standard implementation according to context below is preferred.

### MCPs and Tools to Enable 
Activating too many broad tools burdens context. Use `mcp-tool-manager` (via `AG_master_files/_mcp_profiles/global.json`) if you need to restrict or bring in tools:
- **`flutter` MCP**: Needs `flutter_run`, `flutter_analyze` for creating the frontend scaffold, verifying the builds, and running localhost in dev mode.
- **`context7` MCP**: Needs `mcp_context7_resolve-library-id` and `mcp_context7_query-docs`. Extremely vital for guaranteeing up-to-date syntax for `fastapi`, `supabase-py` (Python Supabase SDK), `python-docx`, `openpyxl`, and `supabase-flutter` (Flutter Supabase SDK).
- **Filesystem Tools** (`view_file`, `write_to_file`): Core tools for actually laying out the project framework detailed in Section 11 of the specs. 

---

## 2. Backend Implementation Steps (`/backend`)

The backend is built with FastAPI. It handles routing by file extension and processes documents sequentially via Gemini 2.5 Pro via Server-Sent Events (SSE).

1. **`backend/requirements.txt` & `.env.example`**
   - Populate requirements: `fastapi`, `uvicorn`, `supabase`, `google-genai` (New SDK!), `python-docx`, `openpyxl`, `pandas`, `python-multipart`.
   - Setup `.env.example` exactly as defined in Section 6.

2. **`backend/main.py`**
   - Initialize FastAPI app.
   - Configure CORS dynamically using `FRONTEND_URL` environment variable for seamless Vercel transitions.
   - Implement `GET /health` returning `{"status": "ok"}` (Render requirement).
   - Ingest router inclusion.

3. **`backend/routers/ingest.py`**
   - Implement `POST /api/ingest`. Payload: `{"property_id": "<ID>"}`.
   - Use FastAPI `StreamingResponse` (Server-Sent Events) to stream status.
   - **Critical Rule**: Process files SEQUENTIALLY, not in parallel. This avoids Gemini throughput rate limits and keeps the SSE stream strictly ordered.

4. **`backend/services/supabase_client.py`**
   - **Property Insertion**: Method to establish a new row in the `properties` table utilizing the newly generated `property_id`. 
   - **List Files**: Method to list files at `Property_assets/{property_id}/user_uploads/`. Do NOT delete these files after processing (they are permanently preserved; vectorization happens out of bounds later).
   - **Status Updates**: Method to `PATCH properties SET status = 'Ingesting' | 'Ingested' | 'Ingest_Error' WHERE id = property_id`.
   - **Append Logic**: Method to implement exact Make.com append mechanism. Fetch existing `ingested_markdown`, append with `\n\n---\n\n`, and save back. Never wipe existing data.

5. **`backend/services/hash_guard.py`**
   - Implement duplicate detection. Calculate SHA-256 for downloaded files (or check Supabase Object ETag/metadata) and skip if already processed.

6. **`backend/services/gemini_client.py`**
   - Use `gemini-api-dev` knowledge to write a wrapper for the new Google GenAI SDK.
   - Needs `upload_file()` for temporary hosting of PDFs/Images/Audio.
   - **Cleanup mechanism**: Needs `delete_file()` to immediately delete the file from the Gemini File API as soon as the text response is acquired.
   - Implement strict call wrappers providing the Exact System Instructions and User Prompts. **Note to Claude: YOU MUST copy Prompts A/B/C/D verbatim from the User Spec (Prompt A for PDF/DOCX, B for Image, C for Audio, D for Sheets). DO NOT paraphrase them.**

7. **`backend/services/file_processor.py`**
   - Core Router Logic runs sequentially:
     - **PDF, Images, Audio/Voice**: Upload via Gemini File API -> Process -> Delete Gemini File instantly. 
     - **DOCX/DOC**: Extract string natively using `python-docx` -> Process directly with Prompt A.
     - **Sheets (xlsx/csv)**: Read structured text rows via `openpyxl`/`pandas` -> Process directly with Prompt D.

---

## 3. Frontend Implementation Steps (`/frontend`)

The frontend is a Flutter Web app focusing on file drops, realtime DB status mapping, and recording live audio. 

1. **`frontend/lib/main.dart`**
   - Basic setup. Load Supabase client to upload and initialize database queries directly for performance.

2. **`frontend/lib/screens/ingest_screen.dart`**
   - Scaffold maintaining UI layout with a Property Registration step:
     - Add a simple "Onboarding Field" for **Property Name**. 
     - No free-text `property_id` input and no dropdowns. 
     - Generate a slug automatically (e.g. `Beach House Malibu` -> `beach-house-malibu-[4-rnd-chars]`).
     - Utilize the Supabase client to INSERT this new property row on first use, exposing the interaction zone once generated.

3. **`frontend/lib/widgets/drop_zone.dart`**
   - Drag & Drop implementations. Supported types: PDF, DOCX/DOC, Images, Sheets, Audio.
   - On drop -> Upload instantly to `Property_assets/{property_id}/user_uploads/{filename}`.
   - Display a tight ✓ (success) or ✗ (failed) per file.

4. **`frontend/lib/widgets/voice_recorder.dart`**
   - Native audio recording logic in the browser. 
   - Encapsulate the stream and save internally as `.webm`.
   - On completion -> Immediately upload to storage path above just like an audio drop.

5. **`frontend/lib/widgets/file_status_list.dart`**
   - Listen to the SSE stream from `POST /api/ingest`.
   - Visually reflect in sequential order: `[File Name] - Queued -> Processing -> Done (or Error)`.

---

## 4. Integration & Wiring

1. **"Ingest" Button Logic:**
   - Disables itself to prevent double clicking/execution logic.
   - Fires the `/api/ingest` POST call to trigger sequential processing.
   - Feeds the returned SSE stream string events back into frontend state variables, repainting the UI cleanly per file.
2. **Backend Completion Cycle:** 
   - Completes consecutive batch -> Appends final markdown blocks cleanly -> Pushes property status `Ingested` via Supabase -> Ends SSE HTTP response.
3. **Failsafe:** 
   - If the FastAPI process throws a breakdown, trap it and force `PATCH properties SET status = 'Ingest_Error'`.

---

## 5. Localhost Test Checklist

- [ ] Startup `uvicorn main:app --reload` (FastAPI) and confirm `/health` = 200.
- [ ] Startup `flutter run -d chrome` (Frontend).
- [ ] Type a "Property Name" into the onboarding field. Verify a slug property id is generated and a new DB row exists.
- [ ] Drop 1 PDF, 1 Image, 1 DOCX, 1 CSV. Verify green ✓ and check Supabase GUI for `{property_id}/user_uploads/`.
- [ ] Record a 5-second voice note, click stop. Verify `.webm` hits Supabase.
- [ ] Click "Ingest". See exact file statuses tick from `Queued` -> `Processing` -> `Done` (Sequentially).
- [ ] Look at Supabase `properties` table. `status` should quickly lock to `Ingesting` and eventually settle to `Ingested`.
- [ ] Verify `ingested_markdown` in the DB has processed outputs separated cleanly by `\n\n---\n\n`.
- [ ] Re-click "Ingest". Verify Hash duplicate detection correctly skips all generation endpoints.

---

## 6. Environment Variables List

**Backend (`backend/.env`)**
```env
SUPABASE_URL="https://[PROJECT].supabase.co"
SUPABASE_SERVICE_ROLE_KEY="eyJh..." # MUST BE SERVICE ROLE
GEMINI_API_KEY="AIza..."
FRONTEND_URL="http://localhost:3000" # Explicit CORS binding
```

**Frontend (`frontend/.env`)**
```env
SUPABASE_URL="https://[PROJECT].supabase.co"
SUPABASE_ANON_KEY="eyJh..." 
```

**HANDOFF INSTRUCTION FOR CLAUDE CODE:** Standardize the backend scaffold immediately, verify SDK availability via Context7 MCP queries, and follow this document chronologically to build out The Ingestor. Note: DO NOT PARAPHRASE ANY GEMINI PROMPTS FROM THE SPEC.
