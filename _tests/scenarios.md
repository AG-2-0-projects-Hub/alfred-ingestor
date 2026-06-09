# Alfred QA Scenario Matrix

**Created:** 2026-06-01
**Status:** v1 draft — awaiting user review
**Architecture reference:** `_Context/plans/alfred-phase6-perspective-parity-and-testing.md`

This is the **living spec** for every meaningful user flow in Alfred. Each scenario is a row that the QA runner can execute against staging. Scenarios are the source of truth — code that contradicts a scenario is a bug.

---

## How to use this file

### Adding a new scenario (TDD-aligned)
When you design a new feature, **add the scenario row first** (before code). The scenario becomes the spec — implementation must make it pass.

### Updating an existing scenario
When you change behavior, update the corresponding row in the same PR as the code change. The `touches:` list is how `qa-changed-since` knows which scenarios to re-run.

### Reporting a bug
When a bug surfaces, **add a regression scenario row before fixing.** The scenario describes the broken behavior + expected fix. After fix, the scenario lives forever as a guardrail.

### Scenario format

```markdown
## Scenario: <short imperative name>
id: <area>-<feature>-<seq>     # stable identifier, never reuse
touches:                        # files this scenario depends on
  - path/to/file.ext
layer: 1 | 2 | 4                # 1=Claude tests, 2=Playwright, 4=user manual
runs_on: [smart, full]          # which cadences include it
setup: <starting state>
action: <what triggers the test>
host_expected: <what host sees>
guest_expected: <what guest sees>
dashboard_expected: <what dashboard shows>
db_expected: <DB state to assert via supabase MCP>
last_tested: null
status: pending | passing | failing | skipped
```

Not all fields are required for every scenario — drop irrelevant ones.

---

## A. Authentication

### A1. Host signup creates account
- **id:** auth-signup-01
- **touches:**
  - `frontend/lib/screens/auth_screen.dart`
  - `backend/main.py` *(if backend handles signup; otherwise Supabase Auth direct)*
- **layer:** 2
- **runs_on:** [smart, full]
- **setup:** anonymous browser session, fresh email
- **action:** open `/auth`, fill email + password, click "Sign Up"
- **host_expected:** redirected to dashboard, session token set in localStorage
- **db_expected:** new row in `auth.users` with the email
- **last_tested:** 2026-06-02 (manual verification by user)
- **status:** passing

### A2. Host login with valid credentials
- **id:** auth-login-01
- **touches:** `frontend/lib/screens/auth_screen.dart`
- **layer:** 2
- **setup:** existing test account
- **action:** enter credentials, click "Log In"
- **host_expected:** dashboard loads with this account's properties only
- **last_tested:** 2026-06-09 (automated Playwright — PASS)
- **status:** passing

### A3. Host login with invalid credentials
- **id:** auth-login-02
- **touches:** `frontend/lib/screens/auth_screen.dart`
- **layer:** 2
- **setup:** anonymous session
- **action:** wrong password
- **host_expected:** error message shown, no redirect, no session set
- **last_tested:** 2026-06-09 (automated Playwright — FAIL: Gemini judge API returned 503 "high demand", transient; not a code failure — mark skipped, re-run when API available)
- **status:** skipped

### A4. Host logout clears session
- **id:** auth-logout-01
- **touches:** `frontend/lib/screens/auth_screen.dart`, `frontend/lib/screens/dashboard_screen.dart`
- **layer:** 2
- **setup:** logged-in host on dashboard
- **action:** click logout
- **host_expected:** redirected to auth screen, localStorage cleared, refresh does not restore session
- **last_tested:** 2026-06-09 (automated Playwright — PASS; pre-logout, post-logout, and post-refresh screenshots all judged pass)
- **status:** passing

---

## B. Ingestor (property creation)

### B1. Ingest new Airbnb URL with files
- **id:** ingest-new-01
- **touches:**
  - `backend/routers/ingest.py`
  - `backend/services/supabase_client.py`
  - `backend/services/file_processor.py`
  - `backend/services/hash_guard.py`
  - `scraper/main.py`
  - `frontend/lib/screens/add_property_screen.dart`
  - `frontend/lib/screens/ingest_screen.dart`
  - `frontend/lib/widgets/drop_zone.dart`
- **layer:** 2
- **runs_on:** [smart, full]
- **setup:** logged-in host, no existing property with this URL. Real Firecrawl call against a known stable test Airbnb URL — user has sufficient credits and prefers real scrapes over mocks.
- **action:** paste known test Airbnb URL, drop 1 PDF + 1 image, click "Ingest Now"
- **host_expected:** status transitions Pending → Ingesting → Ingested, hero image displayed, official property name shown
- **db_expected:** new row in `properties` with the airbnb_url, status='Ingested', file_fingerprints populated, scraped_markdown populated
- **status:** pending

### B2. Re-ingest same URL deduplicates property
- **id:** ingest-dedup-01
- **touches:** `backend/routers/ingest.py`, `backend/services/supabase_client.py`
- **layer:** 1 + 2
- **setup:** property already ingested for URL X (from B1)
- **action:** paste same URL X, add one new file, click "Ingest Now"
- **host_expected:** existing property card updated (same id), new file appears in ingested list, status='Ingested'
- **db_expected:** `properties` row count unchanged for URL X (no duplicate row), `file_fingerprints` now contains all files
- **status:** pending

### B3. Concurrent ingest returns 409
- **id:** ingest-lock-01
- **touches:** `backend/routers/ingest.py`
- **layer:** 1
- **setup:** property X currently has status='Ingesting'
- **action:** POST `/ingest` for same property X
- **host_expected:** N/A (backend test)
- **db_expected:** response is 409 Conflict, property status unchanged
- **last_tested:** 2026-06-08
- **status:** passing

### B4. File hash dedup skips identical files
- **id:** ingest-hash-01
- **touches:** `backend/services/hash_guard.py`
- **layer:** 1
- **setup:** property X has file F1 (size 100KB) in file_fingerprints
- **action:** re-upload same file F1 (size 100KB) via ingest
- **db_expected:** `file_fingerprints` unchanged, file_processor logs "skipped (hash match)"
- **last_tested:** 2026-06-08
- **status:** passing

### B5. Modified file re-upload is processed
- **id:** ingest-hash-02
- **touches:** `backend/services/hash_guard.py`
- **layer:** 1
- **setup:** property X has file F1 (size 100KB) in file_fingerprints
- **action:** upload file F1 with same name but size 120KB (e.g., edited version)
- **db_expected:** file_processor processes the file, `file_fingerprints[F1]` updated to 120
- **last_tested:** 2026-06-08
- **status:** passing

### B6. Invalid Airbnb URL returns graceful error
- **id:** ingest-invalid-url-01
- **touches:** `backend/routers/ingest.py`, `scraper/main.py`
- **layer:** 2
- **setup:** logged-in host
- **action:** paste a non-Airbnb URL (e.g., `https://example.com`), click "Ingest Now"
- **host_expected:** error message displayed, status returns to "Pending" (no half-created property)
- **db_expected:** no orphan `properties` row left in non-terminal state
- **last_tested:** 2026-06-09 (automated Playwright — FAIL: nav judge did not reach Add Property form; click at `DASHBOARD.addPropertyX=0.5, addPropertyY=0.58` appears to miss the "Add Your First Property" button — coordinate mismatch, not a code bug)
- **status:** skipped
- **layer4_needed:** Open staging at 1440×900, note the exact pixel Y of the "Add Your First Property" button, compute Y/900 fraction, update `DASHBOARD.addPropertyY` in `_tests/runner/lib/playwright-helpers.ts`, then re-run `npm run full`.

### B7. Unsupported file dropped is rejected
- **id:** ingest-bad-file-01
- **touches:** `frontend/lib/widgets/drop_zone.dart`
- **layer:** 2
- **setup:** logged-in host on add-property screen
- **action:** drag a `.exe` file onto drop zone
- **host_expected:** inline error message shown, file not added to upload list
- **last_tested:** 2026-06-09 (automated Playwright — FAIL: same navigation failure as B6 — `DASHBOARD.addPropertyY=0.58` missed the button; coordinate mismatch, not a code bug)
- **status:** skipped
- **layer4_needed:** Same calibration as B6 — fix `DASHBOARD.addPropertyY` in playwright-helpers.ts and re-run.

### B8. Voice note appears in "Files to Ingest" immediately
- **id:** ingest-voice-01
- **touches:** `frontend/lib/widgets/voice_recorder.dart`, `frontend/lib/screens/ingest_screen.dart`
- **layer:** 2
- **setup:** logged-in host on add-property screen
- **action:** record a 5-second voice note, stop recording
- **host_expected:** voice note appears in the "Files to Ingest" list before "Ingest Now" is clicked
- **status:** pending

### B0. Scraper /scrape returns 200 + structured markdown for known URL
- **id:** scraper-base-01
- **touches:**
  - `scraper/main.py`
- **layer:** 1
- **runs_on:** [smart, full]
- **setup:** known stable test Airbnb URL (e.g. an existing Dos Rios listing URL); FIRECRAWL_API_KEY + GEMINI_API_KEY configured on the scraper service
- **action:** `POST https://scraper-staging-bn7w.onrender.com/scrape` with body `{"url": "<test_url>"}`
- **db_expected:** HTTP 200, response body has `{"status": "success", "data": "<non-empty structured markdown>"}`
- **why this is in the matrix:** regression guardrail for the 2026-06-02 incident (BUG-006: Gemini preview model `gemini-3-flash-preview` was retired, scraper crashed on every call). Any future preview-model retirement or model name change shows up here before it breaks the whole ingest flow.
- **last_tested:** 2026-06-08
- **status:** passing

### B9. Generate guest link creates a new guest record
- **id:** ingest-guest-link-01
- **touches:**
  - `frontend/lib/widgets/generate_guest_link_dialog.dart`
  - `frontend/lib/widgets/property_expanded_view.dart`
  - `backend/services/supabase_client.py`
- **layer:** 2
- **setup:** logged-in host with property X ingested
- **action:** open property X expanded view → click "Generate Guest Link" → fill guest name + booking id → submit
- **host_expected:** new guest tile appears in property's guest list, guest_chat_url shown/copyable
- **db_expected:** new row in `guests` with property_id=X, unique booking_id, guest_chat_url + host_chat_url populated
- **status:** pending

---

## C. Chat lifecycle (host + guest perspectives)

### C1. Guest sends benign question → autopilot reply
- **id:** chat-benign-01
- **touches:**
  - `backend/routers/messages.py`
  - `backend/services/gemini_messenger.py`
  - `frontend/lib/screens/chat_screen.dart`
- **layer:** 2
- **runs_on:** [smart, full]
- **setup:** property X exists, guest G with valid chat URL, conversation in autopilot mode, host offline. Seed via Supabase MCP: insert empty conversation with mode='autopilot'.
- **action:** guest sends "what time is checkout?"
- **guest_expected:** guest message bubble (plain), AI reply bubble appears within 10s with checkout info
- **host_expected:** in dashboard chat preview, both messages visible, no escalation marker
- **db_expected:** 2 new `messages` rows (sender_type='guest', 'ai'), conversation.mode='autopilot', requires_attention=false
- **status:** pending

### C2. Guest asks about house-rule violation → graceful decline
- **id:** chat-house-rule-01
- **touches:** `backend/services/gemini_messenger.py`
- **layer:** 2
- **setup:** property X has "no pets" rule in master_json. Conversation in autopilot.
- **action:** guest sends "can I bring my dog?"
- **guest_expected:** AI declines politely citing house rules, no escalation
- **db_expected:** conversation.mode='autopilot' (no flip to intervene), no requires_attention=true
- **status:** pending

### C3. Emergency trigger escalates conversation
- **id:** chat-emergency-01
- **touches:**
  - `backend/routers/messages.py`
  - `backend/services/gemini_messenger.py`
  - `frontend/lib/screens/chat_screen.dart`
  - `frontend/lib/utils/chat_system_messages.dart`
  - `frontend/lib/widgets/chat_live_dialog.dart`
  - `frontend/lib/services/push_notification_service.dart`
- **layer:** 2
- **runs_on:** [smart, full]
- **setup:** property X, guest G, conversation in autopilot, host has browser open on dashboard with notifications permission granted
- **action:** guest sends "the smoke alarm is going off and I can smell smoke"
- **guest_expected:** orange banner "host is now attending" + system message __SYS_INTERVENE__ rendered via `ChatSystemMessages.formatForGuest(content, hostName: ...)` into the host's name
- **host_expected:** red emergency bubble in chat dialog, system message rendered via `formatForHost(content, guestName: ...)`, web push notification received with payload referencing the conversation id
- **dashboard_expected:** property tile pill turns red, conversation list item bumps to top, requires_attention indicator visible
- **db_expected:** conversation.mode='intervene', requires_attention=true, escalation_reason populated, new system message row with content='__SYS_INTERVENE__'
- **status:** pending

### C4. Host sends message in intervene mode
- **id:** chat-host-reply-01
- **touches:** `backend/routers/messages.py`, `frontend/lib/widgets/chat_live_dialog.dart`
- **layer:** 2
- **setup:** conversation in intervene mode (carry over from C3, or seed via MCP)
- **action:** host types "I'm calling the fire department now" in dialog and sends
- **guest_expected:** host message bubble appears in real-time
- **host_expected:** message confirmed sent, no banner change
- **db_expected:** new `messages` row with sender_type='host', AI does not auto-reply on top
- **status:** pending

### C5. Host resolves issue → conversation returns to autopilot
- **id:** chat-resolve-01
- **touches:**
  - `backend/routers/messages.py`
  - `frontend/lib/widgets/chat_live_dialog.dart`
  - `frontend/lib/widgets/property_expanded_view.dart`
  - `frontend/lib/utils/chat_system_messages.dart`
- **layer:** 2
- **setup:** conversation in intervene mode with escalated messages
- **action:** host clicks "Resolve" in dialog
- **guest_expected:** orange banner disappears, __SYS_RESOLVED__ system message rendered for guest, escalated bubbles flip to resolved color
- **host_expected:** dialog closes (or shows resolved state), bubbles flip to resolved color
- **dashboard_expected:** property tile pill returns to neutral, conversation no longer bumped to top of requires_attention list
- **db_expected:** conversation.mode='autopilot', requires_attention=false, escalated messages' resolution_status='resolved'
- **status:** pending

### C6. System message markers render correctly per viewer
- **id:** chat-sys-markers-01
- **touches:** `frontend/lib/utils/chat_system_messages.dart`
- **layer:** 1
- **setup:** N/A (pure unit test)
- **action:** call `ChatSystemMessages.formatForGuest('__SYS_INTERVENE__', hostName: 'Maria')` and `.formatForHost(..., guestName: 'Alex')`
- **db_expected:** guest version contains "Maria is now attending" or equivalent; host version contains "Alex" reference; legacy plain-text messages render verbatim
- **last_tested:** 2026-06-09 (automated flutter test — PASS)
- **status:** passing

### C7. Guest sees only their conversation, not others'
- **id:** chat-isolation-01
- **touches:** `frontend/lib/screens/chat_screen.dart`, RLS policies on `conversations` and `messages`
- **layer:** 2
- **setup:** property X has 2 guests, G1 and G2, with separate booking_ids and chat URLs. Both have message history.
- **action:** open G1's chat URL in browser, inspect network and rendered messages
- **guest_expected:** only G1's conversation visible; attempting to query G2's conversation_id via Supabase REST returns no rows
- **status:** pending — **will fail until RLS policies are added (see project_rls_pending memory)**

---

## D. Dashboard real-time

### D1. New guest message bumps conversation to top
- **id:** dash-bump-01
- **touches:**
  - `frontend/lib/screens/dashboard_screen.dart`
  - `frontend/lib/widgets/property_expanded_view.dart`
  - `frontend/lib/widgets/conversation_pill.dart`
- **layer:** 2
- **setup:** host on dashboard with property X expanded, 3 conversations visible, oldest at top
- **action:** seed a new message in conversation #3 via Supabase MCP (sender_type='guest')
- **host_expected:** conversation #3 moves to top of list within 5s (realtime stream) OR within 10s (safety-net timer if stream drops)
- **status:** pending

### D2. Escalation reflects on property pill across open dashboards
- **id:** dash-pill-escalation-01
- **touches:** `frontend/lib/widgets/property_card.dart`, `frontend/lib/widgets/conversation_pill.dart`
- **layer:** 2
- **setup:** host has dashboard open. Two browser contexts: dashboard + a separate process triggering chat.
- **action:** trigger emergency message in guest's chat (as in C3)
- **dashboard_expected:** property X pill turns red within 10s, requires_attention badge appears
- **status:** pending

### D3. Resolution returns pill to neutral
- **id:** dash-pill-resolve-01
- **touches:** `frontend/lib/widgets/property_card.dart`, `frontend/lib/widgets/conversation_pill.dart`
- **layer:** 2
- **setup:** property X has an active intervene-mode conversation, dashboard open
- **action:** host clicks Resolve (or trigger via Supabase MCP update)
- **dashboard_expected:** pill returns to neutral within 10s
- **status:** pending

### D4. Stream-drop safety-net timer catches missed update
- **id:** dash-streamdrop-01
- **touches:** `frontend/lib/widgets/property_expanded_view.dart`, `frontend/lib/screens/dashboard_screen.dart`
- **layer:** 2
- **setup:** host on dashboard. Simulate Supabase realtime stream drop (e.g., close websocket via DevTools).
- **action:** seed an update via Supabase MCP that would normally arrive via stream
- **host_expected:** dashboard catches the update via safety-net timer within 10s, even with realtime stream broken
- **status:** pending

---

## E. Multi-property

### E1. Host with multiple properties sees scoped conversation lists
- **id:** multi-scope-01
- **touches:** `frontend/lib/screens/dashboard_screen.dart`, `frontend/lib/widgets/property_card.dart`
- **layer:** 2
- **setup:** host owns properties X, Y, Z (3 properties seeded via MCP), each with their own conversations
- **action:** expand X, then Y, then Z
- **host_expected:** each property's expanded view shows only its own conversations, no bleed
- **db_expected:** queries filter correctly by property_id
- **status:** pending

### E2. Switching property preserves no state from previous
- **id:** multi-switch-01
- **touches:** `frontend/lib/widgets/property_expanded_view.dart`
- **layer:** 2
- **setup:** as E1
- **action:** expand X, scroll deep into conversation list, expand Y
- **host_expected:** Y's view starts fresh (not scrolled into X's position); no X messages visible while viewing Y
- **status:** pending

---

## F. Theme

### F1. Theme toggle applies across all surfaces
- **id:** theme-toggle-01
- **touches:** `frontend/lib/theme/theme_controller.dart`, `frontend/lib/theme/app_theme.dart`
- **layer:** 2
- **setup:** host logged in, app in light mode
- **action:** click theme toggle
- **host_expected:** all surfaces switch to dark within 1s — dashboard, chat live dialog, property expanded view, popups, system message rendering. No mixed-mode flicker.
- **last_tested:** 2026-06-02 (manual verification by user)
- **status:** passing

---

## G. Security / RLS (will fail until RLS policies added)

### G1. Anon key cannot read other hosts' properties
- **id:** rls-property-isolation-01
- **touches:** RLS policy on `properties` table
- **layer:** 1
- **setup:** properties owned by host_a and host_b exist
- **action:** as host_a's session, query `SELECT * FROM properties` via Supabase REST
- **db_expected:** only host_a's properties returned; host_b's are filtered out
- **last_tested:** 2026-06-08
- **status:** passing

### G2. Anon key cannot read other guests' messages
- **id:** rls-message-isolation-01
- **touches:** RLS policy on `messages` and `conversations`
- **layer:** 1
- **setup:** conversations C1 (booking B1) and C2 (booking B2), each with messages
- **action:** as B1's anon session, attempt `SELECT * FROM messages WHERE conversation_id = '<C2.id>'`
- **db_expected:** zero rows returned
- **last_tested:** 2026-06-09 (automated Supabase query — FAIL: anon read 50 rows, RLS not enforced — intentional pre-beta blocker)
- **status:** failing

### G3. Anon key cannot escalate writes to system messages
- **id:** rls-write-isolation-01
- **touches:** RLS policy on `messages`
- **layer:** 1
- **setup:** valid guest session for booking B1
- **action:** attempt to INSERT a message with sender_type='system' or sender_type='host' (impersonation)
- **db_expected:** insert denied by RLS policy
- **last_tested:** 2026-06-08
- **status:** failing

---

## H. Push notifications (web only)

### H1. Host receives web push on escalation
- **id:** push-escalation-01
- **touches:** `frontend/lib/services/push_notification_service.dart`, `backend/services/gemini_messenger.py`
- **layer:** 2
- **setup:** host has granted notification permission in browser. Dashboard backgrounded.
- **action:** guest sends emergency message (as in C3)
- **host_expected:** browser push notification fires with title referencing the property and a click-through that opens the conversation. Payload includes conversation_id and property_id.
- **status:** pending

---

## I. Exploration anomalies (populated by Layer 3 chaos lane)

This section is populated by the Gemini Exploration Agent when it finds anomalies during weekly chaos runs. Each anomaly becomes a candidate scenario for review and possible promotion to A–H above.

*(none yet)*

---

## Index summary

| Area | Scenarios | Layer 1 | Layer 2 | Layer 4 |
|---|---|---|---|---|
| A. Auth | 4 | — | 4 | — |
| B. Ingestor | 10 | 4 | 6 | — |
| C. Chat | 7 | 1 | 6 | — |
| D. Dashboard | 4 | — | 4 | — |
| E. Multi-property | 2 | — | 2 | — |
| F. Theme | 1 | — | 1 | — |
| G. RLS | 3 | 3 | — | — |
| H. Push | 1 | — | 1 | — |
| **Total** | **32** | **8** | **24** | **0** |

---

## Pending intake

Lightweight queue. Each row is a fix or group of related fixes on the same flow.
**Before next `staging → main` merge:** group by flow, promote to a proper scenario in the A–H sections above, then delete the row.

| Date | Commit(s) | Flow | What to assert | Group with |
|---|---|---|---|---|
| 2026-06-08 | `4336ebd` + uncommitted `add_property_screen.dart` | Add-property — completion popup lifecycle | (1) After ingest completes: no popup shown, only inline panel + MERGE NOW button. (2) After no-conflict merge → status=`Merged`: "Alfred is now trained" popup appears, single "Back to Dashboard" button. (3) After conflict-resolved flow → status=`Trained`: same popup appears. | — |
| 2026-06-08 | `feaf8fd` | Merge / edit-property UX | (1) Merge request does not time out before 120 s. (2) On `edit_property_screen`: conflict questionnaire section renders above JSON viewer. (3) Status badge on submit transitions correctly. (4) Resolved status surfaces in UI after merge completes. | — |
| 2026-06-08 | `0f019f2` | Ingest error surfacing | Backend errors during ingest are shown inline to the user (not silently dropped); upload queue is preserved on failure so user can retry. | Add-property — completion popup lifecycle |
| 2026-06-08 | `1f266ea` | Property dedup / ownership | Re-ingesting an existing URL under the same owner updates the existing row (no duplicate). Re-ingesting the same URL under a different owner creates a separate row. `owner_id` is never overwritten on upsert. | — |
| 2026-06-08 | `2a75a4e` | Scraper model | Scraper does not crash when called; structured markdown returned. (Already covered by B0 — **skip**, no new scenario needed.) | — |
| 2026-06-08 | `5626f1f` | Scraper health endpoint | `HEAD /health` on staging scraper returns 200 (not 405). (Lightweight extension of B0 — **merge into B0** when promoting.) | B0 |
| 2026-06-09 | `1dded18` | Guest chat — display & system messages | (1) Guest chat header shows the official Airbnb listing name (from `master_json.property_identity`, fallback chain → nickname) as a prominent header with an "Alfred · Concierge" sub-line. (2) Consecutive identical system markers render only once (no double "You are now speaking with …"). (3) A sentence-like or >40-char host name renders as "the host" instead of leaking extraction noise into the banner. | — |
| 2026-06-09 | `1dded18` | Ingest extraction quality (merge prompt) | New merges store the host display name only in `host_profile.name` (no sentences/instructions) and always expose the listing title at `property_identity.property_name`. NOTE: existing rows need re-ingestion to clean stored values. | Guest chat — display & system messages |
| 2026-06-09 | `1dded18` | Add-property — duplicate file in queue | Dropping/selecting a file whose name is already in the ingest queue is rejected with an inline "— already in the queue" message and is NOT re-uploaded (previously left a duplicate row stuck on "processing" forever). | — |
| 2026-06-09 | `1dded18` | Add-property — completion popup contrast | Ingested / conflict / trained completion popups use an opaque surface so text stays readable over the dimmed barrier (no dark bleed-through). | Add-property — completion popup lifecycle |
| 2026-06-09 | `1dded18` | Conflict resolution — auto-apply | Submitting conflict resolutions applies the knowledge update automatically and shows the completion popup directly; the intermediate "Update Knowledge" button is removed. | — |

---

## To do (out of scope for v1 draft)

- **Mobile breakpoint scenarios** — deferred to next phase
- **Native iOS/Android push** — deferred to next phase
- **Make.com webhook scenarios** — depends on what they end up doing
- **Conflict resolution / merge flows** — touches `backend/routers/merge_resolve.py`, `backend/services/gemini_merge_resolve.py`, `frontend/lib/widgets/conflict_questionnaire.dart`. Add when that feature is in active use.
- **Archived chats flow** — touches `frontend/lib/widgets/archived_chats_dialog.dart`
- **Setup status banner** — touches `frontend/lib/widgets/setup_status_banner.dart`, `frontend/lib/utils/setup_status.dart`
- **Inactivity wrapper** — touches `frontend/lib/widgets/inactivity_wrapper.dart`
- **Host panel** — touches `frontend/lib/screens/host_panel_screen.dart`

When you review this draft, flag any of the above you want included in v1, plus anything else I missed.
