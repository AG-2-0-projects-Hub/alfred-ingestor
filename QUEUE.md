# Session Queue

The founder's active, near-term list — what to actually tackle over the next several
sessions, in roughly the order below. Separate from `ROADMAP.md` on purpose: that
document holds everything, "eventually"; this one exists so specific asks don't get
lost among it. Add to this file (not just `ROADMAP.md`) whenever the founder says
"add this to the queue."

**Format:** one line per item, done items struck through with the date, not deleted
(so there's a record of what came off the queue and when). Full rationale/detail for
an item usually lives in `ROADMAP.md` or `CONTEXT.md` — this file stays short by design.

---

## Open

- [ ] 🔴 The alert's "Open full conversation" link shows a **blank, misleading page** to anyone who isn't
      signed in as the property's owner (found 2026-10-02 while verifying the email-alert gate — the
      founder opened the escalation email's link and saw "No messages yet" + Autopilot + "Alfred is
      handling this conversation" for a conversation that is really in `intervene` with a live
      EMERGENCY). Reproduced: same URL as the owner = full thread, Intervene, "Mark Issue as Resolved";
      logged out (fresh browser) = the blank screen. RLS is owner-scoped, so a non-owner/logged-out
      viewer just reads zero rows and the page renders its empty defaults. Real-world trigger: a host
      taps the link on a phone where they aren't signed in, or have a second account signed in — the
      alert's own destination tells them nothing is wrong. Proposed fix (not applied — needs approval,
      FIX_VERIFY): logged out → send to the sign-in screen and return to the same link afterwards;
      signed in but the conversation is unreadable → say "You don't have access to this conversation —
      are you signed in as this property's host?" instead of the empty Autopilot view.
      touches: `frontend/lib/screens/chat_live_screen.dart`, `frontend/lib/main.dart` (routing)
- [ ] 🔴 Walkthrough tip bubbles read as see-through (queued 2026-10-01, founder: **do NOT attempt
      unprompted** — a previous 2-day attempt broke other things and never landed). Known root
      cause: `BoxDecoration` paints `gradient` over `color`, so `GlassPanel`
      (`frontend/lib/widgets/glass_panel.dart`) never renders its tint (only the faint highlight
      gradient shows). It is a shared widget used in 13 places (cards, dialogs, chat), so fixing it
      app-wide changes every glass surface; a walkthrough-only opaque layer is the lower-risk shape.
      The 2026-09-14 attempt that added `ClipPath`+`BackdropFilter`+`CustomPaint` re-triggered the
      yellow-underline text bug — screenshot-check against it before shipping anything here.
      touches: `frontend/lib/widgets/glass_panel.dart`, `frontend/lib/widgets/walkthrough_tip_panel.dart`
- [ ] 🟡 guide.html screenshot rework (carried over from the 2026-09-21 handoff, parked 2026-10-01
      as not merge-connected): highlight boxes off-target/cutting into fields, no glow, one
      lightbox opens the wrong image, Step 2 shot inside the wrong callout, Knowledge tab should be
      ONE screenshot with 3 highlights, blurry step-1 shot, step 7 crop cuts off the Send box. Full
      detail + the process lessons: `_Context/HANDOFF_guide-screenshots-and-conflict-error_2026-09-21.md`.
      Must use FIX_VERIFY. touches: `frontend/web/guide.html`
- [ ] 🟡 Feedback dialog (beta-tester report, 2026-07-12, triaged as FT-WF-001/002, S3): message text
      overlaps the Cancel/Send buttons; category chips unreadable in dark mode; reporter also
      suggests dropping Cancel. Detail: `_Context/feedback_triage/2026-09-28_webapp-feedback.md`.
      touches: `frontend/lib/widgets/feedback_dialog.dart`
- [ ] 🟡 Scraper residue after the dead-upsert removal (2026-10-01): `scraper/requirements.txt`
      still lists `supabase` and the scraper Cloud Run services still carry
      `INGESTOR_SUPABASE_URL`/`INGESTOR_SUPABASE_SERVICE_KEY`, both unused now. Drop them in a
      dedicated change (removing the dep can shift transitive pins, so test the scraper build).
      touches: `scraper/requirements.txt`
- [ ] 🟡 Vertex 429 during the merge step (Sentry ALFRED-BACKEND-2, 2026-10-01, staging, from the B1
      E2E run): the task retried and the run completed, so it is the known dynamic-shared-quota
      transient, not a new bug — watch whether it recurs under real beta load (ROADMAP Track 1's
      "Vertex-transport watch"). touches: `backend/routers/ingest_worker.py`
- [ ] 🟡 Server-side file-type filter for ingest (founder-flagged 2026-10-01). The UI already rejects
      unsupported types (drop zone + file picker use one allow-list, plus a 15 MB cap — B7 covers
      it), but it checks the **extension only**, and the backend has no filter at all:
      `file_processor.process_file` sends any unrecognised extension to Gemini as "plain text"
      (`data.decode("utf-8", errors="replace")`). So a file that skips the UI, or a renamed one
      (`x.exe` → `x.pdf`/`x.txt`), reaches the model as garbage and burns a call. Proposal: an
      allow-list in `process_file` that marks the file `failed` with a clear message instead of
      the plain-text fallback, plus a cheap content check (magic bytes for pdf/images/docx; valid
      UTF-8 for txt/json/csv) and the same 15 MB cap enforced server-side. Keep the allow-list in
      one place so the frontend list can't drift from it. Needs FMEA + a scenario (B7's backend twin).
      touches: `backend/services/file_processor.py`, `backend/routers/ingest.py`, `backend/routers/ingest_worker.py`, `frontend/lib/widgets/drop_zone.dart`
- [ ] 🟡 Auth gaps on property endpoints (found 2026-10-01 while verifying G5; **pre-existing, also on
      `main`**, not introduced by the merge): `POST /api/merge/{id}`, `/api/resolve/{id}`,
      `/api/ingest/add-knowledge`, `/api/ingest/query-knowledge` and the `/api/ingest` dispatcher have
      no auth at all (live-confirmed: an unauthenticated call reaches the handler and gets a 404/422,
      not a 401), and `/ingest/{id}/resume` + `/retry-scrape` check the token but not that the caller
      owns the property. The only protection is that property UUIDs are unguessable — **but a guest
      can read it** (RLS policies "guest reads own booking"/"guest reads own conversation" let a
      guest's booking JWT select their own `guests`/`conversations` row, which carries
      `property_id`; a technically skilled guest could pull it from the REST API). Corrected
      2026-10-02 — it is more than "burn Gemini calls": with a property UUID, **no login** needed:
      `add-knowledge` WRITES text into the property's `master_json` (Alfred then answers guests from
      it — fake door code / rules injection) and returns the whole knowledge base; `merge`/`resolve`
      return `master_json` for an already-processed property; `query-knowledge` reads it. And any
      **logged-in** host who knows another property's UUID can call `retry-scrape` to overwrite its
      Airbnb URL and re-run it. **Reproduced live on staging 2026-10-02 (FIX_VERIFY Step 0, run twice):**
      anonymous `add-knowledge` stored a fake door code in `master_json`; anonymous `/api/ingest` with an
      existing property's UUID overwrote its name and started a run (`insert_property` upserts name/URL
      and the dispatcher has no ownership check); `resume` with another host's property returned 200.
      Likelihood low (needs a tech-savvy guest/host), impact real — do it
      before the beta widens. Proposal: one shared `_require_host` + `host_owns_property` guard like
      `messages.py` already uses; keep anonymous `/ingest` only if the add-property flow truly needs it.
      Needs FMEA (the anonymous-ingest path was deliberate) + extend G5. touches: `backend/routers/ingest.py`, `backend/routers/merge_resolve.py`
- [x] ~~🔴 Escalation-email confirmation gate + Telegram-style UI~~ — **shipped to prod 2026-10-02** (PR #11
      `203fba6`, feature `19e5a5f`; FIX_VERIFY; founder-verified on staging and prod). Double opt-in: request →
      e-mailed one-time link → owner presses Confirm → alerts start; alerts only ever go to a confirmed address;
      a DB trigger stops a host session writing the alert columns directly; token stored hashed; 48 h expiry;
      60 s/host + 10 min/address cooldowns; prod's one enabled host was reset to re-confirm. P9 rewritten, P10
      added. Leftover ceiling: confirmation mails come from a Gmail single sender, so they may land in spam until
      the domain is authenticated (`ROADMAP.md` M2) — the "How to use" panel carries the Not-spam tip.
- [ ] 🟡 Stay dates on a guest (founder 2026-10-02): where the host creates/handles a guest — the
      conversation window (the red-bubble live chat) — add fields to enter/display the guest's
      **check-in and check-out date**. The check-in/out *times* already come from the scraped/ingested
      property data; the *dates* are per stay, entered manually for now (later pulled from Airbnb's
      reservation info). Purpose: Alfred can answer "when do I check out?" with the real date, and the
      chat **disconnects 24 h after check-out** (founder: a grace window for follow-ups, forgotten
      items, feedback). **Existing pieces found 2026-10-02:** `guests.check_in`/`check_out` columns
      already exist; `create_guest` fills them with TESTING defaults (now / now+96h, "until Channex
      feeds real dates"); an hourly pg_cron job `auto-archive-conversations` archives a conversation
      once `check_out < now()` (dashboard archive only — a new guest message revives it, so the guest
      is never actually cut off); and the old Make.com bot had the real behaviour
      (`_Context/Supabase Alfred Airbnb - E - The Bot.blueprint.json`, route filter "Expired booking":
      `check_out_date < addDays(now; -1)` → no AI answer; guest gets "Your stay has ended. I have
      forwarded your message directly to the host." and the host gets a Telegram "[EXPIRED] Guest X:
      <message>" via the property's host) — **the native port never carried it over**. ⚠️ Gotcha: every
      existing guest has a synthetic check_out, so enforcing the cutoff blindly would lock real
      guests out ~5 days after link creation — enforce only for explicitly entered dates (e.g. make the
      defaults null or add a "dates confirmed" flag). Open: enter at link-creation time or inside the
      live-chat window (or both)?; expired-reply channels (web/Telegram/WhatsApp) and host alert
      channel (Telegram/email); time zone of check-out. Likely needs a small `guests` migration.
      touches: `frontend/lib/widgets/chat_live_dialog.dart`, `frontend/lib/widgets/generate_guest_link_dialog.dart`, `backend/routers/messages.py`, `backend/services/gemini_messenger.py`
- [ ] 🎯 PRIORITY (founder-flagged 2026-09-22): PWA redesign/reformatting/migration. Current web UI
      feels crowded, especially on mobile — a UI draft already exists in Google Stitch. Checked: the
      PWA plumbing itself is basically already in place (`frontend/web/manifest.json` has
      `display: standalone`, Flutter web already registers a service worker) — the real work is a
      responsive layout pass across the dashboard/chat screens. Also directly shortens a future
      native Android/iOS build later (same Flutter codebase, same widgets). Founder is working the
      Stitch draft during the week; not urgent, but goes first when picked up.
- [x] ~~Host-uploaded-document ingestion leg + merge step reconciliation reframing~~ — shipped
      2026-09-28, staging `1610f1e` (ingestion: grounding rules on all 4 prompts, zip-corruption
      pandas fix, multi-file separator fix) + `604570f` (merge: grounding rules ported +
      `_guard_coordinates`/`_verify_grounded_strings` structural guards). Full 3-leg redesign plan:
      `C:\Users\San_8\.claude\plans\fluffy-riding-feigenbaum.md`. Measured: ingestion's one real
      baseline bug (weekday/weekend overgeneralization) 30%→0/10; merge recall 77%→89% combined,
      0/100 hallucination, 0 fabricated coordinates across two N=5 rounds each. Both have permanent
      smoke tests (`_INGESTION_GROUNDING_TEST`, extended `_UNIVERSAL_FIELDS_TEST`).
- [x] ~~Phase 2 — ground the freeform merge (MERGER_SYSTEM_PROMPT, the bulk of master_json,
      untouched by the item above)~~ — shipped 2026-09-28, staging (commit pending founder
      approval). Full-document fidelity testing (not narrow field fixtures) across the 5 existing
      fixtures + a real trained property's actual documents (Bungalow), 2 independent rounds,
      judged by Claude subagents after an initial cheap OpenRouter judge proved unreliable on long
      documents. One real fix confirmed (Casa Tulum: eliminated a fabricated conflated
      "years_hosting" number + an invented alternate-name guess); every other case a wash, 0
      hallucinations both conditions, no regressions. Also validated multi-file aggregation and
      voice-note end-to-end fidelity, both PASS. New permanent smoke test: `_FREEFORM_MERGE_TEST`.
      touches: `backend/services/gemini_merge_resolve.py`
- [ ] 🔵 Low priority (found 2026-09-28 during Phase 2 fidelity testing, identical in old and new
      merge prompts so unrelated to the grounding fix above): the merge sometimes drops a host's
      "hosting since [year]" fact entirely (seen across several fixtures, ~1 in 2 runs) — likely a
      merge-prompt/schema coverage gap, not a hallucination-guard issue. One run also dropped an
      entire safety-alarms category (smoke/CO alarm, camera) that was present in source — same in
      both baseline and fixed, so a separate, intermittent omission bug worth a dedicated look.
      touches: `backend/services/gemini_merge_resolve.py`
- [x] ~~Phase 3/4 — real-property ingestion + full old-vs-new pipeline testing, root-cause fixes,
      self-grounding critique pass~~ — shipped 2026-09-29, staging (`853af45`, `7b91b6f`, `381085a`,
      `d69402c`, `1a203f8`, `612fbdf`). Tested against 3 real trained properties' actual uploaded
      documents (not synthetic fixtures) at both the ingestion leg and the full scraper+ingestion+
      merge pipeline. Found and fixed, all validated 2+ independent real-Gemini rounds against real
      data: (1) ingestion collapsing a conditional/relative rule ("code sent 1hr before YOUR
      arrival") onto an unrelated nearby absolute; (2) ingestion over-cautious on a legitimate
      in-document identity inference (host's name only ever appears via repeated guest address,
      never self-declared); (3) merge-level fabrication (Sta Prisca: invented bathroom shower) —
      fixed with a new self-grounding critique pass (`_ground_freeform_output`, one extra
      schema-free Gemini call auditing the freeform merge output against its own source); (4) merge
      conflict-detection bundling a settled multi-tier fact with a genuinely disputed value into
      one conflict blob, traced to the prompt's own misleading worked example; (5) a real JSON-mode
      gap causing an outright crash on a malformed response, no retry; (6) large real PDF (~5MB)
      borderline on the ingestion timeout, now size-aware (>3MB gets a single 70s attempt). Two
      other suspected regressions (Sta Prisca WiFi-photo fact, Dos Rios no-Airbnb-account policy)
      did NOT reproduce on re-test — logged as non-issues, not silently dropped. New permanent
      tests: `_CONFLICT_SCOPING_TEST`, `_GROUNDING_CRITIQUE_TEST`. Also added a Root-Cause-It-First
      step to `FIX_VERIFY_PROTOCOL.md` (Step 0) codifying the methodology used throughout. Full
      writeup: `C:\Users\San_8\.claude\plans\fluffy-riding-feigenbaum.md`.
      touches: `backend/services/gemini_client.py`, `backend/services/gemini_merge_resolve.py`
- [ ] 🔵 Low priority: Prompt C (audio) and Prompt D (spreadsheet) ingestion grounding rules are
      only validated against synthetic fixtures — none of the 3 real properties used for Phase 3/4
      testing had audio or spreadsheet uploads. Real-document validation for those 2 paths remains
      an open gap whenever a real property with that upload type is available to test against.
      touches: `backend/services/gemini_client.py`
- [ ] 🔵 Maybe (founder-flagged 2026-09-28, low priority — still in Beta, no urgency): backfill/
      re-verify already-trained properties' stored `master_json` against the new grounding guards.
      The ingestion+merge grounding fix above only prevents *future* merges from fabricating
      data — it doesn't retroactively clean properties trained before it shipped. Confirmed one
      real (though more nuanced than first thought) example while validating the fix: property
      "Bungalow" (staging `e6d4f0c6-6ca1-4622-9559-e21f0b4a80f6`) has a `security_gate_code: "XXXX"`
      placeholder sitting in its stored `ingested_markdown`, predating this fix — would need
      re-ingesting the host's original photo through the now-fixed Prompt B to resolve, not just a
      re-merge. Needs explicit approval before touching any already-trained production/staging data.
- [ ] 🔴 Train Now UX — partially resolved: a Delete button now exists on the dashboard card to
      wipe a stuck property and clear the card, closing the original "no recovery action at all"
      complaint (root cause + history: `_Context/Train_Now_Reliability_and_QA_Process_Plan_
      2026-09-15.md` item 3). Remaining, not yet scoped: broader UX issues around the wait
      dialog/dashboard card during a long-running Train Now (no progress view, no "resume
      watching") — founder wants a full UX/UI audit eventually, not a piecemeal fix. Low priority
      until that audit happens.
      touches: `frontend/lib/screens/dashboard_screen.dart`, `frontend/lib/widgets/training_wait_dialog.dart`
      ("Recovery path for a genuinely stuck backend") — not yet implemented, this is the same issue
      surfacing again, not a new one.
- [ ] Wire prod support into `_tests/health/run_health_check.py` — needs a separate `.env.prod` file for `PROD_BACKEND_URL`/`PROD_SCRAPER_URL` etc. (not just prefixed vars in `.env.test`); the 4 Gemini smoke checks no longer need a separate prod variant — they moved to Vertex/ADC on 2026-09-10 and that transport is already shared by staging + prod
- [ ] Schedule the doc-staleness sweep (`HEALTH_CHECK_PROTOCOL.md` row 17) as a periodic agent pass — no mechanism exists yet, currently manual-only
- [ ] Rotate the Firecrawl API key that got displayed in a session transcript 2026-09-10 (founder-flagged)
- [ ] Rotate the 2 Vercel account tokens exposed in a session transcript 2026-09-15 (founder-flagged) —
      `ingestor-staging-vercel-token` (scope: alfred-staging) and `ingestor-prod-vercel-token` (scope:
      alwaysalfred), both created Sep 3, used by `_mcp_profiles/global.json`'s `vercel-the-ingestor`/
      `vercel-the-ingestor-prod` MCP entries (Vercel's official remote MCP, `mcp.vercel.com`). Exposed
      via a broken ad-hoc `grep|sed` redaction attempt — see `lessons.md`'s 2026-09-15 entry (flagged
      as a Global Candidate) for the structural fix now in place. Revoke both on Vercel's Account →
      Tokens page, create replacements,
      hand new values to Claude via the usual Desktop `.txt` drop for `_mcp_profiles/global.json` update.
- [ ] Rotate `_tests/fixtures/.env.test` test credentials — exposed TWICE now, deferred both times:
      (1) 2026-09-10, printed in full in a session transcript (`GEMINI_API_TEST_KEY`, `VERCEL_API_TOKEN`,
      `VERCEL_BYPASS_TOKEN`, `TELEGRAM_BOT_TOKEN_TEST`, `WHATSAPP_ACCESS_TOKEN_TEST`, `FIRECRAWL_API_KEY_TEST`
      — a `cat`+`sed` redaction only covered the password field); (2) 2026-09-19, the same file exposed
      again via a plain `Read` tool call (same set, plus `TEST_HOST_PASSWORD` this time) — founder
      re-confirmed deferring rather than rotating, but asked for a real mechanical safeguard against a third
      recurrence rather than relying on memory alone (see the PreToolUse hook added the same session,
      `.claude/hooks/block-secret-reads.*` — blocks Read/cat/grep/etc. on paths matching `.env`/secret/
      credential/fixtures patterns repo-wide, not just a documented convention). If this file gets exposed a
      third time despite the hook, that's the actual signal to stop deferring and rotate for real.
- [ ] Rotate `SUPABASE_SERVICE_ROLE_KEY` for staging (project `gcxxilzfhwlsjcvtpsvj`), printed in full in a
      session transcript 2026-09-16 by a plain `grep` of `backend/.env` (same ad-hoc-redaction failure
      class as the other rows here, structural fix already in place per `lessons.md`'s 2026-09-15 entry —
      it just wasn't applied this time). Rotate on Supabase dashboard → staging project → Project Settings
      → API, then update `backend/.env` and the `alfred-backend-staging` Cloud Run service env var with
      the new value.
- [ ] New file dropped in Edit Property's "Manage" → "Add New Files" for an already-trained property sits stuck at "Queued" forever — no retrain/update ever triggers (found 2026-09-10, live on staging, Bungalu property). Related to but distinct from the Train Now reliability plan (`_Context/Train_Now_Reliability_and_QA_Process_Plan_2026-09-15.md`) — different mechanism (nothing ever triggers, not a timeout/recovery gap during a run) — worth a look in the same pass regardless.
- [x] ~~Apply `migrations/2026-09-08_photo_triage.sql` and `migrations/2026-09-09_host_is_dev_flag.sql` to prod~~ — already on prod (verified 2026-10-01: `curated_photos`, `rejected_photos`, `scrape_retry`, `ingest_run_id`, `host_profiles.is_dev`, `welcome_modal_seen` all present; per-table column hashes match staging).
- [ ] Property training-completeness gauge — rubric already decided (deterministic, not LLM-scored)
- [ ] Host-recorded property walkthrough video
- [ ] Native in-app guide screen (replace the static `guide.html`) — deliberately lowest priority
- [ ] Alfred mascot/persona — own mini-project, Clippy-style riff, 🤖 emoji is the placeholder (queued 2026-09-09)
- [ ] Revisit "Update a Property" — file deletion doesn't retract knowledge, real Airbnb listing changes (photos, house code); wants real beta-tester input first (queued 2026-09-09)
- [ ] Add real sourced stats/fun facts to the Train Now wait popup's rotating card (currently Alfred-capability tips only, no stats — deliberately avoided fabricating numbers) (queued 2026-09-09)
- [ ] guide.html: add a section on exporting Airbnb's listing JSON directly (the "goldmine" method), plus a simple copy-paste-into-a-doc (.txt/.docx/PDF) fallback for non-technical hosts — deferred pending the exact export steps from the founder (queued 2026-09-21)
- [ ] Update the feedback-widget workflow (currently: `feedback_dialog.dart` inserts straight into Supabase's `feedback` table via RLS, nothing reads or surfaces it anywhere) — founder already designed a protocol for this in the reflip project that's working well there and wants to use it as inspiration here (queued 2026-09-21)
- [x] ~~New-account signup never sent a confirmation email~~ — resolved 2026-10-01, not a bug: signing up with an already-registered email makes Supabase return a user with `identities: []` and no session and send nothing (anti-enumeration). Reproduced live on staging; `auth_screen.dart` already detects exactly that and shows the "Email already registered" notice (2026-09-21). Prod has 5 confirmed real users, so genuine confirmation emails work.
- [ ] Property/document match-check (queued 2026-09-19, deliberately parked as its own design
      problem — not part of the 2026-09-19 UI/UX batch): verify that uploaded supporting documents
      (house manual, WiFi photo, etc.) actually belong to the property they're attached to, rather
      than trusting whatever the host drops in — e.g. catch a host accidentally uploading a
      different property's manual. Needs its own FMEA/Plan-Mode pass before scoping: how to
      actually detect a mismatch (address/name matching against `master_json`? a Gemini
      cross-check pass over the doc vs. the scraped listing?), what a false positive costs the host
      (a wrongly-flagged real document), and whether it blocks training or just warns.
- [ ] Anonymized guest-conversation training database (mini-project, queued 2026-09-19) — separate store of past guest conversation logs (beyond per-property knowledge) for eventual model fine-tuning. Needs its own design pass before scoping: a disclaimer shown to the host before upload explaining conversations will be anonymized, a full anonymization pass on names, and explicit detection + removal/flagging of payment and contact info (card numbers, phone, email) before anything lands in the training store. Retention policy and storage location undecided.

## Done (came off the queue)

- [x] ~~Country/location extraction reliability -- scraper JSON-native rewrite~~ — shipped
      2026-09-28. Retired `scraper/GEMINI_PROMPT_AIRBNB.md` (a Make.com formatting workaround, not
      a real requirement) entirely; the scraper's own Gemini call is now `response_schema`-
      constrained JSON (`SCRAPER_STRUCTURED_SCHEMA`, `scraper/main.py`) instead of free-text
      markdown, so there's no lossy prose intermediate left for the merge step to re-parse.
      Empirically verified against a real comparison harness (old pipeline vs. new, same fixtures,
      two independent N=5 rounds, 25 runs/path/round): location recall 58-60% → **100%** (100/100
      across both rounds); the documented Otago world-knowledge-leakage hallucination, 1/25 old-path
      runs → **0/50** new-path runs across both rounds. Found and fixed 2 real gaps during a direct
      old-vs-new side-by-side (not just the aggregate score): `meta.language_detected`/
      `data_completeness` were coming back empty (added an explicit self-assess-always rule) and
      `emergency_contact` had no dedicated field (added one, matching the merge step's own
      top-level field) — re-verified clean after both fixes. Added a permanent smoke test
      (`_SCRAPER_STRUCTURED_TEST` in `scraper/main.py`, mirrors `_UNIVERSAL_FIELDS_TEST`'s
      pattern) so this doesn't regress silently later. Also fixed a real downstream break this
      surfaced: `ingest_worker.py`'s `_parse_thumbnail_url` regexed markdown bold syntax that no
      longer exists in the new JSON output — would have silently broken hero-image upload for
      every future scrape; now parses `media.thumbnail_url` from the JSON directly. `scraped_markdown`
      DB column name kept as-is (now holds a JSON string, not markdown — deliberate, to avoid a
      migration + multi-file rename on top of an already-large change). Full investigation log +
      cross-LLM consultation + responses: `_Context/Universal_Fields_Extraction_Reliability_
      Investigation_2026-09-25.md` (gitignored, local only). Two real follow-ups spun off into
      their own Open items above (host-document ingestion leg, merge step's reconciliation-call
      reframing) rather than scope-creeping into this change.
- [x] ~~User-mode Add Property "Ingest" vs "Train Now" button label~~ — closed 2026-09-16, never
      actually broken: `widget.isDev ? 'INGEST NOW' : 'TRAIN NOW'` has been in the code unchanged
      since the original dashboard commit (`721dd3e`); the 2026-09-15 flag was a false read, not a
      real regression
- [x] ~~Confirm the Sep 10 deprecated-model fix works end-to-end~~ — superseded 2026-09-16: far
      beyond confirmed via extensive live retraining this session, and the model has since moved
      again (`gemini-3.8-flash` → `gemini-3.6-flash`, staging `889e83f`) per
      `_Context/Train_Now_Reliability_and_QA_Process_Plan_2026-09-15.md` item 8. Ongoing Train Now
      reliability is now tracked via the 🔴 item at the top of Open, not this one.

- [x] ~~Telegram "Disconnect" feature~~ — shipped 2026-09-25, staging `d90724e`, FIX_VERIFY'd with
      a real Playwright scenario (`p8.ts`, commit `aca57b9`), pushed to staging
- [x] ~~Write the missing `_UNIVERSAL_FIELDS_TEST`~~ — shipped 2026-09-25, staging `0c67f81`,
      pushed. Running it for real surfaced a much bigger reliability problem than expected — see
      the new "Country/location extraction reliability" item above, still open
- [x] ~~Guest hostility/profanity doesn't reliably escalate~~ — fixed 2026-09-25, staging
      `a9f1dc0`, FIX_VERIFY'd (real Gemini calls, founder's exact 2 failing messages + an 8-message
      battery, before/after, zero regressions), pushed. Root cause: Category 4's exclusion clause
      required both "no target" AND "no clear anger" to skip escalation; repeated/emphasized
      profanity with no target was wrongly treated as insufficient on its own
- [x] ~~Wire up Sentry error tracking (backend + frontend + scraper)~~ — shipped 2026-09-25,
      staging `4bcdbb9`. 3 new Sentry projects under org `alonso-vazquez-ng` (`alfred-backend`,
      `alfred-scraper`, `alfred-frontend`), gated on empty `SENTRY_DSN` = off (same convention as
      reflip). Went beyond bootstrap: added explicit `capture_exception()` at every existing
      except block across `ingest_worker.py`/`gemini_merge_resolve.py`/`telegram.py`/
      `whatsapp.py`/`scraper/main.py` that previously only logged and swallowed a real failure —
      the same silent-failure pattern behind the 2026-09-21 resolver `call_timeout` incident that
      motivated this item. Live-verified end-to-end for all 3 projects: real
      `capture_message()`/triggered-error events sent and confirmed server-side via the Sentry
      MCP, including a real Playwright-triggered uncaught error proving `SentryFlutter.init`'s
      automatic zone-based capture actually fires (not just present in the bundle). `SENTRY_DSN`/
      `ENVIRONMENT` set on all 4 Cloud Run services + both Vercel projects; `alfred-backend-staging`/
      `alfred-scraper-staging` redeployed and health-checked live. Prod Cloud Run deploys on the
      `staging→main` merge via the `deploy-prod-on-main` Cloud Build trigger (corrected
      2026-10-01 — this line used to say there was no auto-deploy) — frontend prod deploys via
      Vercel's normal auto-deploy-on-push.
- [x] ~~Overview tab manual walkthrough replay toggle~~ — shipped 2026-09-10, staging `6835304`, Playwright-verified live
- [x] ~~Dev/User (beta) view split for Add Property~~ — shipped 2026-09-09, staging
- [x] ~~Post-training walkthrough panel~~ — shipped 2026-09-09 (Parts A/B/C), staging
- [x] ~~Live E2E test of photo triage through the actual SSE /scrape→/ingest→/merge flow~~ — done 2026-09-09; also surfaced and fixed a real pre-existing bug (curated_photos/rejected_photos weren't persisting)
- [x] ~~Time photo-triage latency on a real 100+-photo listing~~ — attempted 2026-09-09; two real large listings only yielded 7 and 32 candidate photos (Firecrawl's markdown scrape doesn't reach Airbnb's full lazy-loaded gallery) — the "100+" scenario may not be reachable with the current scraping method at all, so treat this as closed unless a different scraping approach comes up
- [x] ~~AI assistant for host support~~ — decided 2026-09-09: no-go, do FAQ instead — see next item
- [x] ~~Restructure `guide.html` into 3 sections + add FAQ~~ — shipped 2026-09-09: tabbed into Add Property / Property Enhancement / Guest Experience / FAQ, Playwright-verified (tab switching, keyboard nav, lightbox)
- [x] ~~Investigate the parallel-session files found 2026-09-10 (`welcome.py`, `property_card.dart`)~~ — resolved 2026-09-10: this session's own work (guest-link 500 crash + Step 0 overlap fixes), committed `a7a103a`, deployed to staging
