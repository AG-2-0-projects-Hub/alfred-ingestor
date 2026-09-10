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

## Architecture

- **TypeScript + Node 20+** — single orchestrator (`run.ts`) coordinates scenarios
- **Playwright (Chromium)** — drives the browser for Layer 2 scenarios
- **@google/genai (Gemini 2.5 Flash)** — vision judge for screenshot assertions
- **@supabase/supabase-js** — anon-role client for RLS isolation scenarios
- **flutter test** — invoked via subprocess for Layer 1 widget tests

## Configuration

Required env vars live in `../fixtures/.env.test` (gitignored). Copy from `.env.test.example` and fill in:
- `GEMINI_API_KEY_TEST` — separate Gemini key for QA, created at aistudio.google.com/apikey
- `SUPABASE_ANON_KEY` — public anon key from Supabase dashboard

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
