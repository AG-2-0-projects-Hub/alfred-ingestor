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

- [ ] Apply `migrations/2026-09-08_photo_triage.sql` to prod (staging-only so far) — same for `migrations/2026-09-09_host_is_dev_flag.sql`, both deferred to the eventual `staging→main` merge
- [ ] Property training-completeness gauge — rubric already decided (deterministic, not LLM-scored)
- [ ] Host-recorded property walkthrough video
- [ ] Native in-app guide screen (replace the static `guide.html`) — deliberately lowest priority
- [ ] Alfred mascot/persona — own mini-project, Clippy-style riff, 🤖 emoji is the placeholder (queued 2026-09-09)
- [ ] Revisit "Update a Property" — file deletion doesn't retract knowledge, real Airbnb listing changes (photos, house code); wants real beta-tester input first (queued 2026-09-09)
- [ ] Add real sourced stats/fun facts to the Train Now wait popup's rotating card (currently Alfred-capability tips only, no stats — deliberately avoided fabricating numbers) (queued 2026-09-09)

## Done (came off the queue)

- [x] ~~Dev/User (beta) view split for Add Property~~ — shipped 2026-09-09, staging
- [x] ~~Post-training walkthrough panel~~ — shipped 2026-09-09 (Parts A/B/C), staging
- [x] ~~Live E2E test of photo triage through the actual SSE /scrape→/ingest→/merge flow~~ — done 2026-09-09; also surfaced and fixed a real pre-existing bug (curated_photos/rejected_photos weren't persisting)
- [x] ~~Time photo-triage latency on a real 100+-photo listing~~ — attempted 2026-09-09; two real large listings only yielded 7 and 32 candidate photos (Firecrawl's markdown scrape doesn't reach Airbnb's full lazy-loaded gallery) — the "100+" scenario may not be reachable with the current scraping method at all, so treat this as closed unless a different scraping approach comes up
- [x] ~~AI assistant for host support~~ — decided 2026-09-09: no-go, do FAQ instead — see next item
- [x] ~~Restructure `guide.html` into 3 sections + add FAQ~~ — shipped 2026-09-09: tabbed into Add Property / Property Enhancement / Guest Experience / FAQ, Playwright-verified (tab switching, keyboard nav, lightbox)
