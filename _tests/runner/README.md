# Alfred QA Runner

Executes scenarios defined in `_tests/scenarios.md` against the staging stack.

## Quick start

```bash
cd _tests/runner
npm install
npx playwright install chromium
npm run smoke   # runs the 3-scenario smoke test
```

Reports land in `_tests/reports/`.

## Full-suite vs. Critical Path

- `npm run full` — every scenario that currently has code here (grows over time). Nothing runs
  it automatically; use it whenever you want a broad but not comprehensive check.
- **Critical Path** — the real gate before merging `staging → main`. A small, hand-picked list
  of what matters most (login, the core Train Now flow, guest chat, security) — see
  `_tests/scenarios.md`'s "## Critical Path" section for the list and why each one's there. Not
  all of them have code here yet.

## Architecture

- **TypeScript + Node 20+** — single orchestrator (`run.ts`) coordinates scenarios
- **Playwright (Chromium)** — drives the browser for Layer 2 scenarios
- **OpenRouter (`qwen/qwen3-vl-8b-instruct`)** — vision judge for screenshot assertions
  (`lib/screenshot-judge.ts`)
- **@supabase/supabase-js** — anon-role client for RLS isolation scenarios
- **flutter test** — invoked via subprocess for Layer 1 widget tests

### Vision judge model
Was `gemini-3.8-flash` direct via `@google/genai`/AI Studio until 2026-09-16. Swapped after a
4-way empirical comparison against known PASS/FAIL screenshots (the model that decides every
Layer 2 visual assertion needs to actually be trustworthy):

| Model | Result |
|---|---|
| `gemini-3.8-flash` (old default) | 0/2 — network-level failure both calls (inconclusive on its own, but already the known-unreliable model from this project's main Gemini reliability work) |
| `gemini-3.6-flash` | 1/2 — one call hit a live `503 high demand`, the same failure class already logged against scenario A3 |
| `openrouter: google/gemma-4-31b-it:free` | 0/2 — hard `429` rate-limit both calls (shared free-tier pool saturated, matches a prior graphify finding) |
| **`openrouter: qwen/qwen3-vl-8b-instruct`** | **2/2, zero errors, ~1.8s avg, ~$0.0002/call** |

`@google/genai` is still used elsewhere if any Layer 1 scenario needs it directly — this swap is
scoped to the vision judge only. Re-run the comparison before changing the judge model again;
don't swap on a guess (see the guidance comment at the top of `screenshot-judge.ts`).

## Configuration

Required env vars live in `../fixtures/.env.test` (gitignored). Copy from `.env.test.example` and fill in:
- `GEMINI_API_TEST_KEY` — separate Gemini key for QA, created at aistudio.google.com/apikey (used
  by any Layer 1 scenario that calls Gemini directly; no longer used by the vision judge)
- `SUPABASE_ANON_KEY` — public anon key from Supabase dashboard

The vision judge additionally needs `OPENROUTER_API_KEY` — **not** read from `.env.test`; loaded
directly from the shared root-level `~/AG_master_files/_scripts/.env` (the same key graphify's
semantic pipeline uses), a deliberate choice over a separate test-scoped key (2026-09-16). If
that file or key is missing, `env.ts` fails loudly at startup.

## Modes

- `npm run smoke` — runs C6 + A2 + G2 (the workflow smoke test)
- `npm run full` — currently same as smoke; will expand to entire matrix once stable

## Adding a new scenario

1. Add a scenario row to `_tests/scenarios.md` first
2. Create `scenarios/<id>.ts` that exports an async function returning `ScenarioResult`
3. Wire it into `pickScenarios()` in `run.ts`

## Known limits

- Layer 2 selector strategy assumes Flutter web HTML renderer; if CanvasKit is used, scenarios that interact with form fields will need vision-driven clicking (Gemini returns coords, Playwright clicks pixels)
- Warmup wait was originally sized for Render free-tier cold start; services now run on Cloud Run (`min-instances=1` on prod, `min=0` on staging), so a staging cold start is Cloud Run's own (much shorter) container-start latency, not Render's
- Reports are HTML in `../reports/` — gitignored, local only
