# Alfred Ingestor + Scraper Integration Plan

This document outlines the implementation plan for fulfilling all requirements in `INGESTOR_REQUIREMENTS_DOC.md`.

## 0. Initial Setup & DB Schema Changes (For Claude)

Before starting the code changes, Claude MUST execute the following SQL via the `mcp_supabase-the-ingestor` MCP server to prepare the database:

1. **Clean up existing duplicates**: Execute a query to remove duplicate `properties` rows (keep only the most recently updated one for each `airbnb_url`). The unique constraint creation will fail if duplicates exist.
2. **Apply schema changes** (via `apply_migration` or `execute_sql`):
   ```sql
   ALTER TABLE properties ADD COLUMN IF NOT EXISTS file_fingerprints JSONB DEFAULT '{}'::jsonb;
   ALTER TABLE properties ADD CONSTRAINT properties_airbnb_url_unique UNIQUE (airbnb_url);
   ```
3. **Environment Variables**: Add `SCRAPER_URL` to `backend/.env` and `backend/.env.example` (pointing to the Scraper's Render URL).

## Proposed Changes

---

### Backend (Ingestor)

Summary of changes:
- Implement `airbnb_url` deduplication: lookup existing property by `airbnb_url` and use its canonical `id`. If found, move any newly uploaded files from the frontend's temporary UUID folder to the canonical folder.
- Add Ingestion Lock: return `409 Conflict` if the property status is already `Ingesting`.
- Call Scraper API (`POST /scrape`) before processing files and handle errors.
- Download the Hero Image (Thumbnail) from the scraped markdown and upload it to Supabase Storage under `{property_id}/hero_image`.
- Update `hash_guard.py` to use a JSONB column (`file_fingerprints`) on the `properties` table for deduplication, tracking `{filename: byte_size}` to handle updated files (REQ-11).
- Enforce atomic status transitions (REQ-21): If any file fails processing, do not set the final status to `Ingested`.

#### [MODIFY] backend/routers/ingest.py
- Add `409 Conflict` check.
- Lookup canonical `property_id` based on `airbnb_url`.
- Perform `httpx.post` to `SCRAPER_URL/scrape`.
- Call `move_files_in_storage` to merge user uploads.
- Parse `**Thumbnail:** [URL]` from `scraped_markdown` and trigger hero image upload.
- Track processing errors to enforce atomic status transition.

#### [MODIFY] backend/services/supabase_client.py
- Add `get_canonical_property(airbnb_url)` and `move_files(src, dest)`.
- Update `update_status` and `insert_property` logic.
- Add helper to download and save hero image.

#### [MODIFY] backend/services/hash_guard.py
- Refactor to take `property_id` and use Supabase instead of a local file.
- Implement size-based deduplication (`{filename: size}`).

---

### Backend (Scraper)

Summary of changes:
- Import `supabase` and upsert the result of the Firecrawl scrape to the Ingestor DB to fulfill REQ-27.

#### [MODIFY] scraper/requirements.txt
- Add `supabase`.

#### [MODIFY] scraper/main.py
- Add `INGESTOR_SUPABASE_URL` and `INGESTOR_SUPABASE_SERVICE_KEY` environment variable checks.
- Add try/except block to upsert `{'airbnb_url': url, 'scraped_markdown': structured_output, 'status': 'Scraped'}` using `on_conflict='airbnb_url'`.
- Ensure write failures log the error without blocking the API response.

---

### Frontend (Flutter Web)

Summary of changes:
- Rebuild the `IngestScreen` state machine to clearly divide "Files to Ingest" and "Files Ingested" (REQ-15, REQ-16).
- Display voice notes immediately in the pre-ingestion list (REQ-13).
- Display `Nickname (Optional)` instead of `Property Name *`.
- Parse and display the official property name and hero image from the backend result after ingestion (REQ-02, REQ-03, REQ-18).
- Reject unsupported file drops (REQ-09).

#### [MODIFY] frontend/lib/screens/ingest_screen.dart
- Update form inputs (Nickname vs Property Name).
- Maintain `_filesToIngest` list.
- Display hero image and official property name using `_scrapedMarkdown`.
- Update the layout to divide into two sections.

#### [MODIFY] frontend/lib/widgets/drop_zone.dart
- Add callback to notify `IngestScreen` of new files.
- Reject dragged files that do not match `_supportedExtensions` and display inline error.

#### [MODIFY] frontend/lib/widgets/voice_recorder.dart
- Add callback to notify `IngestScreen` of newly recorded files so they appear immediately in the "Files to Ingest" list.

## Verification Plan

### Automated Tests
- Since the backend runs Python and FastAPI, we'll verify using terminal commands like `pytest` if available, or just run curl commands to test `/scrape` and `/ingest`.
- Check if UI runs without errors by running `flutter build web` or using `dart analyze`.

### Manual Verification
- After applying the changes, I'll ask the user to test the web app to verify:
  1. Identical URL submissions merge to the same DB row.
  2. Voice notes appear in "Files to Ingest" before clicking Ingest Now.
  3. Scraper populates `scraped_markdown` correctly.
  4. Deduplication accurately skips identical files and updates modified ones.
  5. Hero image is displayed at the top of the ingested view.
