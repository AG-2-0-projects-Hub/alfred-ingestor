-- 2026-09-08 — Gemini Vision photo triage (scraper)
--
-- STATUS
--   staging (gcxxilzfhwlsjcvtpsvj) : APPLIED via MCP 2026-09-08, verified PASS
--   prod    (ylaooctefesedrecshic) : NOT YET APPLIED — run alongside the eventual staging→main merge
--
-- Every migration must be applied to BOTH projects (post-split rule, CONTEXT.md).
--
-- WHY
--   Airbnb-scraped photos were never actually looked at — the scraper only
--   regexed image URLs out of Firecrawl's raw markdown and listed them
--   verbatim, no visual judgment. Host-uploaded photos already get real
--   Gemini Vision analysis (file_processor.py's _process_image); scraped
--   photos did not. A two-phase triage (cheap low-res pass over every photo,
--   then a careful full-res pass on a curated ~20) now classifies and
--   room-labels them before they're trusted as training data.
--
--   Stored as structured JSONB rather than more scraped_markdown prose —
--   avoids regex-parsing an LLM's markdown output to consume this data, and
--   scraped_markdown's own Image Gallery section is left untouched (no
--   behavior change for anything currently reading it).
--
--   1. properties.curated_photos
--      The final, room-labeled gallery kept after both triage phases:
--      [{url, room, description, source}, ...]. Threaded into the merge step
--      alongside scraped_markdown/ingested_markdown so host-uploaded photos
--      can fill gaps or override a scrape-side room label.
--
--   2. properties.rejected_photos
--      Everything filtered out at either phase, with why:
--      [{url, reason, phase}, ...]. Kept specifically so a future pass (once
--      vision analysis is cheaper) can reprocess these instead of re-scraping
--      from scratch.
--
-- REVERSIBILITY
--   Fully additive. Both columns default to an empty JSON array, so every
--   existing row reads as "not yet triaged" — matches reality for every
--   property added before this shipped. Safe to apply ahead of the code.
--   Triage itself fails soft (scraper/main.py) — a Gemini/download error
--   leaves these at their default, never blocks the scrape.


-- ── DDL ──────────────────────────────────────────────────────────────────────

alter table public.properties
  add column if not exists curated_photos jsonb default '[]'::jsonb,
  add column if not exists rejected_photos jsonb default '[]'::jsonb;


-- ── VERIFY — run this SEPARATELY, after the DDL above has been executed ───────
-- Read-only: no transaction, nothing to roll back. Expect one PASS row.
--
-- select 'columns' as check,
--        case when count(*) = 2 then 'PASS' else 'FAIL' end as result
--   from information_schema.columns
--  where table_schema = 'public'
--    and table_name = 'properties'
--    and column_name in ('curated_photos', 'rejected_photos');
