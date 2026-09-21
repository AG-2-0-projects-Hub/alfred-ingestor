# Health Check Run Log

History of notable `run_health_check.py` runs — not every green run, only ones where something
failed, got fixed, was mitigated, or a check itself changed. This is different from
`_tests/bug-backlog.md` (bugs found through any debugging) and from `HEALTH_CHECK_PROTOCOL.md`
(the stable design doc, the 20-row matrix, rationale — reread every time you touch the checks,
never grows). This file is the run-by-run history; the protocol doc should never need to grow to
hold it.

**Reading this:** scan the index below first. Only open the matching dated entry if it looks
relevant — don't read the whole file top to bottom for a routine task.

**Adding an entry:** dated, newest first, 4-8 lines — what happened, root cause if any, what
changed. No step-by-step narration; that's what git history is for.

---

## Index

| Date | Hook | Checks affected |
|---|---|---|
| 2026-09-10 | Gemini smoke checks moved off AI Studio (free tier + prod's depleted prepay key) onto Vertex/ADC | gemini_ingest_text, gemini_merge, gemini_chat, gemini_summarizer |
| 2026-09-10 | Initial 16 scripted rows built and verified live against staging | model_consistency, backend_health, scraper_health, cloud_run_traffic, cloud_run_min_instances, rls_anon_blocked, deployed_supabase_key, frontend_reachable, vercel_build, telegram_webhook, whatsapp_token, check_firecrawl |

---

## Entries

### 2026-09-10 — Gemini checks moved to Vertex/ADC
17/17 scripted rows pass (1 legit skip, `orphaned_test_data`). `check_firecrawl` (added earlier
this session) reconfirmed inside a full combined run for the first time.

**Fixed:** the 4 Gemini smoke checks used `GEMINI_API_TEST_KEY` (AI Studio Developer API, free
tier — 5rpm/20rpd), which repeated runs exhausted, causing flaky pass/503/429 with no way to tell
whether Gemini itself was ever actually degraded. Confirmed live via `gcloud run services
describe` that staging has no Gemini API key at all — it's been on Vertex/ADC since Batch 6
(2026-07-16), same transport as prod. Tried prod's own fallback `GEMINI_API_KEY` secret next — also
dead (AI Studio prepay balance depleted, separate billing from GCP credits). Switched all 4 checks
to Vertex/ADC (`GOOGLE_GENAI_USE_VERTEXAI=true` + local ADC), matching what staging and prod
actually run. No rate cap on this transport. Earlier "Gemini outage" reads from prior sessions
should now be treated as debunked — almost certainly free-tier throttling, not a real outage.

### 2026-09-10 — Initial 16 scripted rows built and verified live
First working version of `run_health_check.py`, built from the 20-row design in
`HEALTH_CHECK_PROTOCOL.md`. Verified live against staging in a single combined run: static model
consistency, backend/scraper `/health`, Cloud Run traffic split + min-instances, RLS anon-read
block, and — the most valuable one — `deployed_supabase_key`, which fetches the live frontend's
`/assets/.env` directly (far more reliable than the first attempt, which regex-scanned the
minified `main.dart.js` bundle and never actually found the key).

**Credentials found and wired, not assumed:** Telegram + WhatsApp staging test tokens pulled
straight from Secret Manager and verified against their real APIs; a Vercel PAT was initially
declared missing (an overly strict regex on `_mcp_profiles/global.json` failed to match its
`VAR=token` shape) and later found and verified on a second pass. `check_firecrawl` was added and
passed in isolation but not yet re-verified inside a full combined run — done in the follow-up
entry above. The 4 Gemini checks used a free-tier AI Studio key at this point (see the entry above
for why that got replaced).
