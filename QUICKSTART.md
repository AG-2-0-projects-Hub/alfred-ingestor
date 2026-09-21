# the-ingestor — Quickstart & Working Guide

**For:** coming back to this project after time away and needing to re-orient — what this is,
what tools exist, and how Claude and the founder actually work together day to day. The precise,
always-current technical law lives in `CLAUDE.md`; this file is the human-readable map on top of
it, and points there rather than duplicating anything that changes often.

---

## 1. What this is

**Alfred** (product name; repo is `the-ingestor`) is a SaaS that lets a vacation-rental host feed
in everything they know about a property (Airbnb URL, photos, PDFs, voice notes) and turns it
into an AI concierge — "Alfred" — that answers guest questions over web chat, Telegram, and
WhatsApp, day or night. The ingest→merge pipeline (host knowledge in) and the chat "Brain"
(guest questions out) are the two core systems; almost everything else supports one of those two.

**Current architecture snapshot:** see `CLAUDE.md`'s own `**Stack:**`/`**Data Schema:**` lines
near the top — that block is deliberately kept current (there's a maintenance rule requiring it),
so it's the source of truth, not this paragraph. In one sentence: Flutter web frontend (Vercel) +
FastAPI backend (Cloud Run) + Supabase (DB/Auth/Realtime/Storage) + Gemini (via Vertex AI, no API
key) for every AI step, split staging/prod end to end.

**Where the bigger picture lives:**
- `ROADMAP.md` — the long-term launch plan (tracks × milestones toward a real launch)
- `QUEUE.md` — the near-term backlog, what's actually being worked next
- `CONTEXT.md` — session-by-session history; its `## Pending` section is what a fresh session
  reads first

---

## 2. Tools available

| Tool | What it's for | Gotcha worth remembering |
|---|---|---|
| Supabase MCP — **`supabase-the-ingestor`** | Staging DB (shared with the scraper project) | Two separate MCPs exist — see below, never mix them up |
| Supabase MCP — **`supabase-the-ingestor-prod`** | Prod DB | Same |
| `gcloud` (via `wsl bash -lc`) | Cloud Run deploys, log/revision checks | No Cloud Build trigger on `staging` — a backend fix needs a **manual** `gcloud run deploy`; `main` auto-deploys prod on merge |
| Flutter | Frontend build/analyze | `flutter analyze` is mandatory before any frontend fix is called done. MCP tools can launch the app but can't do deep runtime introspection here (`connect_dart_tooling_daemon` isn't exposed) — verified, not assumed |
| `_tests/runner` (`npm run smoke` / `npm run full`) | Automated QA scenarios, OpenRouter-judged | See §4 — "full" only covers whatever has code today, not everything documented |
| `_scripts/or_code_review.py` | Cheap second-opinion code review (OpenRouter, cents) | Deliberately **not** Claude's own `/code-review` — that forks ~10 subagents and burns session credits; always say so before running anything that forks agents |
| `_scripts/wrap_up.sh` | Session-end structural check | Mechanical only — checks docs are internally consistent, never judges content quality |

**Two Supabase projects, easy to mix up:** `supabase-the-ingestor` = staging (`gcxxilzfhwlsjcvtpsvj`,
shows as "Scraper + Ingestor" in the dashboard). `supabase-the-ingestor-prod` = prod
(`ylaooctefesedrecshic`, "alfred-prod"). Always confirm which one before running anything.

**Shell tools:** this environment exposes a **PowerShell tool** (primary) and a **Bash tool**
(POSIX/Git Bash) — not a direct WSL2 terminal. Anything that needs a WSL2-installed tool (node,
python, flutter, gcloud, git for this repo) goes through `wsl bash -c "..."` from either shell
tool. `wsl bash -c` runs a **non-login shell with an empty `$PATH`** — use `wsl bash -lc` (login
shell) or an absolute path when a bare command name fails with "not found." (Two real examples
hit this session: `gcloud` and `flutter` both need `~-lc` or an absolute path — see
`lessons.md`/`lessons_index.md` for the exact current paths, since installs can move.)

---

## 3. How we work together (the standing pipeline)

Applies automatically, every fix/feature, without needing to be asked each time:

1. **Before touching a user-facing flow:** state a short failure-mode table (what breaks, how it
   shows up, what catches it) before writing any code.
2. **Propose, then implement.** For a bug found outside the current task's scope, or any
   meaningfully risky change, propose the fix and wait for a "yes"/"confirm"/"go ahead" — not
   silently fixed in passing.
3. **If you (the founder) propose an alternative to something already in progress** — it gets
   tested against real data, not just noted as "also possible." The simpler or better-performing
   one wins even if it means dropping work already invested in the other approach.
4. **Verify, don't assert.** A claimed root cause, config value, or "this works" gets checked
   against real data/logs/DB state before being stated as fact — "unconfirmed, my guess"
   otherwise.
5. **After the fix:** re-verify whatever scenario(s) in `_tests/scenarios.md` overlap the changed
   files (automated where that exists, manual otherwise — see §4), and log one line to
   `_tests/scenarios.md`'s pending-intake table.
6. **Never commit or push without an explicit go-ahead** — shown the exact diff/message first,
   every time, no matter how small.
7. **Before proposing anything that forks into multiple subagents** (e.g. `/code-review`'s ~10-way
   fork) — say the expected scale up front and get a yes, even if agreed to generically before.
8. **A live pass you confirm counts as a real PASS — no Playwright required** (`layer: 4` in
   `_tests/scenarios.md`, same as scenario A1). The intent is Claude logs this the moment you
   confirm a flow works, same turn, without being asked — but this can't be mechanically enforced
   (`wrap_up.sh` only sees git diffs, not chat, so it can't catch a skipped manual log the way it
   catches a skipped code-change scenario). If Claude doesn't do it on its own, just say **"log
   that"** right after confirming something works — that's the one phrase to remember.

---

## 4. QA / testing — what actually runs, and when

- **After every fix (automatic, scoped):** only re-checks scenarios related to what just changed
  — not the whole app. This is step 5 above, and it's cheap (minutes).
- **`npm run full` (explicit ask only, no cron yet):** runs every scenario that currently has
  real code under `_tests/runner/scenarios/` — a small, arbitrary subset (whatever's been
  automated so far, not picked for importance).
- **Critical Path (the real `staging → main` merge gate):** a small, deliberately hand-picked
  list of the scenarios that matter most by actual blast radius — see `_tests/scenarios.md`'s own
  "## Critical Path" section for the list and why each is there. Not fully automated yet; the gap
  is filled manually until it is. Before any merge to `main`, this gets run (and offered
  proactively — you shouldn't need to remember to ask for it by name).
- **The other 40+ documented scenarios:** nothing checks these automatically. They only get
  looked at when a fix happens to touch that area, or someone deliberately walks through them —
  "documented" and "actually tested" are not the same thing in this project today.

---

## 5. Session start / end

**Start:** Claude reads this project's `CLAUDE.md` and `CONTEXT.md`'s `## Pending` section before
doing anything else — that's the full current picture without needing to re-read the whole
history.

**End (whenever you say you're done for now):** Claude runs a fixed wrap-up sequence —
updates `CONTEXT.md`, refreshes `## Pending`, logs any real lessons learned, and runs
`_scripts/wrap_up.sh` until it's clean. You don't need to ask for this by name either — just say
you're wrapping up.

---

## 6. Where to look for things

| Question | Look here |
|---|---|
| "What's being worked on soon?" | `QUEUE.md` |
| "What's the long-term plan?" | `ROADMAP.md` |
| "What happened in past sessions?" | `CONTEXT.md` (top = current state, below = full history) |
| "Has this exact problem happened before?" | `lessons_index.md` (grep first), then `lessons.md` |
| "What's the QA spec for flow X?" | `_tests/scenarios.md` |
| "What are the exact behavioral rules?" | `CLAUDE.md` (this file's technical source of truth) |
