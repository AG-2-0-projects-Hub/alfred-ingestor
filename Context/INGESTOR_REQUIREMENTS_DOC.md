# REQUIREMENTS DOCUMENT: Alfred Ingestor (Mini Project)
**Version:** 1.0
**Status:** Active — Pre-QA Audit
**Project:** Alfred — Airbnb Property Ingestor (Mini Project)
**Stack:** Flutter Web (UI) · FastAPI/Ingestor on Render (backend) · FastAPI/Scraper on Render (absorbed service) · Claude API (file processing) · Gemini API (scrape structuring) · Firecrawl (scraping) · Supabase (storage + DB) · Make.com (async notifications only)
**Last Updated:** 2026-04-23

---

## 1. DOCUMENT PURPOSE

This document defines the **complete functional and engineering requirements** for the Alfred Ingestor mini project. It serves two purposes:

1. **Build Gate** — AG reads this at session start and measures every implementation decision against these requirements before declaring a task complete.
2. **QA Audit Baseline** — The existing live system is audited against this document to surface gaps. Gaps become explicit fix tickets.

> **Make.com Boundary Rule (hard):** Make.com handles two async, non-critical notifications only: (1) the scraper scenario — Webhook → Gmail email to host → Supabase upsert of `scraped_markdown` in the scraper's own DB (legacy, kept for visibility). All business logic — deduplication, file fingerprinting, processing routing, status transitions, and writes to the Ingestor Supabase — lives in the FastAPI backends. Make.com must never be on the critical path.

---

## 2. SYSTEM OVERVIEW

The system has two integrated services: the **Scraper** (absorbs the existing standalone scraper project) and the **Ingestor** (processes host-uploaded files). Each produces its own independent markdown document stored in Supabase — `scraped_markdown` (from the Scraper) and `ingested_markdown` (from the Ingestor). These remain separate outputs in this project. Merging them into a unified `master_json` is out of scope — that belongs to Alfred V1 Phase 1 (Merger service).

**Folder structure:**
```
projects/ingestor/
├── backend/        ← Ingestor FastAPI (file processing, deduplication, status)
├── frontend/       ← Flutter Web UI (shared entry point for both flows)
└── scraper/        ← Absorbed Scraper FastAPI (Firecrawl + Gemini structuring)
    ├── main.py
    ├── GEMINI_PROMPT_AIRBNB.md
    └── requirements.txt
```

**Scraper flow:**
1. User pastes Airbnb URL → clicks "Ingest Now"
2. Ingestor backend calls Scraper API `POST /scrape` with the URL
3. Scraper: Firecrawl scrapes listing → Gemini structures output → returns `scraped_markdown`
4. Scraper fires Make.com webhook in background (async) → Gmail notification + legacy DB write (non-critical)
5. Ingestor backend writes `scraped_markdown` to `properties` table in Ingestor Supabase (UPSERT on `airbnb_url`)

**Ingestor flow:**
1. User uploads files (PDF, DOCX, images, audio, spreadsheets) and/or records voice notes
2. "Ingest Now" triggers backend processing per file
3. Each file processed via Claude API → structured markdown appended to `ingested_markdown`
4. File fingerprints (name + byte size) stored for deduplication
5. Final status set to `Ingested` only when all files complete
6. Extracted Knowledge document rendered in UI

**Entry point:** User clicks "Ingest Now" in Flutter Web UI.
**Exit point:** Extracted Knowledge document rendered in UI, `properties` record fully updated in Supabase.

**Scraper API contract (existing, deployed on Render):**
- `POST /scrape` — input: `{ url: string }` — output: `{ status: "success", data: string (structured markdown) }`
- `GET /health` — returns `{ status: "ok" }`
- Env vars required: `FIRECRAWL_API_KEY`, `GEMINI_API_KEY`, `MAKE_WEBHOOK_URL`, `INGESTOR_SUPABASE_URL`, `INGESTOR_SUPABASE_SERVICE_KEY`

---

## 3. FUNCTIONAL REQUIREMENTS

Each requirement has an ID, a clear MUST/MUST NOT statement, and an embedded **Pass Threshold** — the measurable condition AG uses to verify the requirement is met.

---

### 3.1 Property Identity & Deduplication

**REQ-01 — URL as Primary Key**
The system MUST use the Airbnb listing URL as the unique identifier for a property. Submitting the same URL twice MUST NOT create a new Supabase record. The UPSERT is performed by the Scraper on `airbnb_url` column.
> **Pass Threshold:** Submit identical URL twice → only 1 record exists in `properties` table. Second submission updates `scraped_markdown` and `updated_at`, no new row inserted.

**REQ-02 — Nickname Field (Optional)**
The UI MUST provide an optional "Nickname" field for the property. The mandatory "Property Name" field MUST be removed. The official property name MUST be sourced exclusively from the Airbnb listing scrape result.
> **Pass Threshold:** Form renders with Nickname (optional) + Airbnb URL (required) only. Submitting without a nickname succeeds. Official name appears as document title post-ingestion.

**REQ-03 — Official Name as Document Title**
After ingestion, the top of the Extracted Knowledge document MUST display the official property name pulled from the Airbnb listing (`### 🏠 Property Identity → Property Name` field in scraped markdown) as an `h1` title.
> **Pass Threshold:** Extracted Knowledge header = exact listing name from Airbnb (not user-supplied). Verified against 3 different listings.

---

### 3.2 Scraper Integration

**REQ-26 — Scraper Called on Every Ingest**
When the user clicks "Ingest Now" with a valid Airbnb URL, the Ingestor backend MUST call the Scraper API (`POST /scrape`) as the first step, before processing any uploaded files.
> **Pass Threshold:** Click "Ingest Now" → Render logs show scraper call → `scraped_markdown` populated in Supabase before file processing begins.

**REQ-27 — Scraper Supabase Write**
The Scraper MUST write the structured markdown output directly to the Ingestor Supabase `properties` table via UPSERT on `airbnb_url`, setting `scraped_markdown` and `status = 'Scraped'`. This write happens in the Scraper service itself, not in Make.com.
> **Pass Threshold:** Trigger `/scrape` directly → `properties` row exists in Ingestor Supabase with `scraped_markdown` populated. Make.com webhook fires independently in background (Gmail + legacy DB write) without affecting this result.

**REQ-28 — Scraper Failure Handling**
If the Scraper API returns an error or is unreachable, the system MUST surface a clear error in the UI and MUST NOT proceed to file ingestion. The property record MUST NOT be left in a partial state.
> **Pass Threshold:** Simulate scraper failure (invalid URL / Firecrawl error) → UI shows "Scraping failed: [reason]". No `properties` row created. Ingestor does not process uploaded files.

**REQ-29 — Make.com Notification (Async, Non-Critical)**
The Scraper MUST fire the Make.com webhook in background after a successful scrape. This triggers: Gmail notification to host + legacy write to scraper's own Supabase DB. If the webhook fails, the system MUST log the error and continue — this path is never on the critical path.
> **Pass Threshold:** Successful scrape → Gmail notification received within 2 minutes. If `MAKE_WEBHOOK_URL` env var is missing → system logs warning, continues normally, no crash.

---

### 3.2 File Handling — Supported Types

The system MUST support ingestion of the following file types. Each type has its own processing path and pass threshold.

**REQ-04 — PDF**
MUST extract all text content and structure it into the knowledge document.
> **Pass Threshold:** Upload a multi-page PDF with mixed content (text, tables, lists). Extracted Knowledge contains all key information from the document. No truncation on files under 10MB.

**REQ-05 — DOCX**
MUST extract text and preserve heading hierarchy where present.
> **Pass Threshold:** Upload a .docx with headings and bullet points. Extracted Knowledge reflects document structure. Formatting artifacts (e.g., raw XML) MUST NOT appear in output.

**REQ-06 — PNG / JPG / JPEG (Images)**
MUST extract all visible text and information using vision processing (Claude API). Captures access codes, WiFi passwords, hand-written notes, printed instructions.
> **Pass Threshold:** Upload an image of a WiFi card and a printed house rules sheet. Both WiFi password and key house rules appear in Extracted Knowledge.

**REQ-07 — Audio (M4A / MP3 / WAV / OGG)**
MUST transcribe audio and extract property-relevant information.
> **Pass Threshold:** Record a 60-second voice note describing check-in instructions. Extracted Knowledge contains the check-in instructions in structured text. Transcription accuracy ≥ 90% on clear speech.

**REQ-08 — Spreadsheet (XLSX / CSV)**
MUST extract tabular data and represent it in structured form in the knowledge document.
> **Pass Threshold:** Upload a CSV with cleaning schedule and pricing. Both datasets appear in Extracted Knowledge in readable structured format.

**REQ-09 — Unsupported File Types**
The system MUST NOT silently fail on unsupported file types. It MUST display a clear error message to the user identifying the rejected file and the reason.
> **Pass Threshold:** Upload a `.zip` file → UI shows "[filename] — unsupported file type" inline. File is not uploaded to Supabase Storage.

---

### 3.3 File Deduplication

**REQ-10 — Identical File (Same Name + Same Size)**
If a file with identical name AND byte size already exists for this property, the system MUST skip reprocessing and display `"Already in database"` status inline beside the file name.
> **Pass Threshold:** Upload the same PDF twice for the same property. Second upload shows "Already in database". Supabase Storage contains only one copy. `ingested_markdown` unchanged.

**REQ-11 — Updated File (Same Name, Different Size)**
If a file with the same name but different byte size is uploaded, the system MUST reprocess it, replace the previous version in Storage, and display `"File updated in database"` status inline.
> **Pass Threshold:** Upload doc_v1.pdf (50KB), then doc_v2.pdf renamed to same filename (75KB). System re-ingests, Storage reflects new file, UI shows "File updated in database".

**REQ-12 — New File**
If a file with a name not previously associated with this property is uploaded, the system MUST ingest it normally.
> **Pass Threshold:** Upload a new filename → processed without prompt, appears in "Files Ingested" section.

---

### 3.4 Voice Note Handling

**REQ-13 — Pre-Ingestion Visibility**
A recorded voice note MUST appear in the "Files to Ingest" list immediately after recording, before the user clicks "Ingest Now". It MUST be visually consistent with other uploaded files in the list.
> **Pass Threshold:** Record a voice note → file appears in "Files to Ingest" list within 1 second of recording completion, before any ingestion is triggered.

**REQ-14 — Multiple Voice Notes**
The system MUST support recording multiple voice notes in sequence. Each MUST appear in the "Files to Ingest" list as a separate entry with a unique auto-generated filename (e.g., `voice_note_[timestamp].m4a`).
> **Pass Threshold:** Record 3 voice notes → 3 separate entries visible in "Files to Ingest". All 3 processed on "Ingest Now". All 3 appear in "Files Ingested" post-processing.

---

### 3.5 UI State Machine

The file list area MUST operate as a two-state display, not a single flat list.

**REQ-15 — "Files to Ingest" Section**
All files selected or recorded by the user MUST appear under a "Files to Ingest" header before ingestion begins.
> **Pass Threshold:** Add 3 files + 1 voice note → all 4 appear under "Files to Ingest" header, above "Ingest Now" button.

**REQ-16 — "Files Ingested" Section**
After ingestion, each processed file MUST move from "Files to Ingest" to a "Files Ingested" section with its final status label: `Done`, `Already in database`, or `File updated in database`.
> **Pass Threshold:** Ingest 4 files → "Files to Ingest" section empties, "Files Ingested" section shows all 4 with correct status labels.

**REQ-17 — Per-File Processing Status**
Each file in "Files Ingested" MUST display its individual processing status. Status updates MUST be visible in real-time during processing (not only at completion).
> **Pass Threshold:** Ingest 5 files → each file shows a processing indicator as it is being processed, then transitions to final status. Not all files transition simultaneously.

---

### 3.6 Property Hero Image

**REQ-18 — Main Airbnb Image Display**
After the first successful ingestion of a property, the main/hero image from the Airbnb listing MUST be retrieved and displayed in the UI (property card or knowledge document header).
> **Pass Threshold:** Complete first ingestion of a new property → hero image appears in UI within the ingestion result view. Image sourced from Airbnb listing, stored in Supabase Storage under `{property_id}/hero_image`.

---

### 3.7 Backend Processing

**REQ-19 — Idempotent Ingestion Endpoint**
`POST /ingest` MUST be idempotent with respect to property identity. Calling it multiple times with the same URL MUST result in a consistent DB state (one record, updated content).
> **Pass Threshold:** Call `/ingest` 3× with same URL → Supabase shows 1 property record, `updated_at` reflects most recent call, no duplicate rows.

**REQ-20 — Ingestion Lock (Status: Ingesting)**
While a property is being processed, its status MUST be set to `Ingesting`. A second ingestion request for the same property MUST be rejected with a `409 Conflict` response while status is `Ingesting`.
> **Pass Threshold:** Trigger ingestion, immediately trigger again → second request returns `409`. First ingestion completes successfully. Status transitions: `Pending → Ingesting → Ingested`.

**REQ-21 — Atomic Status Transition**
Status MUST only be set to `Ingested` after ALL files in the batch have been processed. Partial completion MUST NOT set final status.
> **Pass Threshold:** Ingest 4 files — simulate failure on file 3. Status remains `Ingesting` (not `Ingested`). Error is surfaced. Files 1, 2, 4 results are preserved.

**REQ-22 — File Fingerprint Storage**
For each ingested file, the system MUST store filename and byte size in Supabase (e.g., `ingested_files` table or JSONB column on `properties`) for deduplication lookups on subsequent ingestions.
> **Pass Threshold:** After ingestion, Supabase contains a record of each file's name and size associated with the property. Re-upload same file → system reads fingerprint and skips without calling Claude API.

---

### 3.8 Extracted Knowledge Output

**REQ-23 — Complete Data Capture (Zero Data Loss)**
The Extracted Knowledge document MUST capture ALL information present in the source documents. Sections are dynamic — determined by what data is actually present, not a fixed template. The prompt (`GEMINI_PROMPT_AIRBNB.md` for scrape output, Claude processing prompt for uploaded files) is the source of truth for output structure. No information from any source document may be omitted or summarized away.
> **Pass Threshold:** Ingest a multi-file batch. Manually verify that every piece of information in the source files appears somewhere in the Extracted Knowledge output. Cross-check 5 specific data points (e.g., WiFi password, check-out time, a specific house rule, host bio, pool access code) against source. All 5 must be present verbatim.

**REQ-24 — Multi-Language Source Handling**
The system MUST correctly process source documents in any language. The Extracted Knowledge document language MUST match the detected primary language of the source material.
> **Pass Threshold:** Upload a Spanish-language PDF → Extracted Knowledge rendered in Spanish. Upload an English PDF alongside it → system handles mixed-language input gracefully (sections attributed to source language or normalized to primary language — consistent behavior required).

**REQ-25 — No Hallucination Policy**
The system MUST NOT generate property information not present in the source documents. If a standard section (e.g., Emergency Contacts) has no source data, it MUST be omitted or marked `"Not provided"` — not filled with placeholder text.
> **Pass Threshold:** Ingest a minimal 1-page PDF. Sections with no matching source data show `"Not provided"`, not AI-generated filler. Verified by comparing source vs. output manually.

---

## 4. ENGINEERING KPIs

These are the measurable performance thresholds the system must meet. Each KPI has a PASS value (acceptable) and a TARGET value (optimal).

| KPI | Metric | PASS | TARGET | Measured By |
|-----|--------|------|--------|-------------|
| **Scrape latency** | Time from `/scrape` call to `scraped_markdown` written in Supabase | < 45s | < 20s | Render logs |
| **End-to-end ingestion time** | Time from "Ingest Now" click to Extracted Knowledge rendered (single PDF, <5MB) | < 60s | < 30s | Stopwatch / Playwright timer |
| **End-to-end ingestion time** | Same, for a 5-file batch (mixed types, <10MB total) | < 120s | < 60s | Playwright timer |
| **Audio transcription latency** | Time to transcribe a 60s voice note | < 30s | < 15s | Measured in backend logs |
| **API error rate** | % of ingestion requests that result in an unhandled 5xx error | < 2% | < 0.5% | Render logs over 20 test runs |
| **Deduplication accuracy** | % of identical file re-uploads correctly identified and skipped | 100% | 100% | Automated test (10 runs) |
| **File type coverage** | % of supported file types that process without error | 100% | 100% | One test file per type |
| **UI state accuracy** | Files correctly moving from "to ingest" → "ingested" with correct status labels | 100% | 100% | Playwright E2E |
| **No duplicate property records** | Same URL submitted N times → exactly 1 DB record | 100% | 100% | Supabase query after 5 submissions |
| **Hero image retrieval** | Hero image present in UI after first ingestion | 100% | 100% | Manual verification (5 listings) |
| **Hallucination rate** | Sections marked "Not provided" vs. AI-invented content on minimal input | 0 hallucinations | 0 hallucinations | Manual audit (5 runs) |

---

## 5. EXPLICIT OUT-OF-SCOPE (MUST NOT)

These items are explicitly excluded from this mini project. AG MUST NOT implement them here — they belong in the full Alfred build.

- MUST NOT implement guest-facing features (chat, messaging, escalation)
- MUST NOT implement conflict detection / merger / vectorization pipeline (Alfred V1 Phase 1 scope)
- MUST NOT integrate WhatsApp, Telegram, or any guest communication channel
- MUST NOT implement multi-host / multi-tenant logic
- MUST NOT store API keys or credentials in source code or Make.com scenario configuration
- MUST NOT implement authentication / authorization beyond what is currently live
- Make.com MUST NOT contain file processing logic, Claude API calls, or deduplication logic

---

## 6. QA AUDIT PLAN

### Skills to invoke (in order)

| Step | Skill | Purpose |
|------|-------|---------|
| 1 | `verification-before-completion` | Validate current live system state against REQ-01 through REQ-25 before any fixes |
| 2 | `systematic-debugging` | Root cause any failing requirements identified in Step 1 |
| 3 | `test-driven-development` | Write failing tests for each gap before implementing the fix |
| 4 | `webapp-testing` | E2E coverage for UI state machine (REQ-15, REQ-16, REQ-17) |
| 5 | `playwright` | Automated E2E test suite for full ingestion flow against all KPIs |
| 6 | `property-based-testing` | Stress test file fingerprinting and deduplication logic (REQ-10, REQ-11, REQ-22) |
| 7 | `requesting-code-review` | Pre-merge checklist before closing any fix branch |
| 8 | `insecure-defaults` | Verify no credentials exposed, no public bucket policies, no key leaks |

### Audit Protocol

1. AG reads this document at session start — before reading CLAUDE.md or CONTEXT.md
2. AG runs `verification-before-completion` against the live system
3. Every failing requirement is logged as a fix ticket with REQ-ID reference
4. Fix tickets are resolved in REQ-ID order (identity/dedup first, then file types, then UI)
5. After all fixes: full Playwright E2E run against all KPIs
6. Session closes only when all KPIs reach PASS threshold

---

## 7. STATUS TRACKING

| REQ-ID | Description | Status | Notes |
|--------|-------------|--------|-------|
| REQ-01 | URL as primary key (UPSERT) | ✅ Built | DB: UNIQUE constraint on airbnb_url; backend: UPSERT on conflict in ingest.py + scraper |
| REQ-02 | Nickname field / remove name field | ✅ Built | ingest_screen.dart: Nickname (Optional) + Airbnb URL * fields; name field removed |
| REQ-03 | Official name as document title | ✅ Built | Parsed from scraped_markdown via regex; displayed as h1 above Extracted Knowledge |
| REQ-04 | PDF ingestion | ✅ Live | Working |
| REQ-05 | DOCX ingestion | ✅ Live | Working |
| REQ-06 | Image ingestion | ✅ Live | Working |
| REQ-07 | Audio ingestion | ✅ Live | Working |
| REQ-08 | Spreadsheet ingestion | ⚠️ Unknown | Not confirmed in spec |
| REQ-09 | Unsupported file type error | ✅ Built | drop_zone.dart: drag rejects unsupported extensions inline; file not uploaded |
| REQ-10 | Identical file deduplication | ✅ Built | hash_guard.py: size-based fingerprint; SSE status "already_in_db"; file_status_list.dart updated |
| REQ-11 | Updated file detection | ✅ Built | hash_guard.py: same name + different size → reprocess; SSE status "file_updated" |
| REQ-12 | New file ingestion | ✅ Live | Working |
| REQ-13 | Voice note pre-ingestion visibility | ✅ Built | voice_recorder.dart: onFileAdded called immediately on stop; ingest_screen.dart: _filesToIngest list |
| REQ-14 | Multiple voice notes | ✅ Built | Each recording → unique timestamp filename → separate _filesToIngest entry |
| REQ-15 | "Files to Ingest" section header | ✅ Built | ingest_screen.dart: _filesToIngest list under "Files to Ingest" header before INGEST NOW |
| REQ-16 | "Files Ingested" section header | ✅ Built | ingest_screen.dart: _fileStatuses list under "Files Ingested" header after ingest |
| REQ-17 | Per-file real-time status | ✅ Built | SSE stream updates each file in _fileStatuses in real-time; spinner during processing |
| REQ-18 | Hero image display | ✅ Built | Backend downloads from Airbnb, stores at {id}/hero_image/main.jpg; frontend signed URL + Image.network |
| REQ-19 | Idempotent endpoint | ✅ Built | get_canonical_property resolves existing row; UPSERT on airbnb_url; no duplicate rows |
| REQ-20 | Ingestion lock (409) | ✅ Built | ingest.py: pre-stream check status == "Ingesting" → 409 Conflict |
| REQ-21 | Atomic status transition | ✅ Built | error_count tracked; "Ingested" only if error_count == 0, else "Ingest_Error" |
| REQ-22 | File fingerprint storage | ✅ Built | file_fingerprints JSONB column; loaded once per ingest; updated after processing |
| REQ-23 | Zero data loss output | ✅ Live | Working — confirmed in screenshot |
| REQ-24 | Multi-language handling | ✅ Live | Confirmed (Spanish detected in screenshot) |
| REQ-25 | No hallucination policy | ⚠️ Unknown | Needs manual audit |
| REQ-26 | Scraper called on every ingest | ✅ Built | ingest.py: POST /scrape before file processing; abort on failure (REQ-28) |
| REQ-27 | Scraper writes to Ingestor Supabase | ✅ Built | scraper/main.py: upsert_to_ingestor_supabase() on airbnb_url with updated_at |
| REQ-28 | Scraper failure handling | ✅ Built | ingest.py: scraper error → SSE error event + abort; no partial property row |
| REQ-29 | Make.com notification (async) | ✅ Live | Background task in scraper; non-critical; MAKE_WEBHOOK_URL missing → logs warning |

---

*This document is the source of truth for the Ingestor mini project. All implementation decisions are measured against it. Update Section 7 status after each audit/fix session.*
