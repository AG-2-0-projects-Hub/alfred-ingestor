# Session Context
**Created:** 2026-04-14
**Last Session:** 2026-06-09 (staging merged to main via PR #1 — all 10 commits now on prod; Layer 1 QA done; Layer 2 runners written; QA workflow codified — see `_Context/session-digest.md`)
**Prior Session:** 2026-06-02 (Phase 6 QA + multi-tenancy fixes + merge-flow UX — staging only, 6 commits ahead of `main`)
**Prior Sessions:** 2026-05-28 Commit 4 `40453c9` + Commit 5 `c80a84c` (three-layer real-time)
**Prior Session:** 2026-05-15 (Phase 5 shipped — design token migration `d432f22`, P0 `ead7512`, P1 `e7295d9`, P2 `d8c20c1`)

---

## Live URLs
| Service | Prod | Staging |
|---|---|---|
| Backend | https://the-ingestor.onrender.com | https://the-ingestor-staging.onrender.com |
| Scraper | https://scraper-ojux.onrender.com | https://scraper-staging-bn7w.onrender.com |
| Frontend | https://alfred-ingestor.vercel.app | https://alfred-ingestor-git-staging-sanslighthouse-6079s-projects.vercel.app |
| GitHub | https://github.com/AG-2-0-projects-Hub/alfred-ingestor | (branch `staging`) |
| Auto-deploy | Render + Vercel on push to `main` | Render + Vercel on push to `staging` (intermittent — ISSUE-C, manual trigger sometimes needed) |

## Supabase Project
| Key | Value |
|---|---|
| MCP name | `supabase-the-ingestor` |
| project_ref | `gcxxilzfhwlsjcvtpsvj` |
| Project URL | `https://gcxxilzfhwlsjcvtpsvj.supabase.co` |
| Anon key | in `frontend/.env` |
| Service role key | in `backend/.env` |
| Bucket | `Property_assets` (private) |

### RLS (enabled 2026-06-10 — shared prod+staging DB)
- `properties`: `owner_only` (ALL, `owner_id = auth.uid()`) — pre-existing.
- `guests` / `conversations` / `messages`: RLS ON. Host SELECT via property ownership; host INSERT messages + UPDATE conversations (take-over/resolve markers + mode) via ownership; guest SELECT + guest-only INSERT scoped to `auth.jwt()->>'booking_id'`.
- `scrape_jobs`: RLS ON, no policies (service-role only).
- **Guest auth = booking-scoped JWT.** Backend `POST /api/guest-token` mints a short-lived (24h) JWT with `role=anon` + `booking_id` claim, signed with the Supabase JWT secret. Guest Flutter client uses it via a dedicated `SupabaseClient(accessToken: …)` (chat_screen.dart). Bare anon key (no claim) now gets 0 rows.
- **⚠️ REQUIRED env var:** `SUPABASE_JWT_SECRET` must be set on every backend deploy (Render staging `the-ingestor-staging` AND prod `the-ingestor`). Value = Supabase dashboard → Settings → API → JWT Secret. Without it `/api/guest-token` 500s and guest chat breaks.
- Backend uses the service-role key (bypasses RLS), so ingest/merge/host-send/resolve are unaffected.

## Render Monitoring
- UptimeRobot pings every 5 minutes (keeps Render free-tier instances warm — 15-min spin-down otherwise):
  - `https://the-ingestor.onrender.com/health` (prod backend)
  - `https://scraper-staging-bn7w.onrender.com/health` (staging scraper — added 2026-06-02)
  - Prod scraper covered by its own existing monitor

---

## Stack
- **Backend:** FastAPI + uvicorn, Python 3.14 (Render), deployed on Render free tier
- **Frontend:** Flutter web, deployed on Vercel
- **AI:** google-genai SDK, model `gemini-2.5-pro`
- **Storage/DB:** Supabase (Storage + Postgres)

---

## Session 2026-06-02 — Phase 6 rollout + multi-tenancy + merge UX (staging, 6 commits ahead of `main`)

Full handoff lives in `_Context/session-digest-2026-06-02.md` (gitignored). One-line per commit:

| Commit | Subject |
|---|---|
| `67a633b` | docs: add QA system usage section to QUICKSTART |
| `fbda872` | feat(qa): Phase 6 QA system foundation (scenarios.md, TS runner, smoke tests) |
| `1f266ea` | fix(security): scope property dedup to owner + freeze owner_id on upsert |
| `0f019f2` | fix(ingest): surface backend errors to user + preserve queue on failure |
| `2a75a4e` | fix(scraper): switch from retired gemini-3-flash-preview to gemini-2.5-flash |
| `feaf8fd` | fix(merge-flow): bump timeout to 120s, surface resolved status, reorder UI |

DB migration (applied via Supabase MCP, not in git, shared prod+staging DB): `properties.airbnb_url` global UNIQUE → compound `UNIQUE (airbnb_url, owner_id)` — enables multi-tenancy. Safe (only loosens).

Two infra fixes today (no code): paid the overdue GCP bill on the scraper-staging Gemini project; added scraper-staging to UptimeRobot.

**Pending on `main`:** all 6 commits above. Open staging→main PR once user verifies the merge-flow UX on the staging Vercel rebuild.

---

## Upcoming Phases (sequenced, as of 2026-06-08)

Phase 6 QA system operational. Layer 1 done. Layer 2 runners written. Next sequence:

1. **Run Layer 2 full suite** — `cd _tests/runner && npm run full` — verify A3/A4/B6/B7 pass; tune coordinates if needed (Flutter CanvasKit clicks are coordinate-based).
2. **Promote pending-intake entries** — `_tests/scenarios.md` has 4 entries in the pending-intake table that become proper scenarios before staging→main merge.
3. **Merge staging → main** — 10 commits ready. Open PR, self-merge. Triggers prod deploy.
4. **ISSUE-B (Delete FK)** — `ON DELETE CASCADE` on `guests.property_id`, `conversations.property_id`, `messages.conversation_id` — apply via Supabase MCP.
5. **ISSUE-C (Vercel auto-deploy)** — investigate Vercel webhook delivery; for now manually trigger staging redeployment after every frontend push.
6. **RLS policy design** — see memory `project_rls_pending`. Tables: `scrape_jobs`, `guests`, `conversations`, `messages`. G2/G3 are the failing-expected guardrails that enforce this gets done before beta.
7. **Mobile UI optimization** — functionality works, presentation has known issues on small screens.

After step 7: beta launch prep (split staging↔prod URLs, DB reset, Cloud Run migration per memory `project_cloud_run_migration`).

---

## Current App State (as of 2026-05-15)

### What is fully working
- Auth (login/signup, email confirmations disabled)
- Dashboard (property grid, responsive, glassmorphism design, real-time via Supabase stream)
- Property ingestion (SSE stream, file upload to Supabase, Gemini processing)
- Guest link generation (slug-based booking ID)
- Host panel (per-property conversation list)
- Property detail drawer (4 tabs: Overview / Files / Knowledge / Resolve)
- Edit property (per-file delete + re-ingest)
- Archived chats dialog
- **Phase 4 (2026-05-15):** Dual-theme toggle (Daylight/Midnight), `ThemeController` + `shared_preferences` persistence, `AppPalette` ThemeExtension, `InactivityWrapper` (1h auto-logout), `SetupStatusBanner` on drawer + edit property, `ConversationPill` replacing `_ConvPreviewRow`, `PropertyExpandedView` modal, `FileThumbnail` widget, `relativeTime` util, optimistic send in ChatLive, markdown styleSheet contrast fix, JSON copy button, clickable Airbnb URLs, real-time dashboard subscriptions, theme toggle in AppBar. **Deployed on Vercel** (commit `2c7d1e4` after build-fix for `const`/`context.palette` violations).
- **Phase 4.5 (2026-05-15):** In-screen `ChatLiveDialog` (replaces full-page nav from conversation pills + push-notification clicks) + browser push notifications via Web Notification API. New files: `widgets/chat_live_dialog.dart`, `services/push_notification_service.dart`. Modified: `screens/dashboard_screen.dart` (added `_prevRequiresAttention` edge-detection map, `_checkForNewEscalations`, notif permission state), `widgets/property_expanded_view.dart` (pill onTap → `ChatLiveDialog.show`), `pubspec.yaml` (`web: ^1.1.0`). `ChatLiveScreen` kept intact as fallback route. **Pushed (`3946597`) but build FAILED on Vercel** — dart2js error: `.has()` not defined on `Window`/`JSObject`. Followup push `b32c781` tried `globalContext.has()` but failed the same way (`.has()` lives in `dart:js_interop_unsafe`, not `dart:js_interop`). **Local fix prepared in `push_notification_service.dart`** — adds `import 'dart:js_interop_unsafe';` so the existing `globalContext.has('Notification')` compiles. Verified via `flutter analyze`: only 2 unnecessary_cast warnings (pre-existing pattern copied from ChatLiveScreen, non-blocking). **Uncommitted** — to be pushed after Phase 5 lands so the deploy goes green in one shot.

### Chat status (guest-facing `/chat?booking=...`)
- **Working as of 2026-05-11.** Fix: `if result and result.data:` guard in `find_or_create_conversation` (`supabase_client.py`). Committed and deployed.

---

## Architecture

### Backend (`backend/`)
| File | Purpose |
|---|---|
| `main.py` | FastAPI app, CORS from `FRONTEND_URL` env var; `/health` accepts GET + HEAD |
| `routers/ingest.py` | `POST /api/ingest` — SSE stream, sequential file processing |
| `routers/messages.py` | `POST /api/messages/web-incoming` (guest→AI), `POST /api/messages/host-send`, `POST /api/guests` |
| `services/supabase_client.py` | All DB/storage operations; singleton Supabase client |
| `services/gemini_messenger.py` | `first_pass` + `second_pass_with_search` — both async, called with 45s `asyncio.wait_for` guard |
| `services/gemini_client.py` | Low-level Gemini file upload/prompt execution |
| `services/file_processor.py` | Route by extension → correct Gemini prompt |
| `services/hash_guard.py` | SHA-256 duplicate detection |

### Frontend (`frontend/lib/`)
| File | Purpose |
|---|---|
| `main.dart` | Auth guard + routes |
| `screens/auth_screen.dart` | Two-panel login/signup, password toggle |
| `screens/dashboard_screen.dart` | Property grid, aurora bg, glass app bar, staggered cards |
| `screens/add_property_screen.dart` | Property creation + ingest flow |
| `screens/chat_screen.dart` | Guest-facing chat (reads booking_id from URL) |
| `screens/chat_live_screen.dart` | Host live monitoring panel |
| `screens/host_panel_screen.dart` | Per-property conversation list |
| `screens/edit_property_screen.dart` | Edit property files + re-ingest |
| `widgets/property_card.dart` | Glass card with hover/press animation, status badge |
| `widgets/property_detail_drawer.dart` | 4-tab side drawer |
| `widgets/aurora_background.dart` | 4-blob radial gradient background widget |
| `widgets/glass_panel.dart` | Reusable glassmorphic surface (blur + hover) |
| `widgets/drop_zone.dart` | Dashed-border drag-drop zone (custom CustomPainter) |
| `widgets/generate_guest_link_dialog.dart` | 2-step dialog: name → copy URLs |
| `widgets/archived_chats_dialog.dart` | Past guests list per property |
| `widgets/conversation_pill.dart` | Color-coded clickable pill per conversation with pulse dot + Live badge |
| `widgets/property_expanded_view.dart` | Glassmorphic dialog showing active + archived conversations |
| `widgets/setup_status_banner.dart` | Guided next-step banner mapped from property status |
| `widgets/file_thumbnail.dart` | Async signed URL image or themed file-type icon |
| `widgets/inactivity_wrapper.dart` | 1-hour idle → auto-logout via Listener + Timer |
| `widgets/chat_live_dialog.dart` | In-screen glassmorphic chat dialog (replaces page nav from pills) — Phase 4.5 |
| `services/push_notification_service.dart` | Web Notification API singleton via `package:web` JS interop — Phase 4.5 |
| `services/api_client.dart` | Typed HTTP wrapper: 60s timeout, 1 retry, ApiException hierarchy |
| `theme/app_theme.dart` | AppPalette ThemeExtension, daylightTheme + midnightTheme, PaletteX context extension |
| `theme/theme_controller.dart` | ChangeNotifier for Daylight/Midnight toggle, persisted via shared_preferences |
| `utils/setup_status.dart` | nextStepFor(status) → SetupStep (headline, subtext, icon, accent) |
| `utils/relative_time.dart` | relativeTime(DateTime) → "Just now / 5m ago / Yesterday / Mar 12" |

---

## Chat Flow (how it works end-to-end)

1. Host generates a guest link via dashboard → `POST /api/guests` → returns `booking_id` slug
2. Guest opens `https://alfred-ingestor.vercel.app/chat?booking=<booking_id>`
3. `ChatScreen` reads `booking_id` from URL, loads conversation from Supabase, subscribes to messages realtime
4. Guest sends message → `ApiClient.postJson('/api/messages/web-incoming', {booking_id, message})`
5. Backend: `get_guest_by_booking_id` → `find_or_create_conversation` → `insert_message(guest)` → checks mode
   - If mode = `intervene`: returns `{status: "intervene_mode", reply: null}` (host has taken over)
   - If mode = `autopilot`: calls `gemini_messenger.first_pass` (45s timeout) → optionally `second_pass_with_search` (45s timeout) → `insert_message(ai)` → returns reply
6. Realtime subscription delivers AI message to guest UI via Supabase `.stream()`

### Error handling (frontend)
| Error | Shown to user |
|---|---|
| 504 (Gemini timeout) | "Alfred took longer than usual. Tap retry." |
| 5xx server error | "Alfred hit a temporary issue. Tap retry." |
| 404 booking | "This booking link is no longer valid." |
| Network / no response | "Can't reach Alfred. Check your connection." |

---

## Design System (AppTheme / Phase 5)
Two themes via `AppPalette extends ThemeExtension<AppPalette>`. Tokens sourced from `_Context/Design inspo/Design_inspo_Alfred.json` (gitignored).
- **Daylight:** Primary `#778643` olive, Accent `#6B7280` sage, Background `#FEFCFB` warm off-white, Surface `#EFEFEF`
- **Midnight:** Primary `#778643` olive (same), Accent `#9CA3AF` soft-sage, Background `#050506` near-black, Surface `#0A0A0C` elevated
- **Glass:** `glassTint`, `glassTintStrong`, `glassTintHeavy` — alpha varies per theme; blur sigma 20/24 (`AppTheme.glassBlurSigma` / `glassBlurSigmaHeavy`)
- **Aurora blobs:** monochromatic olive family + single dim moon-glow accent (no sage/olive temperature clash) — both themes
- **Typography:** Space Grotesk (headings, w300 h1, w500 subsection, w400 card name) + Inter (body w400, label w500/w600)
- **Easing:** `AppTheme.standardEasing` (Cubic(0.16, 1, 0.3, 1)) — replaces Curves.easeOut everywhere
- **Press scale:** `AppTheme.pressScale` (0.97)
- **Radii:** cards 12, large panels/dialogs 24, pills 100, inputs 8
- **Access pattern:** `context.palette.X` everywhere (PaletteX BuildContext extension)
- **Toggle:** `themeController.toggle()` in AppBar — persisted via `shared_preferences`

---

## Conversation Modes
| Mode | Meaning |
|---|---|
| `autopilot` | AI replies automatically (normal state) |
| `intervene` | Host has taken over; AI is paused |

To reset a conversation back to AI: `UPDATE conversations SET mode = 'autopilot', ai_status = 'active' WHERE booking_id = '<id>';`
Note: `'auto'` is NOT a valid value — constraint will reject it.

---

## Phase 4 Plan (COMPLETED 2026-05-15)

Plan file: `C:\Users\San_8\.claude\plans\alfred-phase4-polish-guided-setup.md`

Covers (no backend changes, no SQL migrations):
1. **Theme toggle** — Daylight (old teal/sky palette) / Midnight (current indigo/void); persisted via `shared_preferences`; default = Daylight; AppPalette ThemeExtension refactor
2. **Inactivity auto-logout** — 1 hour idle → signOut + redirect to AuthScreen (excludes guest chat)
3. **Guided setup flow** — `setup_status.dart` helper maps status → next step (Scraped → Add Files, Ingested → Merge, Conflict_Pending → Resolve, Merged → Train Alfred); `SetupStatusBanner` shown on property card, drawer Overview, and Edit Property top
4. **"Train Alfred" vs "Update Knowledge"** button label — status-based + first-time success dialog with celebratory CTA
5. **Conversation pills (replacing simple rows)** — color-coded clickable pills opening ChatLiveScreen; Live sub-badge for intervene; pulsing unread glow for `requires_attention`; LayoutBuilder responsive density; "+N more active" → opens expanded view
6. **Card tap = expanded view** — `PropertyExpandedView` modal with Active + Archived sections + New Guest Link CTA; replaces drawer-on-tap behavior
7. **Settings icon** replaces "Chats" button in card action row → opens `PropertyDetailDrawer`
8. **Real-time dashboard** — Supabase `.stream()` on properties + conversations + guests, debounced re-process, immediate UI updates without refresh
9. **File thumbnails** — actual image previews for jpg/png/webp/heic, themed icons for PDF/DOCX/audio/etc.
10. **Clickable Airbnb URL** — `url_launcher` in drawer + edit property
11. **Markdown / Master JSON / Resolve Conflicts contrast fix** — explicit `MarkdownStyleSheet` with theme-aware colors
12. **Optimistic message send** in ChatLiveScreen + relative-time timestamps everywhere
13. **Empty state** for zero properties (welcome hero)
14. **Confirm dialogs** for destructive actions (file delete)

### Phase 4.5 — Push Notifications + In-Screen Chat Dialog (PUSHED, BUILD FAILING — fix prepared locally)
Plan file: `C:\Users\San_8\.claude\plans\alfred-phase4-5-push-notifications.md`

**Feature A — In-Screen Chat Dialog (✅ implemented locally):**
- `ChatLiveDialog` (`widgets/chat_live_dialog.dart`) — glassmorphic dialog with same two-panel layout as ChatLiveScreen
- `PropertyExpandedView._openChat` now calls `ChatLiveDialog.show(...)` instead of `Navigator.push(ChatLiveScreen)`
- Stacks on top of PropertyExpandedView — close returns to expanded view
- `ChatLiveScreen` kept intact as fallback route

**Feature B — Push Notifications (✅ implemented locally):**
- `PushNotificationService` (`services/push_notification_service.dart`) — singleton via `package:web` JS interop
- DashboardScreen: `_prevRequiresAttention` map for false→true edge detection in `_checkForNewEscalations()`
- Permission prompt fires on first escalation, not on init
- Notification onTap → opens `ChatLiveDialog` for that conversation (in-screen, no page nav)
- AppBar permission chip (state field `_notifPermission` + `_showNotifChip`)
- `pubspec.yaml`: `web: ^1.1.0` added

**Status:** RESOLVED 2026-05-15. The `dart:js_interop_unsafe` import fix shipped bundled with Phase 5A (`d432f22`); subsequent Phase 5 commits all deployed green.

### Commit 6 — Host/Guest Perspective Parity + Emergency Notice + Popup Refresh (2026-05-29, uncommitted)

User exposed four issues by exploring the deployed app: (1) "Issue resolved" prefix bled to guest, (2) host saw "speaking with [host name]" instead of "[guest name]", (3) guest got no banner/system-message on emergency escalation, (4) `PropertyExpandedView` popup stayed stale after resolve.

**Architectural shift:** system messages stored in `messages.content` are now marker tokens (`__SYS_INTERVENE__`, `__SYS_RESUME__`, `__SYS_RESOLVED__`). Each viewer renders the marker through `ChatSystemMessages.formatForGuest(content, hostName: ...)` or `formatForHost(content, guestName: ...)` — so the same DB row produces different text per actor without a schema change. Legacy plain-text messages still render verbatim via fall-through; `inferModeFromSystemMessage` keeps a legacy-string match alongside the marker check so the guest-side piggyback works across both formats.

**Files changed:**
- `frontend/lib/utils/chat_system_messages.dart` — Rewritten with marker constants, per-viewer formatters, legacy-compat mode inference.
- `frontend/lib/screens/chat_screen.dart` (guest) — Loads `_hostName` via PostgREST alias query (`name, host_name:master_json->host_profile->>name`). System messages render via `formatForGuest`. Piggyback (`_syncModeFromMessageStream`, renamed) now also detects unresolved escalated AI messages and flips `_mode='intervene'` locally — closes the emergency banner gap when the conversations stream silently drops.
- `frontend/lib/widgets/chat_live_dialog.dart` + `screens/chat_live_screen.dart` (host) — Load `_guestName` from `guests.name`. `_setMode` and `_resolveIssue` insert markers. System bubbles render via `formatForHost`. Unused `_hostName` field removed (host doesn't render their own name to themselves).
- `frontend/lib/widgets/property_expanded_view.dart` — Extracted shared merge/sort logic into `_applyConversations`. New `_refreshLocalConversations()` does a one-shot fetch. `_openChat` wraps `onResolved`: refresh popup first, then forward to dashboard.
- `backend/routers/messages.py` — On auto-escalation, after `update_conversation` sets mode=intervene, insert a `__SYS_INTERVENE__` system message. Makes emergency parity work regardless of whether the host has the chat open. Marker kept in sync with the frontend constant (comment notes this).

**Acceptance behavior:**
- Host resolves → host sees "Issue resolved — Alfred has resumed the conversation.", guest sees only "Alfred has resumed the conversation."
- Host clicks Intervene → host sees "You are now speaking with [guest name].", guest sees "You are now speaking with [host name]."
- Guest sends emergency message → backend escalates → guest sees orange banner + intervention system message in ≤2s, regardless of host presence
- Host resolves from inside `PropertyExpandedView` → popup pill switches from red → neutral immediately (no waiting for stream)

**Verification:** `flutter analyze` on all 5 changed frontend files → no issues. `python3 ast.parse` on `messages.py` → parses OK.

### Commit 5 — Three-Layer Real-Time Fix (2026-05-28, shipped `c80a84c`)

Commit 4's "streams-only + resume-resubscribe" architecture assumed Supabase free-tier realtime is reliable for `conversations` and `properties` table UPDATEs. It isn't — low-traffic tables get throttled, and updates can lag 5–15s or drop entirely. User reported: after marking an issue as resolved in the chat dialog, the dashboard's "needs attention" badge stayed until manual reload. Same symptom for new escalations arriving on the dashboard.

**Three complementary layers — no single point of failure:**

1. **Streams (Commit 4 mechanism, retained)** — fast path when working.
2. **Optimistic refresh on host action** — `ChatLiveDialog` now takes an `onResolved: VoidCallback?` param. The dashboard passes `_onChatResolved` (which calls `_loadProperties(silent: true)`) at all 3 `ChatLiveDialog.show()` call sites. When the host marks an issue as resolved, the dashboard refreshes the instant the API returns — no waiting for the conversations stream to fire. Callback threaded through `PropertyExpandedView` (new `onChatResolved` field).
3. **Silent safety-net timer** — `_silentRefreshTimer` polls every 10s while the dashboard is mounted, calling `_loadProperties(silent: true)`. `_loadProperties` now takes `{bool silent = false}` — when silent, skips the `_loading = true` toggle, suppresses SnackBar errors (background sync, user can't act on them). Result: invisible self-healing for cases where the stream dropped AND the user didn't take the action themselves (e.g. guest sends a message from another device).

**Why not just keep the 30s timer from before Commit 4:** User specifically rejected the visible blank-screen reload. The silent variant is invisible — no spinner, no UI disruption. The 10s interval is short enough that perceived lag is negligible.

**Why not push for stream-only:** Supabase free-tier realtime is throttled. We can't fix platform behavior from the client. On a paid Supabase plan ($25/mo Pro), realtime quotas are dedicated and stream reliability improves significantly — the 10s safety-net could likely be removed or raised to 60s. Until then, optimistic + safety-net pattern matches industry norm (Slack, Linear, Notion all use it).

**Files changed:**
- `frontend/lib/screens/dashboard_screen.dart` — `_loadProperties({bool silent})`, `_silentRefreshTimer`, `_onChatResolved()`, wired at 3 call sites
- `frontend/lib/widgets/chat_live_dialog.dart` — `onResolved` param on widget + `show()`, fired from `_resolveIssue`
- `frontend/lib/widgets/property_expanded_view.dart` — `onChatResolved` pass-through field
- `CONTEXT.md` — this entry

**Not changed:** `chat_live_screen.dart` (full-screen host view). It's opened from non-dashboard flows (`main.dart` deep-link, `generate_guest_link_dialog`, `ingest_screen`, `host_panel_screen`); none of those parents currently consume a resolve callback. If the user reports similar staleness on those flows, we'll thread the same callback through them.

**Verification:** `flutter analyze` clean on the 3 changed files — 2 pre-existing `unnecessary_cast` warnings unchanged.

### Commit 4 — Live System + Escalation Lifecycle Colors (2026-05-28, shipped `40453c9`, see also Commit 5)

Plan derived inline during session (no `.claude/plans/` file). Prior commits 1–3 in this session series (bug fixes, visual identity redesign, mobile optimization) all shipped earlier in `the-ingestor` history.

**Files changed:**
- `frontend/lib/screens/dashboard_screen.dart`
- `frontend/lib/screens/chat_screen.dart`
- `frontend/lib/widgets/chat_live_dialog.dart`
- `frontend/lib/screens/chat_live_screen.dart`
- `frontend/lib/utils/chat_system_messages.dart` (new)

**1. Dashboard real-time (no more 30s blank-screen reload):**
- Removed the `Timer.periodic(30s)` belt-and-suspenders fallback that called `_loadProperties()` and toggled `_loading = true` → caused full-screen spinner every 30s.
- Added `WidgetsBindingObserver` mixin to `_DashboardScreenState`. On `AppLifecycleState.resumed`, the dashboard cancels all three stream subscriptions (`_propertyStreamSub`, `_convStreamSub`, `_guestStreamSub`) and re-calls `_subscribeRealtime()` so dropped WebSockets reconnect instantly when the tab regains focus. Updates now flow truly real-time via streams alone; no polling.

**2. Guest chat — mode piggyback on messages stream:**
- Created `utils/chat_system_messages.dart` with `ChatSystemMessages.resume`, `intervene(hostName)`, `resumeAfterResolve` constants + `inferModeFromSystemMessage()` matcher. Single source of truth so changing wording doesn't silently break detection.
- `chat_screen.dart`: `_subscribeToMessages()` now calls `_syncModeFromSystemMessages()` after every stream tick — scans the most recent system message and updates `_mode` if it implies a state transition. Closes the failure mode where the conversations stream dropped but the messages stream didn't, leaving the intervention banner stuck on the guest side.
- `_modeSubscription` / `_watchConversation()` stays as the primary path; piggyback is insurance.

**3. Host chat — escalation lifecycle colors + emergency-red fix (both `chat_live_dialog.dart` AND `chat_live_screen.dart`):**
- Replaced `bool inEscalationWindow` with `enum _EscalationState { none, active, resolved }`.
- `_computeEscalationWindow()` now tracks `windowStart` index alongside `inWindow`. When a `resolution_status == 'resolved'` marker arrives, retroactively flips every message in the open window from `active` → `resolved` so resolved escalations are coloured green.
- `_buildBubble()` colour logic:
  - `resolved` → `palette.successContainer` bg + `palette.success` border (both guest + Alfred bubbles)
  - `active` + `isEmergency` → `dangerContainer` + `danger` border (red)
  - `active` + non-emergency → `warningContainer` + `warning` border (amber)
  - Host messages keep their neutral styling regardless of state
- New sender label `'Alfred — resolved'` for resolved Alfred bubbles.
- **Emergency-red bug fix:** After resolve, `_escalationReason` is cleared locally; if a new emergency arrives and the conversations stream has dropped, `isEmergency` stays false → orange instead of red. Added `_refreshEscalationReason()` (single-row `SELECT escalation_reason WHERE id = ...`), called from `_subscribeToMessages()` whenever the auto-intervene branch fires. Lightweight, no spinner.

**4. Host chat — "Issue resolved" system message:**
- `_resolveIssue()` now inserts `ChatSystemMessages.resumeAfterResolve` ("Issue resolved — Alfred has resumed the conversation.") instead of the generic "Alfred has resumed your conversation." used by the mode-toggle path. Neutral phrasing works for both host and guest; gives the host the confirmation message they asked for without duplication.

**5. Selectable chat text:**
- Replaced `Text(msg['content']...)` → `SelectableText(...)` for all three message bubble types: guest-side `chat_screen.dart`, host-dialog `chat_live_dialog.dart`, host-screen `chat_live_screen.dart`. Applied to both regular bubbles and centered system messages.

**Why both `chat_live_dialog.dart` AND `chat_live_screen.dart`:** They're near-duplicates (the deferred dedupe from Phase 5 lives in this file). Both files house the same `_buildBubble` / `_computeEscalationWindow` / `_resolveIssue` / `_setMode` logic. Both used: dialog from dashboard pills + push notifications; screen from `main.dart` deep-link, `generate_guest_link_dialog`, `ingest_screen`, `host_panel_screen`. Future cleanup: extract a shared `LiveChatPanel` widget (still deferred).

**Verification:** `flutter analyze` clean — 8 pre-existing warnings unchanged (unnecessary casts in `_loadConversation`, deprecated Radio APIs, dead `_refreshProperty`, `dart:html` deprecation in `voice_recorder.dart`). No new diagnostics from this commit.

**Pending:** show diff → await user approval → commit + push (safe-commit-n-push workflow).

### Phase 5 — UI/UX Audit & Design Token Migration (COMPLETED 2026-05-15)
Plan file: `C:\Users\San_8\.claude\plans\alfred-phase5-uiux-audit.md`

**Part A — Design Token Migration (`d432f22`):**
- Olive `#778643` primary, sage accent, off-white `#FEFCFB` / near-black `#050506` bases (replaces teal/sky + indigo/void)
- Poppins → Space Grotesk for all headings (w300 h1, w500 subsection, w400 card name, w600 labels unchanged)
- `AppTheme.standardEasing` (Cubic(0.16, 1, 0.3, 1)), `AppTheme.pressScale` (0.97), blur sigma 20/24, card radius 12, large-panel 24
- Bundled Phase 4.5 build fix (`dart:js_interop_unsafe` import) so Vercel deploys went green for the first time since 4.5

**Part B — Audit fixes:**
- **P0 (`ead7512`):** Aurora harmonization (olive family + dim moon-glow, no temperature clash); touch targets ≥44px; Mode toggle keyboard focus via Material+InkWell; conversation_pill respects reduced motion; FileThumbnail Tooltip+Semantics+loadingBuilder; file_status_list and generate_guest_link_dialog full Colors.X → palette token remap; auth brand panel gradient olive-ified
- **P1 (`e7295d9`):** Live badge tooltip + readable fontSize; CTA hierarchy (Sign In, INGEST NOW, _officialPropertyName) aligned to button design token (SG w500); 4px grid corrections on property_card + setup_status_banner action button
- **P2 (`d8c20c1`):** True pill radii (100) on property_card badges; large-panel radii 20→24 across add_property/chat_live screens + archived_chats dialog; bubble radii 14→12 (card token); 4px grid on tiny icon buttons

**Deferred to future polish phase:**
- Scroll-fade `ShaderMask` indicators (dashboard grid, edit_property knowledge tab, drawer file list)
- `file_thumbnail` file-type semantic colors → centralized `AppPalette.fileTypeColors` map
- `chat_live_screen` ↔ `chat_live_dialog` widget duplication → extract shared `LiveChatPanel`
- `generate_guest_link_dialog` inline `errorText` state (currently SnackBar-only)
- `ingest_screen.dart` cleanup — dead code, no router references; either delete or wire in

### Future Backend Work (deferred — needs SQL migrations)
- **Per-guest separate chat threads (decided 2026-06-09 to defer).** Today a booking link = ONE shared conversation (everyone who opens it shares the thread). Desired down-the-line: each guest gets their *own* thread under the booking so they can't read each other's messages. **Caveat to solve first:** identity is the booking_id in the URL, so the same person opening on phone + browser would otherwise spawn two threads — need a per-guest identity (device/session token or a "who are you" step) before splitting threads. Until then: shared thread is intentional.
- **Property delete = soft-delete + guest anonymization (decided 2026-06-09).** Do NOT hard-delete or cascade-delete chats/messages — keep them for history + future re-training / data-annotation rounds. On delete: soft-delete the property (`properties.deleted_at`), retain conversations + messages, and anonymize guests in place (rename to `Guest <FirstLetterOfName><first3ofBookingId>`) for privacy. Replaces the original ISSUE-B ON-DELETE-CASCADE idea.
- `properties.trained_at` timestamp — reliable "first training" detection (currently inferred from status)
- `conversations.checked_out_at` or `is_archived` flag — true "guest checked out" detection for Archived section in expanded view
- `ai_status` + active chat count filtering by recency (currently counts all guests)
- Reservations calendar — real data + UI
- Google Cloud Run migration — eliminates Render cold-start
- `INGESTOR_SUPABASE_URL`/`INGESTOR_SUPABASE_SERVICE_KEY` env vars on Render scraper
- End-to-end REQ-08 test (CSV upload)

---

## Phase 3 Plan (completed)

Plan file: `C:\Users\San_8\.claude\plans\alfred-phase3-dark-redesign.md`

Covers 3 changes (no backend changes, no new packages):
1. **Open issue disclaimer** — `chat_live_screen.dart`: amber banner + "Mark as Resolved" button when `_mode == 'autopilot' && _escalationReason != null`
2. **Conversation previews on property card** — `dashboard_screen.dart` fetches guest names + conversation status; `property_card.dart` renders priority-ordered list (emergency → escalation → normal) with colored dots + "Live" pill for intervene mode; max 5 rows + "+N more"; card `childAspectRatio` → `280 / 390`
3. **Full dark redesign** — new palette: Electric Indigo `#6366F1` primary, Void Slate `#0D0D12` background, Soft Mint `#10B981` success, Golden Hour `#F59E0B` warning, Coral Ember `#EF4444` danger; `aurora_background.dart` inherits blob colors automatically (no rename needed); status glow on cards (BoxShadow by severity)

---

## Pending Actions

### ✅ Done (2026-05-11)
- `backend/services/supabase_client.py` — NoneType crash fix pushed and live
- `backend/main.py` — `/health` HEAD support live; UptimeRobot confirmed working
- Chat confirmed working end-to-end
- Escalation resolve flow + learning system (2026-05-11)
- New columns: `properties.learned_knowledge`, `conversations.escalation_reason`, `messages.used_learned_knowledge`
- New endpoint: `POST /api/conversations/resolve`
- New service function: `gemini_messenger.summarize_escalation` (gemini-2.5-flash)
- UI: resolve button in intervene mode, escalation window coloring, emergency styling, automated-learning badge, property card alert pills

### ✅ Done (Phase 2 — this session)
- **Step 1**: `query_knowledge_base()` now includes `learned_knowledge` in Gemini prompt
- **Step 2**: `learned_entry` dict now includes `"reviewed": False` on creation
- **Step 3**: `insert_message()` accepts `message_type` and `media_url` params
- **Step 4**: `chat_live_screen.dart` — replaced `_subscribeToConversation` with `_watchConversation()` filtering by `booking_id`; real-time sync now works even when conversation doesn't exist yet
- **Step 5**: System messages (sender_type='system') — `_insertSystemMessage()` helper; `_setMode()` and `_resolveIssue()` insert "You are now speaking with [host name]" / "Alfred has resumed" messages; both `chat_live_screen` and `chat_screen` render system messages as centered italic text
- **Step 6**: `_computeEscalationWindow()` now includes the guest message that immediately precedes an escalated AI response
- **Step 7**: Guest chat `AppBar` shows property name subtitle; `_watchConversation()` added for real-time new-conversation detection
- **Step 8**: Media attachments (image + voice) in guest chat — `file_picker` for images, `record` for audio; uploads to `chat_media` Supabase Storage bucket; `audioplayers` for playback in both guest and host views; `_AudioBubble` widget in both files
- **Step 9**: Automated Learning review UI in Knowledge tab — orange cards (unreviewed), green cards (reviewed); Accept / Edit / Discard actions with Supabase read-modify-write

### Supabase (pending — user must do manually)
- SQL migration for system sender_type: `ALTER TABLE public.messages DROP CONSTRAINT messages_sender_type_check; ALTER TABLE public.messages ADD CONSTRAINT messages_sender_type_check CHECK (sender_type IN ('guest', 'ai', 'host', 'system'));`
- SQL migration for media columns: `ALTER TABLE public.messages ADD COLUMN message_type text NOT NULL DEFAULT 'text', ADD COLUMN media_url text;`
- Create PUBLIC Supabase Storage bucket named `chat_media` (Storage → New bucket → toggle Public ON)

### Supabase (if not done yet)
- Set Site URL → `https://alfred-ingestor.vercel.app` (Auth → URL Configuration)
- Add Redirect URL → `https://alfred-ingestor.vercel.app/**`
- Run Storage policies (3 `CREATE POLICY` statements — see session 2026-05-07 Part 3 in git history)
- `UPDATE properties SET owner_id = 'f86ebcae-683d-4914-837b-caaedca6a19d';`

### Lower priority
- **Reservations calendar** — placeholder button exists; no real data yet
- **Active chat count definition** — currently counts all guests, not filtered by recency
- **Add** `INGESTOR_SUPABASE_URL`/`INGESTOR_SUPABASE_SERVICE_KEY` to Render scraper env vars
- **End-to-end REQ-08 test** (CSV upload)
- **Google Cloud Run migration** — eliminates Render cold-start entirely; need to write Dockerfile

---

## Build Notes
- **dart2js strictness:** `context.palette.X` is a runtime value — never wrap in `const`. dart2js catches this even when the local analyzer doesn't. Rule: any widget referencing `context.palette` must not have `const` on itself or any ancestor that contains it.
- **Map type inference:** `{...someMap, 'key': value}` infers `Map<dynamic, dynamic>` — always annotate as `<String, dynamic>{...}` when assigning to a typed map.
- **`.has()` for JS feature detection:** Lives in `dart:js_interop_unsafe`, NOT `dart:js_interop`. To check if a global JS API exists (e.g. `Notification`), import both and call `globalContext.has('Notification')`. `web.window.has(...)` does NOT compile — `Window` doesn't expose `.has()`.
- **Local pre-deploy verification:** Always run `flutter analyze <changed files>` before pushing — local analyzer catches dart2js errors that Vercel will hit. To work around snap-flutter XDG issue on WSL2: `export XDG_RUNTIME_DIR=$HOME/.cache/xdg-runtime && mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"` before invoking flutter.

---

## Known Constraints
- Render free tier: 15-min inactivity spin-down; mitigated by UptimeRobot 5-min ping
- `asyncio.wait_for(timeout=45)` guards both Gemini calls — if Gemini hangs, client gets a structured 504 (not a raw connection kill)
- Supabase singleton client (`_client`) is shared across `asyncio.to_thread` calls — thread-safe in practice because supabase-py uses httpx which is connection-pool safe, but worth watching
- `conversations_mode_check` constraint only allows `'autopilot'` and `'intervene'` — not `'auto'`
- `messages.sender_type` check must include `'system'` (migration adds it); system messages render as centered italic text
- `messages.message_type` defaults to `'text'`; `'image'` and `'audio'` use `media_url` pointing to `chat_media` public bucket path
- Media upload requires `_conversationId` to be set (guest must send one text message first)
