# Health Check Protocol

**Created:** 2026-09-10, after a real incident: the founder could not train a single property on
staging because `gemini_client.py` had been silently running a deprecated Gemini model since
2026-09-09 — `/health` returned 200 the entire time. This protocol exists because uptime
monitoring alone already proved insufficient once; the checks below specifically target the
failure modes that `/health` cannot see.

**Status:** manual, on-demand (`python _tests/health/run_health_check.py`). Designed to become a
scheduled cron job once dedicated live agents exist — see "Future: cron" at the bottom.

---

## 1. Design principle

`/health` tells you the process is running. It does not tell you Gemini calls actually succeed,
that a deploy actually picked up your last fix, that RLS still blocks cross-tenant reads, or that
the frontend is talking to the right backend. Every check below targets a **specific, real
incident** this project already hit — nothing here is hypothetical.

Checks are grouped into layers by cost and speed, cheapest first, so a full run fails fast on the
free checks before spending money on live API calls.

## 2. The full check matrix

| # | Failure mode | Category | Severity | Script check | Mitigation on failure |
|---|---|---|---|---|---|
| 1 | Deprecated/retired Gemini model | AI layer | 🔴 Critical | `check_model_consistency` | Update the stale constant to the current validated model, redeploy |
| 2 | Gemini outage/degradation | AI layer | 🔴 Critical | `check_gemini_ingest_text`, `check_gemini_merge`, `check_gemini_chat`, `check_gemini_summarizer` | Nothing we control directly — retries already in place; escalate if it fails across repeated runs |
| 3 | Gemini quota/prepay credits exhausted | AI layer | 🔴 Critical | same 4 smoke checks (a 429/quota error surfaces here, not a silent hang) | Pay overdue balance / raise quota — hit this exact failure once already ("Lightning dunning decision is deny") |
| 4 | Cloud Run stuck on a bad rollout (not 100% traffic) | Backend infra | 🟠 High | `check_cloud_run_traffic` | Route 100% to latest healthy revision, or rollback |
| 5 | Cloud Run `min-instances` reverted | Backend infra | 🟠 High | `check_cloud_run_min_instances` | `gcloud run services update --min-instances=N` |
| 6 | Required env var/secret missing after redeploy | Backend infra | 🔴 Critical | `check_backend_health` (indirect — most missing secrets crash startup or 500 on first use) | Re-set from Secret Manager, redeploy |
| 7 | RLS policy regression (real past incident — cross-tenant data leak) | Database | 🔴 Critical | `check_rls_anon_blocked` | Re-apply the correct policy, treat as a security incident |
| 8 | Migration applied to staging but not prod | Database | 🟠 High | *not scripted — run via Supabase MCP `list_migrations` on both projects and diff* | Apply the missing migration to whichever env lacks it |
| 9 | Supabase project paused | Database | 🔴 Critical | `check_backend_health` (any DB-touching endpoint fails loudly if the project is paused) | Resume via dashboard or MCP |
| 10 | Frontend pointing at wrong backend URL | Frontend | 🔴 Critical | `check_frontend_reachable` | Correct the base-URL env var on Vercel, redeploy without cache |
| 11 | Vercel serves a stale prior build | Frontend | 🟠 High | *not scripted — needs `VERCEL_API_TOKEN` to compare deployment timestamps, not wired yet* | Trigger a fresh deploy |
| 12 | Vercel "Redeploy" reuses the build cache — a fix never reaches the bundle (real incident, 2026-07-13) | Frontend | 🟠 High | `check_deployed_supabase_key` catches this specifically for the key-rotation case | Redeploy with "Use existing Build Cache" unticked — standing habit after any env change |
| 13 | Supabase Auth Site URL/Redirect URLs stale (already happened once) | Auth | 🟠 High | *not scripted — check via Supabase dashboard/Management API* | Update Site URL/Redirect URLs to match the live domain |
| 14 | WhatsApp webhook/token silently expired | Integration | 🔴 Critical (WA users) | *not wired — needs a WhatsApp test token in `.env.test`* | Re-verify in Meta dashboard, regenerate token, re-subscribe app to WABA |
| 15 | Telegram webhook URL stale | Integration | 🟠 High | `check_telegram_webhook` (staging only) | Re-run `setWebhook` with the current backend URL |
| 16 | Firecrawl key/quota exhausted | Integration | 🟠 High | *not wired — needs `FIRECRAWL_API_KEY_TEST`* | Check Firecrawl dashboard, rotate key |
| 17 | Docs/comments describing fixed bugs or old UI as current | Documentation | 🟡 Medium | **not part of this script — needs judgment, run as a periodic agent sweep instead** (see §4) | Patch the flagged files |
| 18 | Orphaned test data accumulating in staging | Data hygiene | 🟢 Low | `check_orphaned_test_data` | Soft-delete anything past a reasonable age (reports only in v1 — no auto-delete) |
| 19 | Vercel serves the wrong Supabase key to the public bundle (real incident — prod briefly shipped `service_role`) | Frontend/Security | 🔴 Critical | `check_deployed_supabase_key` | Correct the env var, redeploy without cache, **rotate the key if it was ever live** |
| 20 | Two Vercel × two Supabase projects cross-wired | Frontend/Config | 🔴 Critical | `check_deployed_supabase_key` (asserts the decoded project ref matches the expected one for that environment) | Correct the swapped env var |

**Coverage: 15 of 20 checks are live/scripted** (rows 1-7, 9-12, 15, 18-20). Rows 8 and 13 need no
script — run directly via the Supabase MCP when checking. Row 17 is deliberately not a script (see
§4). **Genuinely open:**
- Row 14 (WhatsApp) — staging still runs its own separate test WABA (`+15556127233`, confirmed
  live 2026-09-10), not prod's number. Reusing prod's number for staging health checks was
  proposed and is an open decision, not yet made — see `CONTEXT.md`'s 2026-09-10 entry. A
  dedicated staging test token was pulled from Secret Manager either way, ready to wire once the
  decision is made.
- Row 16 (Firecrawl) — usable today interactively via the connected Firecrawl MCP (no key needed
  for that). Only needs a standalone API key if/when this script runs unattended outside Claude
  Code (the cron future in §6) — not needed for on-demand runs like this session's.

## 3. Running it

```bash
cd _tests/health
../../backend/venv/bin/python run_health_check.py            # staging (default)
../../backend/venv/bin/python run_health_check.py --env prod # prod — read-only checks only
```

Reads config from `_tests/fixtures/.env.test` (same file the Playwright runner uses — one source
of test credentials, not two). Exits non-zero if any check fails, so it's cron/CI-ready as-is.
**The 4 Gemini smoke checks make real, billed API calls** (tiny payloads, a few cents per full
run) — this is intentional; a check that doesn't actually call Gemini can't catch a deprecated
model.

## 4. Documentation staleness — separate track, not this script

Row 17 is structurally different from everything else here: there's no mechanical pass/fail for
"does this doc accurately describe the current code" — it needs a read-and-judge pass, which is
what the 2026-09-10 session did manually (see that session's `CONTEXT.md` entry for the sweep
method: a fixed list of "facts about current state," checked against `ROADMAP.md`, `QUEUE.md`,
`bug-backlog.md`, `scenarios.md`, and code comments). Run that sweep periodically as its own pass
— monthly, or whenever a batch of "this behavior changed" fixes lands — not on the same cadence as
the mechanical checks above.

## 5. Bug ledger

Every bug this protocol (or a session) finds and fixes gets logged to `_tests/bug-backlog.md` —
root cause, fix, commit — so a recurrence has a known answer instead of a re-investigation from
scratch. Keep entries short (4-6 lines): what broke, why, what fixed it, where. That file is the
project's institutional memory for "we've hit this before."

## 6. Future: cron

Once dedicated live agents exist (per the founder's own framing — not yet), this becomes a
scheduled job: run layers 0-1 frequently (cheap, no API cost), layer 2 (Gemini smoke) a few times
a day, and the doc-staleness sweep (§4) weekly/monthly via an agent, not this script. Failures
should page/notify rather than sit in a log nobody reads — exact channel (Slack? email?) is an open
decision for whenever that's built, not decided here.
