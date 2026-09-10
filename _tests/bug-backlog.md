# Bug Backlog

The project's institutional memory for real bugs: what broke, why, and how it got fixed — so a
recurrence has a known answer instead of a re-investigation from scratch. Entries stay short (4-6
lines): symptom/impact, root cause, fix, where. Not every fixed bug needs a regression scenario in
`scenarios.md`, but when one exists it's cross-referenced.

**Adding an entry:** after any fix with a real root cause worth remembering, add it here — concise,
no over-narrating. This file plus `_tests/HEALTH_CHECK_PROTOCOL.md` are the two places this
project tracks "have we seen this before."

---

## Open — not yet fixed

### BUG-001: Chat pills overlap UI on property card
- **Reported:** 2026-06-02
- **Severity:** UI / layout
- **Symptoms:** chat pills ("Juanito", "Steven", etc.) too large for the card width; "+N more"
  pill overlaps the Settings button row; pills don't adapt to card/viewport size.
- **Likely touches:** `frontend/lib/widgets/conversation_pill.dart`, `property_card.dart`

### BUG-002: Ingest stuck in "Queued" state, dashboard goes empty
- **Reported:** 2026-06-02
- **Severity:** functional — blocking ingest flow
- **Symptoms:** files stayed "Queued" after Ingest Now; retry did nothing; Back → empty dashboard.
- **Note:** predates the Cloud Run migration and this session's ingest-resilience fixes (BUG-045,
  BUG-047) — may already be moot; re-verify before investigating further.

### BUG-003: Scraping fails with 500 Internal Server Error on prod
- **Reported:** 2026-06-02
- **Severity:** functional
- **Symptoms:** `Server error '500 Internal Server Error'` from the scraper; property still
  created with partial extracted knowledge.
- **Note:** predates the Cloud Run migration (was Render) and the `gemini-3.8-flash` migration —
  re-verify against current infra before investigating further.

### BUG-004: User isolation broken — new account could see another user's property + chats
- **Reported:** 2026-06-02
- **Severity:** CRITICAL — data leak / security
- **Symptoms:** a fresh account's dashboard showed another user's property and 5 chats after
  ingesting a URL that happened to match an existing canonical property row.
- **Note:** substantially addressed by the later RLS + booking-JWT work (BUG-012) and the
  soft-delete/canonical-lookup fixes (BUG-014), but never explicitly re-verified against *this*
  exact repro (property dedup by `airbnb_url` returning another owner's row) — worth a targeted
  regression pass before considering it closed.

### BUG-005: Staging deployment renders differently from prod
- **Reported:** 2026-06-02
- **Severity:** UI / unknown
- **Symptoms:** "everything is bigger" on staging vs prod, same codebase.
- **Note:** predates the platform-parity migration (both now Cloud Run + the same Flutter build
  pipeline) — likely moot, re-verify before investigating.

---

## Fixed

### BUG-006: Scraper crashed calling a retired Gemini preview model
- **Fixed:** 2026-06-02, commit `2a75a4e`
- **Severity:** functional — blocking all ingests
- **Root cause:** `scraper/main.py` called `model="gemini-3-flash-preview"`, which Google retired;
  every scraper Gemini call raised, caught and rethrown as an opaque 500.
- **Fix:** switched to a current stable model (`gemini-2.5-flash` then, `gemini-3.8-flash` now) +
  added error logging so future failures aren't silent.
- **Scenario:** **B0** (scraper-base-01), Layer 1. **Recurred once already** — see BUG-048.

### BUG-007: Guest chat crashed with a NoneType error on first contact
- **Fixed:** 2026-05-11
- **Severity:** guest-facing chat unusable on a new booking's first message
- **Root cause:** `find_or_create_conversation` didn't guard against an empty/None Supabase
  response before accessing `.data`.
- **Fix:** added a presence guard before use.

### BUG-008: Push-notification feature broke every Vercel deploy
- **Fixed:** 2026-05-15, commit `d432f22`
- **Severity:** build-breaking — blocked all web releases
- **Root cause:** `.has()` JS feature-detection was called via `dart:js_interop`, but that method
  only exists in `dart:js_interop_unsafe`.
- **Fix:** added the correct import.

### BUG-009: Re-escalated conversations showed amber instead of red after a stream drop
- **Fixed:** 2026-05-28, commit `40453c9`
- **Severity:** host triage — an emergency could visually read as routine
- **Root cause:** `_escalationReason` was cleared locally on resolve; a new emergency arriving
  during a dropped realtime stream left `isEmergency` stuck `false` client-side.
- **Fix:** added `_refreshEscalationReason()` on the auto-intervene branch.

### BUG-010: Dashboard "needs attention" badge stuck after resolving an issue
- **Fixed:** 2026-05-28, commit `c80a84c`
- **Severity:** host could miss a new issue or believe a resolved one was still open
- **Root cause:** Supabase free-tier Realtime throttles/drops updates on low-traffic tables, no
  fallback existed.
- **Fix:** kept streams as the fast path, added an optimistic refresh on resolve + a silent 10s
  safety-net poll.

### BUG-011: Host/guest saw each other's system messages with the wrong text
- **Fixed:** 2026-05-29
- **Severity:** confusing/broken UX across 4 distinct symptoms (leaked host-only prefix, wrong
  name shown, missing emergency banner, stale popup)
- **Root cause:** system messages were stored as literal display text instead of viewer-agnostic
  markers, so one DB row couldn't render differently for host vs. guest.
- **Fix:** rewrote as marker tokens (`__SYS_INTERVENE__` etc.) rendered per-viewer.

### BUG-012: Enabling RLS silently broke guest-facing reads
- **Fixed:** 2026-06-11, commit `f527e11`
- **Severity:** guest chat header, realtime delivery, and dup system messages all broke
- **Root cause:** `anon` could no longer read `properties` directly; the guest realtime socket
  wasn't authenticating with the booking JWT; 3 racing writers could double-insert a marker.
- **Fix:** `/api/guest-token` resolves property/host name server-side; guest client calls
  `realtime.setAuth(token)`; added a DB trigger to suppress duplicate markers.

### BUG-013: Host actions started 401-ing after a Supabase signing-key migration
- **Fixed:** 2026-06-11, commit `f527e11`
- **Severity:** would have blocked host-only endpoints project-wide
- **Root cause:** Supabase moved to asymmetric JWT signing keys; backend validated host tokens via
  local `jwt.decode(..., HS256)`, which no longer matched.
- **Fix:** switched host-token verification to `supabase.auth.get_user(token)` (algorithm-agnostic).
  Guest tokens (self-minted HS256) were left on the legacy-secret path deliberately.

### BUG-014: Soft-deleted properties couldn't be safely re-added
- **Fixed:** 2026-06-30, commits `bd13deb`, `fdf965c`
- **Severity:** re-adding a deleted listing hard-failed or silently revived a hidden tombstone
- **Root cause:** the `(airbnb_url, owner_id)` uniqueness constraint counted soft-deleted rows;
  canonical-property lookup didn't exclude tombstones.
- **Fix:** partial unique index (`WHERE deleted_at IS NULL`); tombstones excluded from lookup;
  `/api/guest-token` 410s for deleted properties.

### BUG-015: Failed Gemini retries piled up duplicate guest messages
- **Fixed:** 2026-07-05
- **Severity:** a guest's failed send could retry into multiple stored copies
- **Root cause:** the guest message row was inserted *before* calling Gemini, so any retry
  re-inserted it.
- **Fix:** dedupe guard skips inserting a message identical to the immediately-preceding one.

### BUG-016: Guest's language flipped mid-conversation on stray tokens
- **Fixed:** 2026-07-05
- **Severity:** a Spanish-speaking guest could get switched to English by typing "okok"
- **Root cause:** `preferred_language` was seeded to `"english"` at guest creation, so the first
  non-English message always looked like a "switch."
- **Fix:** language now derived from the last 3 guest messages; new guests seed `"not_set"`.

### BUG-017: Conversation-resolve endpoint 500'd after an incomplete refactor
- **Fixed:** 2026-07-08→09, commit `024752c`
- **Severity:** blocked the resolve flow entirely (autopilot unaffected)
- **Root cause:** a refactor added `escalation_reason` to the function's return tuple, but only 1
  of 3 `return` statements was updated.
- **Fix:** all 3 returns made consistent.

### BUG-018: Off-topic questions were wrongly escalated to the host
- **Fixed:** 2026-07-08, commit `33b955a`
- **Severity:** unnecessary host interruptions on trivial messages
- **Root cause:** the "out-of-scope" escalation category was over-broad; hostility detection fired
  on a single vulgar word.
- **Fix:** split into a narrower "needs host decision" category + a "redirect, don't escalate"
  category; hostility now requires genuine anger/target.

### BUG-019: Guest replies sometimes showed raw JSON; resolve button didn't appear live
- **Fixed:** 2026-07-09, commit `cc5c5a8`
- **Severity:** guest-visible garbled replies; hosts missing a live escalation
- **Root cause:** the web-search second pass reused the JSON-mandating first-pass prompt; the
  resolve-button check only scanned the stream's last message.
- **Fix:** dedicated plain-text prompt + sanitizer; resolve check scans all messages.

### BUG-020: Telegram escalation notice arrived before Alfred's own reply
- **Fixed:** 2026-07-10, commit `90faaa9`
- **Severity:** made Alfred's reply read as if the host had written it
- **Root cause:** notice was sent before the AI reply.
- **Fix:** reordered.

### BUG-021: Archiving a conversation intermittently did nothing, or showed stale rows
- **Fixed:** 2026-07-10, commit `90faaa9`
- **Severity:** hosts couldn't reliably clean up conversations
- **Root cause:** `_conversationId` only populated by a laggy realtime stream; the conversation
  list didn't filter already-archived rows.
- **Fix:** both gaps closed in `_applyConversations`.

### BUG-022: Guest voice notes on web silently did nothing
- **Fixed:** 2026-07-10, commit `90faaa9`
- **Severity:** mic button appeared to work but produced no message, no error
- **Root cause:** permission/encoder failures were swallowed.
- **Fix:** errors now surfaced explicitly.

### BUG-023: Host avatar upload failed with a storage 403
- **Fixed:** 2026-07-10, commit `90faaa9`
- **Severity:** avatar upload completely broken
- **Root cause:** direct client-side upload hit an RLS policy it didn't satisfy.
- **Fix:** brokered through `POST /api/host/avatar` (service role).

### BUG-024: Desktop microphone was unreachable by construction
- **Fixed:** 2026-07-14 (found 2026-07-10)
- **Severity:** voice notes never worked on desktop browsers
- **Root cause:** mic UI was gated behind `hasPermission()`, which desktop Chrome/Firefox reports
  `false` for the unasked "prompt" state — so `getUserMedia` (the only thing that triggers the
  permission prompt) never ran.
- **Fix:** ask for the mic by using it directly instead of pre-checking.

### BUG-025: Migrating to Vertex AI broke image/PDF ingest and left chat-path 429s unretried
- **Fixed:** 2026-07-12→13, commits `efd8086`, `5681735`
- **Severity:** every image/PDF ingest failed outright; Telegram failed under load
- **Root cause:** Vertex has no File API; the 429 retry wrapper was only wired into ingest, not
  guest chat.
- **Fix:** ingest sends bytes inline (~15MB cap); all 7 `generate_content` sites route through
  `genai_factory.generate_with_retry()`.

### BUG-026: New prod database never streamed Realtime updates
- **Fixed:** 2026-07-12
- **Severity:** host dashboard never live-updated, required manual refresh
- **Root cause:** Realtime only streams tables in the `supabase_realtime` publication, which isn't
  part of table/policy/index DDL — the schema-parity copy silently omitted it.
- **Fix:** added `messages` to the publication; parity checks now diff publications too.

### BUG-027: Mexican listings got an English-only welcome message
- **Fixed:** 2026-07-13
- **Severity:** wrong first impression for non-English guests
- **Root cause:** `welcome.py` read `location.country`, but merge nests it under
  `location.address.country`.
- **Fix:** corrected the JSON path.

### BUG-028: Telegram replies froze and arrived stacked minutes late
- **Fixed:** 2026-07-13, commit `3a1d1e5`
- **Severity:** major reliability issue
- **Root cause:** Cloud Run throttles CPU to ~0 right after the HTTP response returns, but real
  work ran in `BackgroundTasks` after acking.
- **Fix:** replaced with Cloud Tasks — webhook acks in ~150ms, a fresh request handles the work
  with full CPU. See `HEALTH_CHECK_PROTOCOL.md` row 5 (`min-instances` regression guard).

### BUG-029: Prod Vercel shipped the Supabase service_role key to every visitor
- **Fixed:** 2026-07-14, commits `136551d`, `96e5ad8`
- **Severity:** CRITICAL — any visitor received a key that bypasses RLS (~1 day exposure)
- **Root cause:** the prod Vercel project had `service_role` set in `SUPABASE_ANON_KEY`; Flutter
  compiles `.env` into the bundle and serves it at `/assets/.env`.
- **Fix:** rotated to `sb_secret_`/`sb_publishable_` keys, disabled legacy JWT-based API keys,
  added a boot-time guard refusing to start on a service_role/`sb_secret_` key.
- **Regression guard:** `HEALTH_CHECK_PROTOCOL.md` row 19 (`check_deployed_supabase_key`) — checks
  `/assets/.env` directly on every run.

### BUG-030: Voice note recordings were compounding-truncated
- **Fixed:** 2026-07-14→15, commit `a1ab9bb`
- **Severity:** guest voice notes lost ~10-40% of audio
- **Root cause:** `record_web`'s hand-rolled JS resampler reset its carry-over state on every
  ~43ms flush, dropping samples each time.
- **Fix:** switched to native `MediaRecorder` + `decodeAudioData` → WAV.

### BUG-031: Email-confirmation link signed visitors into the dashboard without a password
- **Fixed:** 2026-07-14→15, commits `13b651c`, `fcead48`
- **Severity:** CRITICAL — anyone holding a forwarded confirmation email could become the host
- **Root cause:** Supabase's confirm link carries session tokens in the URL fragment; the app let
  `Supabase.initialize()` consume it and land the visitor signed-in. A second gap via the PKCE
  `?code=` flow was found on retest.
- **Fix:** capture the launch URL before init, tear down the auto-created session, route to sign-in.

### BUG-032: Signup landed hosts on a dashboard they weren't signed into
- **Fixed:** 2026-07-14
- **Severity:** confusing broken state ("Email: —", zero stats)
- **Root cause:** `signUp()` unconditionally navigated to the dashboard, but email confirmation ON
  returns a user with no session.
- **Fix:** navigation now requires a real session; shows "Confirm your email" otherwise.

### BUG-033: Rapid-fire guest messages produced multiple separate AI replies
- **Fixed:** 2026-07-14
- **Severity:** 3 quick messages got 3 separate answers instead of one
- **Root cause:** no message coalescing existed.
- **Fix:** messages collect and the Brain runs once ~5s after the guest stops typing (Cloud Task
  named per conversation).

### BUG-034: Deleted-listing conversations could still be written to
- **Fixed:** 2026-07-14→15, commit `02e728f`
- **Severity:** a guest could resurrect an archived/deleted-property conversation
- **Root cause:** the web guest-token `deleted_at` check had no Telegram equivalent; the web
  client also writes `messages` directly under a booking JWT, bypassing the backend.
- **Fix:** same guard added before Telegram's first write; `SECURITY DEFINER` RLS function
  (`conversation_property_is_live`) added (a naive RLS join would have silently denied every
  guest insert, since `anon` can't read `properties`).

### BUG-035: A prod RLS function was silently reverted mid-migration
- **Fixed:** 2026-07-16
- **Severity:** guests could write to deleted listings on prod for a window
- **Root cause:** pasting a migration file's own `VERIFY` block (`begin;…rollback;`) alongside its
  DDL into the SQL editor ran as one transaction — the rollback reverted the DDL too, while the
  verify rows still printed PASS in-transaction.
- **Fix:** re-applied DDL only. Lesson: never paste a migration's verify/rollback block with its DDL.

### BUG-036: Telegram local-recommendation questions timed out on cold staging
- **Fixed:** 2026-07-16→17, commits `d2444b1`, `a0c1fdc`
- **Severity:** guest got a timeout message on the web-search second pass
- **Root cause:** on `min=0` staging, a cold instance's first Vertex call hit dynamic-shared-quota
  429s that stacked with the old 2/4/8s retry backoff past the 45s ceiling.
- **Fix:** shortened to jittered ~0.5/1/2s backoff + an UptimeRobot keep-warm ping on staging.

### BUG-037: WhatsApp deep-link parsing nearly shipped broken
- **Fixed:** pre-ship, 2026-07-20, commit `71324b7`
- **Severity:** would have diverted ordinary guest messages down the link-parsing path
- **Root cause:** the booking-ID regex also matched the phrase "check-out".
- **Fix:** required the real booking-ID shape's 6-char final segment; verified against 2,100
  generated IDs.

### BUG-038: WhatsApp test credentials were saved in prod-named secret slots
- **Fixed:** 2026-07-20, commit `71324b7`
- **Severity:** would have made a future prod deploy silently send from a 5-person test number
- **Root cause:** unprefixed secret names mean PROD in this project's convention; test-WABA
  credentials were saved unprefixed.
- **Fix:** re-created as `staging-whatsapp-*`; unprefixed originals deleted.

### BUG-039: Meta WhatsApp phone registration failed with an undocumented server error
- **Fixed:** 2026-09-03 (found 2026-08-27)
- **Severity:** blocked WhatsApp launch entirely
- **Root cause:** Meta-side bug (error `1675030`), confirmed via two independent developer forum
  threads reporting the identical `mid` — the console UI's mutation was broken, not
  account-specific.
- **Fix:** bypassed the console mutation, called the public Graph API endpoint directly
  (`POST /{phone-number-id}/register`).

### BUG-040: WhatsApp webhook verified but no real messages ever arrived
- **Fixed:** 2026-09-03
- **Severity:** blocked WhatsApp going live despite every other check passing
- **Root cause:** the WABA had zero apps subscribed — a manual API-only step with no UI button,
  skipped because registration used the direct-API bypass (BUG-039).
- **Fix:** called `POST /{waba-id}/subscribed_apps` directly.

### BUG-041: WhatsApp verify-token handshake would have silently failed
- **Fixed:** pre-ship, 2026-09-03
- **Severity:** would have broken Meta's webhook handshake on first setup
- **Root cause:** `openssl rand -hex ... > file` leaves a trailing newline; the backend does an
  exact string match with no trim.
- **Fix:** caught before deploying, token regenerated without the newline.

### BUG-042: Password-reset feature would have re-created the exact lockout it fixed
- **Fixed:** pre-ship, 2026-09-03
- **Severity:** would have signed a user out before they could set a new password
- **Root cause:** the existing signup-confirmation-link detection also matched the default
  Supabase password-recovery link shape.
- **Fix:** an explicit `flow=recovery` marker on the redirect URL, mutually exclusive from the
  signup-confirmation path.

### BUG-043: Staging's Auth Site URL pointed at a dead domain
- **Fixed:** 2026-09-07 (root cause: a 2026-07-16→17 rename)
- **Severity:** every Supabase auth email on staging silently fell back to a dead domain
- **Root cause:** staging's frontend domain was renamed but Supabase's Auth URL Configuration
  (Site URL + Redirect URLs) was never updated to match.
- **Fix:** Site URL and Redirect URLs updated live.
- **Regression risk:** any future domain rename — `HEALTH_CHECK_PROTOCOL.md` row 13 covers this
  but isn't scripted yet.

### BUG-044: Property name displayed the literal placeholder "Not specified in listing"
- **Fixed:** 2026-09-08
- **Severity:** confirmed on 2 real properties months apart — not a one-off
- **Root cause:** the scrape prompt licensed that placeholder for Property Name like any other
  optional field; the frontend rendered it verbatim as real data.
- **Fix:** frontend treats the placeholder as null (falls back to nickname); scrape/merge prompts
  mark Property Name non-optional.

### BUG-045: Properties could get stuck at "Ingesting" forever with no recovery
- **Fixed:** 2026-09-08
- **Severity:** stuck 24h+ with no DB write, no retry path; untrained properties could also get a
  guest link that 404'd on first message
- **Root cause:** per-file Gemini calls had no timeout, and the client-disconnect handler skipped
  the status update every other failure path performed.
- **Fix:** 90s hard per-file timeout, `Ingest_Error` written on disconnect with a real Retry
  action; guest-link creation blocked until trained.

### BUG-046: Scraped photo triage results never actually saved
- **Fixed:** 2026-09-09, commit `40c0876`
- **Severity:** the whole photo-triage feature silently no-opped (`curated_photos`/`rejected_photos`
  always 0/0)
- **Root cause:** the scraper's write used `upsert(on_conflict="airbnb_url")` against a column with
  no matching unique constraint (silent Postgres `42P10`); the backend's `save_photo_triage()`
  existed but was never called.
- **Fix:** removed the broken scraper-side write, wired `ingest.py` to call `save_photo_triage`.

### BUG-047: A failed ingest retry lost all previously-completed file progress
- **Fixed:** 2026-09-09→10, commit `f973c3f`
- **Severity:** major — any interrupted ingest forced every retry to reprocess every file
- **Root cause:** `file_fingerprints` persisted only once, at the end of the whole file loop, so
  Cloud Run's 300s request timeout silently discarded already-succeeded progress.
- **Fix:** fingerprints persist immediately per file; a genuine stall now retries (not just 429s);
  partial per-file failures no longer block the whole property.

### BUG-048: A second file was left on a deprecated Gemini model during the 3.8-flash migration
- **Fixed:** 2026-09-10
- **Severity:** same failure class as BUG-006 — 100% ingest failure, zero successful calls logged
  since 2026-09-09
- **Root cause:** the 2026-09-08 migration missed `backend/services/gemini_client.py` (every
  per-file ingest Vision/PDF/audio call), left on `gemini-2.5-pro`.
- **Fix:** updated to `gemini-3.8-flash`, matching the rest of the app. Also found and fixed the
  same gap in `gemini_messenger.py` (chat + summarizer) and the test runner's LLM judge.
- **Regression guard:** `HEALTH_CHECK_PROTOCOL.md` row 1 (`check_model_consistency`) — this is the
  exact class of bug that check exists to catch before it reaches a host again.
