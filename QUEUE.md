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

- [x] ~~User-mode Add Property "Ingest" vs "Train Now" button label~~ — closed 2026-09-16, never
      actually broken: `widget.isDev ? 'INGEST NOW' : 'TRAIN NOW'` has been in the code unchanged
      since the original dashboard commit (`721dd3e`); the 2026-09-15 flag was a false read, not a
      real regression
- [x] ~~Confirm the Sep 10 deprecated-model fix works end-to-end~~ — superseded 2026-09-16: far
      beyond confirmed via extensive live retraining this session, and the model has since moved
      again (`gemini-3.8-flash` → `gemini-3.6-flash`, staging `889e83f`) per
      `_Context/Train_Now_Reliability_and_QA_Process_Plan_2026-09-15.md` item 8. Ongoing Train Now
      reliability is now tracked via the 🔴 item at the top of Open, not this one.

- [x] ~~Overview tab manual walkthrough replay toggle~~ — shipped 2026-09-10, staging `6835304`, Playwright-verified live
- [x] ~~Dev/User (beta) view split for Add Property~~ — shipped 2026-09-09, staging
- [x] ~~Post-training walkthrough panel~~ — shipped 2026-09-09 (Parts A/B/C), staging
- [x] ~~Live E2E test of photo triage through the actual SSE /scrape→/ingest→/merge flow~~ — done 2026-09-09; also surfaced and fixed a real pre-existing bug (curated_photos/rejected_photos weren't persisting)
- [x] ~~Time photo-triage latency on a real 100+-photo listing~~ — attempted 2026-09-09; two real large listings only yielded 7 and 32 candidate photos (Firecrawl's markdown scrape doesn't reach Airbnb's full lazy-loaded gallery) — the "100+" scenario may not be reachable with the current scraping method at all, so treat this as closed unless a different scraping approach comes up
- [x] ~~AI assistant for host support~~ — decided 2026-09-09: no-go, do FAQ instead — see next item
- [x] ~~Restructure `guide.html` into 3 sections + add FAQ~~ — shipped 2026-09-09: tabbed into Add Property / Property Enhancement / Guest Experience / FAQ, Playwright-verified (tab switching, keyboard nav, lightbox)
- [x] ~~Investigate the parallel-session files found 2026-09-10 (`welcome.py`, `property_card.dart`)~~ — resolved 2026-09-10: this session's own work (guest-link 500 crash + Step 0 overlap fixes), committed `a7a103a`, deployed to staging
