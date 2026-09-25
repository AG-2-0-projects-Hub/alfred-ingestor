# the-ingestor — Local Law

**Active Workspace:** `projects/the-ingestor/` — all file operations scoped here unless explicitly stated otherwise.
**Inherits:** Root `CLAUDE.md` (the AG Global Constitution for Claude Code) — read it at session
start. Does **not** separately inherit `GEMINI.md`; Claude Code never reads that file (root
`CLAUDE.md` §1) — an older version of this line claimed otherwise, corrected 2026-09-16.
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
Google Cloud Tasks — one queue for the WhatsApp webhook, a separate one for ingest/merge (per-file
Cloud Tasks workers, `backend/routers/ingest_worker.py`; DB-backed run state via `ingest_run_id`/
`ingest_files`/`ingest_heartbeat_at` on `properties`, a self-rescheduling watchdog, host-triggered
`/resume`). SSE + BackgroundTasks for ingest were fully retired 2026-09-16 (Phase 2 of the Train
Now reliability work) — `/api/ingest` is now a sub-second JSON dispatcher, not a stream.
**Data Schema:** Core Supabase tables: `host_profiles` (`is_dev` flag gates advanced/dev UI),
`properties` (`master_json` — freeform host-knowledge blob, merged with ~12 canonical
"universal fields" via a second strict-schema Gemini call; `curated_photos`/`rejected_photos`
JSONB from Gemini Vision triage; `scraped_markdown`; `ingest_run_id`/`ingest_files`/
`ingest_heartbeat_at`/`ingest_stage` — live per-run background-worker state, added 2026-09-16),
`conversations` (`mode`: `autopilot`|`intervene`), `messages`, `guests` (booking-scoped),
`scrape_jobs`, `feedback`, `file_fingerprints` (cross-run per-file dedupe key, distinct from
`ingest_files` above — a retry doesn't lose completed work or re-process an unchanged file).
Schema evolves per-migration in `migrations/`, applied to staging first, prod on the eventual
`staging→main` merge.

**Architecture snapshot maintenance:** the two lines above are a snapshot, not a log — update
them **in place** (overwrite the stale part, don't append a new sentence next to it) only when a
session ships a real architectural or schema change (new service, stack swap, new core table).
Routine feature work never touches this block; if you're not sure whether a change qualifies, it
probably doesn't.

---

## Shell Execution Environment

**Corrected 2026-09-16 — the previous version of this section was wrong** (said WSL2 terminals
were used directly and PowerShell/Git Bash were forbidden; root `CLAUDE.md` established the
actual environment back on 2026-07-28 and this file was never updated to match, despite every
session since actually running commands the way described below).

This environment exposes a **PowerShell tool** (primary) and a **Bash tool** (Git Bash/POSIX) —
there is no direct WSL2 terminal. All project tools (node, npm, python, flutter, gcloud, git for
this repo) live inside WSL2 and are invisible to both shell tools unless routed through
`wsl bash -c "..."` (from either shell tool).
- `wsl bash -c` runs a **non-login shell with an empty `$PATH`** — a bare command name (e.g.
  `flutter`, `gcloud`) will fail "not found" even though it's installed. Fix: `wsl bash -lc`
  (login shell) or the tool's absolute path. Confirmed necessary for both `gcloud` and `flutter`
  this session — check `lessons_index.md` for their current exact paths, since reinstalls can
  move them (already happened once to `flutter`'s symlink, 2026-09-16).
- Windows paths (`C:\`, `D:\`) are never valid inside a `wsl bash -c` command.
- If a command fails with "not found" after prefixing with `wsl bash -c` — try `-lc` or an
  absolute path before assuming the tool isn't installed.

---

## Shared Resources

This project reads from AG shared resources. Never create local copies.

| Resource | Path |
|---|---|
| Skills | `~/AG_master_files/_skills/` |
| Global Lessons | `~/AG_master_files/_global_lessons/lessons.md` |
| Global Lessons Index | `~/AG_master_files/_global_lessons/lessons_index.md` |
| Protocols | `~/AG_master_files/_protocols/` |

**Before infra/security/secrets/deploy/regex/MCP-config/git work:** grep BOTH
`lessons_index.md` (this project's own, project root) AND
`_global_lessons/lessons_index.md` (not either full `lessons.md`) for tags
matching the task. If a line looks relevant, open the matching `lessons.md` at
that date heading before proceeding. Do this check itself — don't rely on
remembering to do it; the same lesson recurring because this step was skipped
is exactly what the 2026-09-16 entry in this project's own index is about.

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
4. **Lessons check, before any commit.** Ask explicitly: did this session hit a real discovery,
   failure, constraint, or piece of feedback that would help a future session (not routine work)?
   If yes, log it to `lessons.md` now (format in root `CLAUDE.md` §13) — don't defer it, and don't
   skip it because step 1 already summarized it narratively; `lessons.md` is the searchable,
   indexed record, `CONTEXT.md` is not. Then add the matching one-line row to `lessons_index.md`
   in the same pass — `_scripts/wrap_up.sh` mechanically checks the two stay in sync (see below),
   so an entry without an index row is a FAIL, not just an oversight to catch later.
5. **Conditional — Graphify (code graph only):** if `graphify-out/` exists for this project,
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
6. **Run `_scripts/wrap_up.sh`.** It mechanically checks steps 1-4's structure only — never
   content quality: `## Pending`/`## Unresolved Decisions` headings exist, `## Pending` is
   ≤15 lines, `session-digest.md` has ≤5 entries, this file's Stack/Data Schema lines aren't
   still placeholder text, whether this session's commits touched `backend/**`/`frontend/lib/**`
   without a matching diff in `_tests/scenarios.md`, **and (added 2026-09-16)
   whether `lessons_index.md`'s row count matches `lessons.md`'s entry count.**
   - On every other FAIL: fix the underlying doc and rerun.
   - **On the QA-gate FAIL: go back and actually run the missing same-session targeted replay**
     (see `## QA Workflow` above) **and log the pending-intake row now** — do not just silence the
     check by adding an unrelated `scenarios.md` line. Only rerun once the QA step for real work
     has actually happened.
   - **On the lessons-sync FAIL: add the missing row(s) to `lessons_index.md` now** — this check
     can't tell you *whether* a lesson was worth logging (that's step 4's judgment call), only that
     whatever you *did* log in `lessons.md` also has a matching index row, so the index never
     silently drifts out of date the way this project's own 2026-09-16 lesson describes happening
     to the QA-logging discipline.
   Rerun until clean before showing the user a commit to approve.

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

**Why this section has two checkpoints, not one:** the recurring Train Now reliability failures
(2026-09-14→16) traced back to fixes being reactive — shipped, then the founder hit the *next*
failure mode live, repeat — because nothing enumerated failure modes up front, and the existing
pending-intake rule below was still skipped once under session pressure despite already being
documented. Full history: `_Context/Train_Now_Reliability_and_QA_Process_Plan_2026-09-15.md`.

### Before any fix or feature: failure-mode check
For anything touching a user-facing flow (skip for pure docs/config/copy changes — same exemption
list as below): before writing code, state a short table inline in the session — *failure mode →
user-facing effect → mitigation* — covering at minimum: all succeed / partial fail / total fail /
connection drops mid-request / request never reaches backend / backend hangs past any timeout.
Same requirement pattern as root `CLAUDE.md`'s "Mechanical Logic First" (§3) — stated before
implementation, not after.

### On any fix or feature
After closing out any fix or feature with observable behaviour, append **one row** to the `## Pending intake` section of `_tests/scenarios.md`. Do not create a full scenario — just log the entry. Use the `Group with` column to flag entries that share a flow and should be merged into one compound scenario when promoted.

### Same-session targeted replay
Before calling the fix done: grep `_tests/scenarios.md` for scenarios whose `touches:` list
overlaps the files just changed, and replay those (not the full suite) to confirm nothing
adjacent broke. Cheap — minutes, not a full session extension — and this is what
`_scripts/wrap_up.sh`'s QA-gate check (see Session End below) verifies actually happened.

### Optional: OpenRouter code review for critical changes
For a change that's genuinely high-risk (auth/security touches, or anything going into a
`staging → main` merge) — not routine work — you can run `_scripts/or_code_review.py` (diffs
`origin/staging...HEAD` plus uncommitted changes through `qwen/qwen3.7-flash` on OpenRouter).
This is deliberately **never** Claude's own `/code-review` — that forks into ~10 parallel
subagents on Claude itself, which burns Claude Code session credits fast and should never run
without first telling the founder the expected scale and getting a go-ahead (2026-09-16
incident: it ran unannounced and reasonably alarmed the founder mid-session). The OpenRouter
version costs cents in API credits instead, so it's fine to reach for more freely — still ask
first for anything beyond a single small diff, since cost is now non-zero either way.

### Full-suite QA
`cd _tests/runner && npm run full` runs every scenario that currently has code — explicit-ask
only, no cron yet. The real `staging → main` merge gate is the smaller Critical Path set in
`_tests/scenarios.md` (picked by blast radius, not by what's already automated) — see the
Promotion rule below.

### FIX-VERIFY Protocol (opt-in, mechanically enforced)
When the founder says "fix X with FIX_VERIFY_PROTOCOL.md" (or names the protocol), follow
`FIX_VERIFY_PROTOCOL.md` at the project root exactly — real FMEA, explicit approval, implement,
then verify for real (create a Playwright scenario for any frontend change, not just reuse one
if it exists; a real check for backend-only changes), with a mandatory `Protocol: FIX_VERIFY` +
`Verified:` trailer in the commit message. `_scripts/wrap_up.sh` fails the session if that
trailer is present without a real `Verified:` line or, for a frontend change, a matching new/
changed file under `_tests/runner/scenarios/`. Optional, not the silent default for every fix —
read the file itself for the full sequence and why it exists.

### Promotion rule — run before every `staging → main` merge
0. Before starting: proactively ask whether to run the Critical Path check first — don't wait to
   be asked for it by name.
1. Review the pending intake table
2. Group rows by flow using the `Group with` column
3. For each group: create one proper scenario (or extend an existing one) in the relevant A–H section of `_tests/scenarios.md` — multi-step assertions are preferred over micro-scenarios
4. Delete the promoted intake rows
5. Run every Critical Path scenario (`_tests/scenarios.md`'s "## Critical Path" section) —
   automated ones via `npm run full`, unautomated ones manually until they're built. Run any
   other new Layer 1 scenarios immediately too; schedule non-critical Layer 2 scenarios for the
   next Playwright run as before.

### What does NOT need a pending-intake entry
- Pure cosmetic changes (spacing, colour tweaks) with no assertable state
- Changes already covered by an existing passing scenario
- Changes to this file or other docs

---

## Feedback Triage

Follow `FEEDBACK_TRIAGE_PROTOCOL_INGESTOR.md` (project root) — it declares this project's
feedback sources and points to the base `_protocols/FEEDBACK_TRIAGE_PROTOCOL.md` for the full
sequence. Invoked on-demand only ("run the feedback triage protocol"); no cron yet.
