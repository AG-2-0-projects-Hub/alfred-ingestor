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

- [ ] 🎯 PRIORITY (founder-flagged 2026-09-22): PWA redesign/reformatting/migration. Current web UI
      feels crowded, especially on mobile — a UI draft already exists in Google Stitch. Checked: the
      PWA plumbing itself is basically already in place (`frontend/web/manifest.json` has
      `display: standalone`, Flutter web already registers a service worker) — the real work is a
      responsive layout pass across the dashboard/chat screens. Also directly shortens a future
      native Android/iOS build later (same Flutter codebase, same widgets). Founder is working the
      Stitch draft during the week; not urgent, but goes first when picked up.
- [ ] Consider JSON-native for the host-uploaded-document ingestion leg too (`ingested_markdown`,
      from PDFs/docs hosts upload) — opened 2026-09-25, scoped as its own mini-project 2026-09-28.
      Checked `file_processor.py`: **not** pure deterministic parsing as originally assumed — PDFs/
      images/audio each go through their own Gemini call ("Prompt A/B/C/D") that restructures
      content into markdown before it ever reaches the merge step, the same architectural shape
      the scraper's old design had. Real reason to suspect the same placeholder/hallucination bug
      class could live here too, not just a symmetry nice-to-have — investigate before deciding.
- [ ] Merge step's `_extract_universal_fields` call: now that the scraper produces clean typed
      JSON directly (see Done below), this call's job shifts from "extract canonical fields from
      prose" to "reconcile scraper's JSON against the host's ingested doc" — same quote-first/
      evidence-grounding principle applied one level up, not yet done. Free optimization noted:
      when a property has zero ingested files (scrape-only), this call is pure redundant
      re-derivation of what the scraper JSON already has and could just short-circuit to a
      pass-through. Opened 2026-09-28, not scoped/tested yet.
- [ ] 🔴 Train Now leaves the host stranded with no recovery action when a run takes longer than
      expected: the wait dialog's own safety-timeout message ("still working, check the dashboard")
      dumps them back on the plain form with only a "Train Now" button — no way to check progress,
      resume watching, or know if it's really still running vs. dead. The dashboard card then just
      shows "Processing…" with nothing clickable, for however long it takes (minutes, possibly
      longer). Recurring, founder-flagged live 2026-09-15/16 across multiple real runs. Root cause +
      full context: `_Context/Train_Now_Reliability_and_QA_Process_Plan_2026-09-15.md` item 3
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
- [ ] Apply `migrations/2026-09-08_photo_triage.sql` to prod (staging-only so far) — same for `migrations/2026-09-09_host_is_dev_flag.sql`, both deferred to the eventual `staging→main` merge
- [ ] Property training-completeness gauge — rubric already decided (deterministic, not LLM-scored)
- [ ] Host-recorded property walkthrough video
- [ ] Native in-app guide screen (replace the static `guide.html`) — deliberately lowest priority
- [ ] Alfred mascot/persona — own mini-project, Clippy-style riff, 🤖 emoji is the placeholder (queued 2026-09-09)
- [ ] Revisit "Update a Property" — file deletion doesn't retract knowledge, real Airbnb listing changes (photos, house code); wants real beta-tester input first (queued 2026-09-09)
- [ ] Add real sourced stats/fun facts to the Train Now wait popup's rotating card (currently Alfred-capability tips only, no stats — deliberately avoided fabricating numbers) (queued 2026-09-09)
- [ ] guide.html: add a section on exporting Airbnb's listing JSON directly (the "goldmine" method), plus a simple copy-paste-into-a-doc (.txt/.docx/PDF) fallback for non-technical hosts — deferred pending the exact export steps from the founder (queued 2026-09-21)
- [ ] Update the feedback-widget workflow (currently: `feedback_dialog.dart` inserts straight into Supabase's `feedback` table via RLS, nothing reads or surfaces it anywhere) — founder already designed a protocol for this in the reflip project that's working well there and wants to use it as inspiration here (queued 2026-09-21)
- [ ] New-account signup never sent a confirmation email — founder tried creating a second test account (to test the first-time welcome/walkthrough flow) and never received it. Not investigated yet; likely Supabase Auth email delivery/config, not app code, but confirm before assuming (queued 2026-09-21)
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
      `alfred-scraper-staging` redeployed and health-checked live. Prod Cloud Run still needs its
      own manual `gcloud run deploy --source` after the next `staging→main` merge (no auto-deploy
      on this project, confirmed via `CONTEXT.md`'s existing note) — frontend prod deploys via
      Vercel's normal auto-deploy-on-push.
- [x] ~~Overview tab manual walkthrough replay toggle~~ — shipped 2026-09-10, staging `6835304`, Playwright-verified live
- [x] ~~Dev/User (beta) view split for Add Property~~ — shipped 2026-09-09, staging
- [x] ~~Post-training walkthrough panel~~ — shipped 2026-09-09 (Parts A/B/C), staging
- [x] ~~Live E2E test of photo triage through the actual SSE /scrape→/ingest→/merge flow~~ — done 2026-09-09; also surfaced and fixed a real pre-existing bug (curated_photos/rejected_photos weren't persisting)
- [x] ~~Time photo-triage latency on a real 100+-photo listing~~ — attempted 2026-09-09; two real large listings only yielded 7 and 32 candidate photos (Firecrawl's markdown scrape doesn't reach Airbnb's full lazy-loaded gallery) — the "100+" scenario may not be reachable with the current scraping method at all, so treat this as closed unless a different scraping approach comes up
- [x] ~~AI assistant for host support~~ — decided 2026-09-09: no-go, do FAQ instead — see next item
- [x] ~~Restructure `guide.html` into 3 sections + add FAQ~~ — shipped 2026-09-09: tabbed into Add Property / Property Enhancement / Guest Experience / FAQ, Playwright-verified (tab switching, keyboard nav, lightbox)
- [x] ~~Investigate the parallel-session files found 2026-09-10 (`welcome.py`, `property_card.dart`)~~ — resolved 2026-09-10: this session's own work (guest-link 500 crash + Step 0 overlap fixes), committed `a7a103a`, deployed to staging
