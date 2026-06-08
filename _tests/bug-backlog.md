# Bug Backlog — to convert into regression scenarios

These are bugs reported by the user during triage or general dev. Each entry should be promoted into a proper scenario row in `scenarios.md` during step 3 of the upcoming phase sequence (see `CONTEXT.md` → Upcoming Phases).

Each promoted scenario must include the same fields as other scenarios: `id`, `touches:`, `layer:`, `setup:`, `action:`, expected outcomes, etc. The bug entry below is the rough form; promotion fleshes it out.

---

## Open

### BUG-001: Chat pills overlap UI on property card
- **Reported:** 2026-06-02
- **Severity:** UI / layout
- **Where:** Property card / `PropertyExpandedView` (the card shown on dashboard with chat pills like "Juanito", "Steven", "Sof", "+1 more")
- **Symptoms:**
  - Chat pills are too large for the card width
  - "+N more" pill overlaps the Settings button row at the bottom of the card
  - Pills don't adapt to the size of the property card / viewport
- **Expected:** chat pills should be sized responsively — shrink horizontally on narrow cards, wrap or truncate names, never overlap action buttons
- **Likely touches:**
  - `frontend/lib/widgets/conversation_pill.dart`
  - `frontend/lib/widgets/property_card.dart`
  - `frontend/lib/widgets/property_expanded_view.dart` (if pills are duplicated there)
- **Notes:** screenshot exists in chat history (2026-06-02 triage session); shows "+1 more" pill stacking on top of Settings button row in a green-toned card

---

### BUG-002: Ingest stuck in "Queued" state, dashboard goes empty
- **Reported:** 2026-06-02 (staging URL)
- **Severity:** functional — blocking ingest flow
- **Symptoms:**
  - Filled nickname + Airbnb URL + 5 files (pdf, docx, voice note, jpg, png) + clicked Ingest Now
  - Loading wheel appeared briefly, then "Ingest Now" button became re-clickable but files stayed in "Queued" state
  - Clicking Ingest Now again did nothing
  - Hitting Back → dashboard empty (property not visible)
- **Notes:** scraper-staging was likely cold (502 first request). Need scraper-staging + the-ingestor-staging logs from this attempt. **Worked previously** per user, so a regression suspected.
- **Likely touches:**
  - `backend/routers/ingest.py` (SSE stream handling)
  - `frontend/lib/screens/add_property_screen.dart` (loading state machine)

### BUG-003: Scraping fails with 500 Internal Server Error on prod
- **Reported:** 2026-06-02 (prod URL `alfred-ingestor.vercel.app`)
- **Severity:** functional
- **Symptoms:** ingest attempt failed with `Server error '500 Internal Server Error' for url 'https://scraper-ojux.onrender.com/scrape'`. Status set to `Ingest_Error`. Property still gets created and extracted knowledge is shown — partial success.
- **Notes:** prod scraper returning 500, not 429/502. Need scraper logs from prod (`scraper` service in Render). Could be Firecrawl returning error, Gemini timeout, or scraper code crash.
- **Likely touches:**
  - `scraper/main.py`
  - external: Firecrawl API

### BUG-004: User isolation broken — new account can see other user's property + chats
- **Reported:** 2026-06-02 (prod URL, fresh account `a1test@test.com`)
- **Severity:** CRITICAL — data leak / security
- **Symptoms:**
  - Created brand new account on prod
  - Dashboard initially empty (Welcome screen) — correct
  - Added a new property (Airbnb URL with unique_share_id=0aad1080-...)
  - After ingest, went back to dashboard → saw "Bungalowww" property with 5 chats (Steven, Juanito, Sof, Loki) from the OTHER user's data
- **Possible causes (need investigation):**
  - (a) RLS gap on conversations/messages/guests (already known via G2 scenario)
  - (b) Property deduplication by `airbnb_url` returns the canonical row regardless of who owns it — so two accounts pasting the same URL share a property AND inherit its chats
  - (c) Combination
- **Likely touches:**
  - `backend/services/supabase_client.py` (`get_canonical_property` dedup logic)
  - `backend/routers/ingest.py` (where canonical lookup happens)
  - RLS policies on `properties`, `conversations`, `messages`, `guests` (most are disabled — see memory `project_rls_pending`)

### BUG-006: Scraper crashes calling retired Gemini preview model
- **Reported:** 2026-06-02
- **Severity:** functional — blocking all ingests
- **Symptoms:** scraper-staging `/scrape` returns 500. Render logs show only "Starting scrape for URL: ..." then 500 with no traceback (HTTPException detail goes to response body, not stdout).
- **Root cause:** `scraper/main.py` line 116 called `model="gemini-3-flash-preview"`. Google retired or renamed the preview, causing every Gemini call from the scraper to raise. Exception caught at line 127 and rethrown as HTTPException 500 — opaque to callers.
- **Why prod appeared fine:** prod was last successfully ingested before the retirement; user assumed prod still worked without retesting. Prod is/was actually broken too.
- **Fixed in commit:** *(commit hash filled in when this lands)*
  - Scraper model changed to `gemini-2.5-flash` (stable, GA, free-tier accessible, accurate enough for one-shot structured markdown generation)
  - Added `print(f"ERROR: ...")` lines before the HTTPException raises so future scraper failures appear in stdout / Render logs immediately
- **Regression scenario:** B0 (scraper-base-01) added to `scenarios.md` — runs as Layer 1 against `scraper-staging-bn7w.onrender.com/scrape`. Any future model retirement / scraper crash shows up here before it breaks the whole ingest flow.

### BUG-005: Staging deployment renders differently from prod
- **Reported:** 2026-06-02
- **Severity:** UI / unknown
- **Symptoms:** user observes "everything is bigger" on staging URL vs prod URL. Same code base on both.
- **Possible causes:**
  - Browser zoom level differs between tabs/windows
  - Browser cache showing stale prod CSS
  - Vercel preview deployment bundles differently than production
  - Some env-var-driven layout difference
- **First diagnostic step:** open both URLs in incognito at same zoom + check identical bundle hash

---

## Promoted (already in scenarios.md)

*(none yet — entries move here once they have a corresponding scenario row)*
