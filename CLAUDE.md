# the-ingestor — Local Law

**Active Workspace:** `projects/the-ingestor/` — all file operations scoped here unless explicitly stated otherwise.
**Inherits:** AG Global Constitution (GEMINI.md)
**Also inherits:** Root `CLAUDE.md` — read it at session start.
**Overrides:** None
**Stack:** Frontend: Flutter (Dart) web app, deployed to Vercel — staging
`alwaysalfred-staging.vercel.app`, prod `alwaysalfred.vercel.app`. Backend: FastAPI on Google
Cloud Run (`alfred-backend-staging` / prod `alfred-backend`, project `alfred-prod-502215`,
`europe-west3`), plus a separate Cloud Run scraper service (`alfred-scraper-staging`/prod) using
Firecrawl to scrape Airbnb listings. DB/Auth/Realtime/Storage: Supabase, split staging/prod (see
"Supabase Connection" below) — RLS on guest-facing tables via a backend-minted, booking-scoped
guest JWT. LLM: Gemini via Vertex AI/ADC on both environments (no API key, no rate cap) for
ingest/merge/chat/summarization. Guest channels: native web chat, Telegram, and WhatsApp (Meta
Cloud API) — all three share one message-processing path ("the Brain"). Job orchestration:
Google Cloud Tasks for the WhatsApp webhook queue; ingest/merge run directly via FastAPI SSE +
BackgroundTasks.
**Data Schema:** Core Supabase tables: `host_profiles` (`is_dev` flag gates advanced/dev UI),
`properties` (`master_json` — freeform host-knowledge blob, merged with ~12 canonical
"universal fields" via a second strict-schema Gemini call; `curated_photos`/`rejected_photos`
JSONB from Gemini Vision triage; `scraped_markdown`), `conversations` (`mode`:
`autopilot`|`intervene`), `messages`, `guests` (booking-scoped), `scrape_jobs`, `feedback`,
`file_fingerprints` (per-file ingest progress, persisted immediately per file so a retry doesn't
lose completed work). Schema evolves per-migration in `migrations/`, applied to staging first,
prod on the eventual `staging→main` merge.

**Architecture snapshot maintenance:** the two lines above are a snapshot, not a log — update
them **in place** (overwrite the stale part, don't append a new sentence next to it) only when a
session ships a real architectural or schema change (new service, stack swap, new core table).
Routine feature work never touches this block; if you're not sure whether a change qualifies, it
probably doesn't.

---

## Shell Execution Environment

**CRITICAL:** All terminal commands run in WSL2 (Ubuntu 24.04) — never Git
Bash, PowerShell, or cmd.
- All tools (node, npm, npx, python, pip) are installed in WSL2 only
- Windows paths (`C:\`, `D:\`) are never valid for command execution
- If a command fails with "not found" — wrong shell context, not missing tool

---

## Shared Resources

This project reads from AG shared resources. Never create local copies.

| Resource | Path |
|---|---|
| Skills | `~/AG_master_files/_skills/` |
| Global Lessons | `~/AG_master_files/_global_lessons/lessons.md` |
| Global Lessons Index | `~/AG_master_files/_global_lessons/lessons_index.md` |
| Protocols | `~/AG_master_files/_protocols/` |

**Before infra/security/secrets/deploy/regex/MCP-config work:** grep
`_global_lessons/lessons_index.md` (not the full `lessons.md`) for tags
matching the task. If a line looks relevant, open `lessons.md` at that date
heading before proceeding.

---

## Session Start
**Before any other action:** read `CONTEXT.md`'s `## Pending`/`## Unresolved Decisions` in full
(the small, current state), then `_Context/session-digest.md` if present. That's the full
current picture without touching the session log below it. Only read into `CONTEXT.md`'s
prepended `**Last Session:**`/`**Prior Session:**` blocks when you need depth on a specific past
decision — `## Pending` should already carry whatever's still open.

**Conditional:** if `graphify-out/GRAPH_REPORT.md` exists for this project, consult it before raw
files for architecture/structure questions (see root `CLAUDE.md` §10). Skip if it doesn't exist —
nothing else changes.

### Updating `_Context/session-digest.md`
This file holds the **last 5 sessions** as separate dated entries (newest first) — including parallel sessions — so a fresh session sees everything recent even when 2-3 sessions ran in parallel and closed out around the same time, not just whichever session updated it last.
- **Never fully replace the file.** Re-read it fresh immediately before editing, **prepend** a new dated entry for the current session, and if that makes more than 5 entries, delete only the oldest one.
- If a parallel session already added its own entry since you last looked, keep it — add yours alongside, don't overwrite.
- Full permanent history always lives in `CONTEXT.md`'s prepended session log.

---

## Session End / Wrap-up

**Whenever the user asks to wrap up, end the session, or otherwise signals they're done for now
— run this exact sequence, every time, without being asked individually for each step:**

1. **Write the `CONTEXT.md` entry.** This file's session log is prepend-only, not append-only:
   rename the current `**Last Session:**` block to `**Prior Session:**` and prepend a fresh
   `**Last Session:**` block above it (see the length-target rule below). There is no
   `## Accomplished` heading in this file — do not create one.
2. **Refresh `## Pending`/`## Unresolved Decisions`** at the top of `CONTEXT.md`. Hard rule:
   `## Pending` must be **≤15 lines** when you're done — if refreshing it would push it over,
   prune resolved items by **deleting the line outright**, never strikethrough-and-keep (the
   resolution is already permanent in the entry you just wrote in step 1, so nothing is lost).
   Point to `QUEUE.md`/`ROADMAP.md` for the standing feature/bug backlog instead of duplicating
   it here — this section is for session-continuity state that doesn't fit a backlog line (an
   in-flight investigation, a pending commit approval), and should often be short or empty.
3. `_Context/session-digest.md` — prepend a new dated entry per the Session Start rules above (cap at 5).
4. **Conditional — Graphify (code graph only):** if `graphify-out/` exists for this project,
   refresh the code graph (`graphify update .` — free/local, unconditional, no LLM). If
   `/graphify` doesn't show up as a recognized skill (Windows-side session — see
   `_global_lessons/lessons.md` 2026-09-10 entries), Read `SKILL.md` directly via its WSL/UNC
   path rather than skipping the step — but do **not** manually dispatch a Claude subagent to run
   the doc-semantic pass; that burns Claude Code session credits (confirmed: ~30% of a session in
   one run). Skip entirely if graphify isn't installed/run for this project yet.

   **The doc-semantic pass + Obsidian export is NOT part of wrap-up anymore** (moved out
   2026-09-11 — it's slow and free-tier-dependent, unfit to gate every session). It's now its own
   deterministic pipeline: `_scripts/graphify_semantic_pipeline.sh` (see
   `_protocols/GRAPHIFY_SEMANTIC_PIPELINE_PROTOCOL.md`), meant to run standalone or on a cron
   schedule, not during interactive wrap-up. Only run it here if the user explicitly asks for a
   doc/Obsidian refresh in this session.
5. **Run `_scripts/wrap_up.sh`.** It mechanically checks steps 1-3's structure only — never
   content quality: `## Pending`/`## Unresolved Decisions` headings exist, `## Pending` is
   ≤15 lines, `session-digest.md` has ≤5 entries, and this file's Stack/Data Schema lines aren't
   still placeholder text. Fix anything it reports FAIL on and rerun until clean before showing
   the user a commit to approve.

### `CONTEXT.md`'s entry-length target (keeps it from re-bloating without splitting the file)

`CONTEXT.md`'s session log is a single file, prepend-only, single source of truth for full
history — no separate archive, no lossy condensing, nothing ever rewritten after the fact (same
principle reflip established 2026-08-07, applied here to this project's actual prepend order
rather than reflip's append order — see global lesson of the same date). What keeps it from
re-growing unbounded is discipline at write time plus the `## Pending` line-count gate above, not
a later cleanup pass:

- **Target ~25-40 lines per session entry, hard ceiling ~50.** Capture decisions, why, real
  bugs found+fixed, and what shipped. Skip step-by-step verification narration (which command
  was run, what each log line said) — that already lives in git commit history and the code itself.
- If a session genuinely needs a deeper record (rare — a big multi-day build, a research
  session), write it to its own doc under `_Context/` and link it from the terse entry.
- `## Pending`/`## Unresolved Decisions` at the top are what a fresh session actually needs for
  continuity (see Session Start above) — the log below should rarely need reading past the last
  2-3 `**Last Session:**` entries except for historical curiosity or root-causing an old decision.

---

## Fix/Feature Completion Workflow

**After finishing a fix or feature (tests passing, typecheck clean, locally verified where
possible) — proactively ask something like "ready to redeploy and test?" instead of going quiet
and waiting for the user to notice it's done and separately prompt for a deploy.** This does not
relax the Git hard rules below — a push/deploy still needs the user's explicit go-ahead — it
just means Claude surfaces that question itself rather than making the user chase it. Applies
whether the fix was requested standalone or is one item off a running queue/backlog within the
same session.

---

## Git — HARD RULES

**NEVER run `git commit` or `git push` on your own.**

Always use the safe-commit-n-push workflow:
1. Show the user what will be committed (files + proposed message)
2. Wait for explicit "yes" / "confirm" / "go ahead" approval
3. Only then stage, commit, and push

This applies to ALL commits — documentation, fixes, features, everything. No exceptions, no matter how small the change.

This project is a standalone git repo (`projects/the-ingestor/.git`, remote
`origin` → `AG-2-0-projects-Hub/alfred-ingestor`) — it is not tracked by
AG_master_files' root repo.
1. **Pushing to `staging`** — plain `git push origin staging` (or
   `git -C projects/the-ingestor push origin staging` from the AG root) works
   directly, no PR needed.
2. **Shipping to `main`** — a plain push to `main` is **rejected** (GitHub
   branch protection requires a pull request, error `GH013`; confirmed twice,
   2026-09-03 and 2026-09-07). Open a PR from `staging`→`main` (GitHub UI
   "Compare & pull request", or `gh pr create` if `gh` is available — it
   wasn't in either session that hit this) and merge it there. **The founder
   merges these PRs manually on purpose, as their own final QA gate before
   anything reaches real users — do not try to script or bypass this step.**
3. Verify remote SHA matches local after pushing/merging.

---

## Supabase Connection
Two separate Supabase projects, one MCP each — never mix them up:

| Environment | MCP name | project_ref | Dashboard shows it as |
|---|---|---|---|
| Staging | `supabase-the-ingestor` | `gcxxilzfhwlsjcvtpsvj` | "Scraper + Ingestor" (shared DB with the scraper project, intentional) |
| Prod | `supabase-the-ingestor-prod` | `ylaooctefesedrecshic` | "alfred-prod" |

**Scoped to this project only** — never use the global `supabase` MCP when working here.
For the matching Vercel projects/domains and the Auth URL Configuration each Supabase
project needs, see `CONTEXT.md`'s "Vercel projects, domains & Supabase URL config" section
— this has silently broken once already (a stale Site URL + empty Redirect URLs on staging),
so don't assume it's still correct without checking if you're touching Auth-related code.

---

## QA Workflow

### On any fix or feature
After closing out any fix or feature with observable behaviour, append **one row** to the `## Pending intake` section of `_tests/scenarios.md`. Do not create a full scenario — just log the entry. Use the `Group with` column to flag entries that share a flow and should be merged into one compound scenario when promoted.

### Promotion rule — run before every `staging → main` merge
1. Review the pending intake table
2. Group rows by flow using the `Group with` column
3. For each group: create one proper scenario (or extend an existing one) in the relevant A–H section of `_tests/scenarios.md` — multi-step assertions are preferred over micro-scenarios
4. Delete the promoted intake rows
5. Run any new Layer 1 scenarios immediately; schedule Layer 2 scenarios for the next Playwright run

### What does NOT need a pending-intake entry
- Pure cosmetic changes (spacing, colour tweaks) with no assertable state
- Changes already covered by an existing passing scenario
- Changes to this file or other docs
