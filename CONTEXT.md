# Session Context
**Created:** 2026-04-14
**Last Session:** 2026-05-15 (Phase 4 + build fix + Phase 4.5/5 plans)

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
| Bucket | `Property_assets` (private) |

## Render Monitoring
- UptimeRobot pings `https://the-ingestor.onrender.com/health` every 5 minutes (keeps free-tier instance warm)
- Render free tier spins down after 15 min inactivity; UptimeRobot prevents this

---

## Stack
- **Backend:** FastAPI + uvicorn, Python 3.14 (Render), deployed on Render free tier
- **Frontend:** Flutter web, deployed on Vercel
- **AI:** google-genai SDK, model `gemini-2.5-pro`
- **Storage/DB:** Supabase (Storage + Postgres)

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

## Design System (AppTheme / Phase 4)
Two themes via `AppPalette extends ThemeExtension<AppPalette>`:
- **Daylight:** Primary `#0F766E` teal-700, Accent `#0EA5E9` sky-500, Background `#F8FAFC` slate-50
- **Midnight:** Primary `#6366F1` indigo-500, Accent `#22D3EE` cyan-400, Background `#0D0D12` void-slate
- **Glass:** `glassTint`, `glassTintStrong`, `glassTintHeavy` — alpha varies per theme; blur sigma 18–28
- **Aurora blobs:** teal / sky / lavender / peach at 4 corners, blur sigma 60 — inherited from palette
- **Typography:** Poppins (headings) + Inter (body)
- **Animations:** 150–300ms ease-out; `.withValues(alpha:)` throughout (Flutter 3.27+)
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

### Phase 4.5 — Push Notifications + In-Screen Chat Dialog (PLANNED)
Plan file: `C:\Users\San_8\.claude\plans\alfred-phase4-5-push-notifications.md`

**Feature A — In-Screen Chat Dialog:**
- Clicking a ConversationPill opens `ChatLiveDialog` modal instead of navigating to `ChatLiveScreen`
- `ChatLiveDialog` = same two-panel layout (messages left, controls right) inside a glassmorphic dialog
- Stacks on top of `PropertyExpandedView` — close returns to expanded view
- `ChatLiveScreen` kept intact as a fallback route; just stop navigating to it from pills/dashboard
- New file: `frontend/lib/widgets/chat_live_dialog.dart`

**Feature B — Push Notifications:**
- Web Notification API (no FCM, no service worker — tab must be open)
- `push_notification_service.dart` singleton via `package:web` JS interop
- `_prevRequiresAttention` diff map in DashboardScreen for false→true edge detection
- Permission prompt on first escalation, not on init
- Click handler: `window.focus()` + open `ChatLiveDialog` for that conversation
- No backend changes, no SQL migrations

### Phase 5 — UI/UX Audit (PLANNED)
Plan file: `C:\Users\San_8\.claude\plans\alfred-phase5-uiux-audit.md`
- Skills: `web-design-guidelines` (Vercel) + `ui-ux-pro-max-skill` (v2.5.0) + `_ingestor/frontend-design.md`
- 5 audit categories: Accessibility (WCAG 2.1 AA), Typography, Layout & Spacing, Interaction & Animation, Brand & Consistency
- Both Daylight and Midnight themes must pass
- Findings format: `[P0|P1|P2] file:line — finding — fix`
- One commit per category after fixes

### Future Backend Work (deferred — needs SQL migrations)
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

---

## Known Constraints
- Render free tier: 15-min inactivity spin-down; mitigated by UptimeRobot 5-min ping
- `asyncio.wait_for(timeout=45)` guards both Gemini calls — if Gemini hangs, client gets a structured 504 (not a raw connection kill)
- Supabase singleton client (`_client`) is shared across `asyncio.to_thread` calls — thread-safe in practice because supabase-py uses httpx which is connection-pool safe, but worth watching
- `conversations_mode_check` constraint only allows `'autopilot'` and `'intervene'` — not `'auto'`
- `messages.sender_type` check must include `'system'` (migration adds it); system messages render as centered italic text
- `messages.message_type` defaults to `'text'`; `'image'` and `'audio'` use `media_url` pointing to `chat_media` public bucket path
- Media upload requires `_conversationId` to be set (guest must send one text message first)
