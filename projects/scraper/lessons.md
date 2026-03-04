# Project Lessons Log
_Discoveries logged here during sessions. Global candidates flagged for promotion._

## 2026-03-01 — Skill installed: fastapi-router-py
**Source:** https://github.com/microsoft/skills
**Domain:** FastAPI
**Score:** 10/12
**Reason:** Provides FastAPI routers with CRUD and auth.

## 2026-03-01 — Skill installed: supabase-postgres-best-practices
**Source:** https://github.com/supabase/agent-skills
**Domain:** Supabase
**Score:** 10/12
**Reason:** Official PostgreSQL best practices from the Supabase team.

## 2026-03-01 — Skill installed: n8n-workflow-patterns
**Source:** https://github.com/czlonkowski/n8n-skills
**Domain:** n8n Automation / Make.com webhook equivalent
**Score:** 9/12
**Reason:** Workflow patterns for webhook and HTTP tasks relevant to Make.com logic.

---

## 2026-03-03 — Monorepo Migration: Scraper → Alfred Main Project
**Context:** Scraper micro-project completed local E2E test successfully. Ready to integrate into the larger Alfred monorepo.
**Discovery:** The scraper's functional core is only 4 files — everything else is planning/debug artifacts. Keeping it as a standalone microservice (Option B) is cleaner than merging code.
**Impact:** Adopted monorepo pattern: one root repo (`alfred/`), independent service subfolders under `services/`, each self-contained and independently deployable.
**Global Candidate:** Yes — monorepo + microservice pattern applies to all future Alfred services.

### Functional Core (files to migrate)
```
main.py
requirements.txt
GEMINI_PROMPT_AIRBNB.md
.env.template
```

### Migration Commands
```bash
# Run from inside the alfred/ root repo
mkdir -p services/scraper
cp ~/AG_master_files/projects/scraper/main.py services/scraper/
cp ~/AG_master_files/projects/scraper/requirements.txt services/scraper/
cp ~/AG_master_files/projects/scraper/GEMINI_PROMPT_AIRBNB.md services/scraper/
cp ~/AG_master_files/projects/scraper/.env.template services/scraper/
```

### Target Monorepo Structure
```
alfred/
├── services/
│   ├── scraper/          ← this project (4 files)
│   ├── pricing-engine/   ← future
│   └── availability-sync/← future
├── frontend/             ← Flutter UI
├── docs/
│   └── architecture.md   ← service map
└── README.md
```

### Render.com Deployment Update
After migrating, update the Render service **Root Directory** setting from `.` to `services/scraper` and redeploy. No other config changes needed.

---

## 2026-03-03 — GitHub MCP Not Active in Claude Code Session Despite Correct Profile
**Context:** Attempting to deploy scraper to Vercel via Claude Code using the GitHub MCP. The `scraper.json` profile correctly lists `github` as a required MCP server.
**Discovery:** `ag-switch.sh` is NOT fully automatic. It updates `mcp_config.json` correctly, but MCP servers are connected at **session startup only**. The user must hit **"Refresh" in the MCP panel** after `ag-switch.sh` runs for the changes to take effect in the active session. If Claude Code was already open before the switch (or if the switch ran but Refresh was skipped), the GitHub MCP is not available — even though the profile is correct. The AI model cannot inject MCPs into an already-running session.
**Impact:** Claude Code fell back to manual workarounds (creating the repo by hand) instead of using the `mcp__github__*` tools. This breaks the automation intent of the MCP profile system.
**Fix:** Always hit "Refresh" in the MCP panel after `ag-switch.sh` runs. If starting a session where GitHub is needed, run `ag-switch.sh` first in WSL, hit Refresh, then begin the Claude Code session.
**Global Candidate:** Yes — this applies to every project that uses any MCP tool. The "run ag-switch → hit Refresh → then open Claude Code" order is a universal session-start requirement that should be documented in GEMINI.md or `_global_lessons/lessons.md`.

---

## 2026-03-03 — MCP Tool Overrides Are Global-Only: No Per-Project Granularity
**Context:** Attempted to enable `create_repository` for the GitHub MCP in the scraper project without affecting other projects. Discovered this is not currently possible.
**Discovery:** The `disabledTools` list lives exclusively in `global.json` and `mcp_config.json` at the server level. The project profile (`scraper.json`) only declares *which MCP servers* to include — it has no mechanism to override which *tools within those servers* are enabled. Enabling a tool means enabling it globally for all projects that use that server.
**Impact:** Workaround was to edit `mcp_config.json` directly (session-only, gets rebuilt on next `ag-switch` run). This is fragile and doesn't scale.
**Long-Term Fix:** Extend the project profile schema to support a `toolOverrides` key per MCP server. `ag-switch.sh` should merge global `disabledTools` with project-level additions/removals when building `mcp_config.json`. Example target schema:
```json
{
  "mcpServers": ["github", "context7"],
  "toolOverrides": {
    "github": {
      "enable": ["create_repository"],
      "disable": []
    }
  }
}
```
**Global Candidate:** Yes — this is a fundamental architectural gap in the MCP profile system. Fix belongs in `ag-switch.sh` + `new-project.sh` + the profile schema spec in `_global_lessons/`.

---

## 2026-03-03 — Flutter Web Blank Page on Vercel: Service Worker Fix
**Context:** Flutter web app deployed to Vercel rendered a blank white page on first load.
**Root Cause:** Flutter's legacy service worker strategy (`flutter_service_worker.js`) blocks `main.dart.js` from loading until the SW activates. On a first visit (no cached SW), the activation stalls — especially in Brave which has stricter SW handling.
**Fix:** Rebuild with `--pwa-strategy=none`: `flutter build web --release --pwa-strategy=none`. This generates an `index.html` that loads `main.dart.js` directly with no SW dependency.
**Signal:** Build warns "Flutter's service worker is deprecated" — this is the tell.
**Global Candidate:** Yes — applies to any Flutter web deployment on static hosts (Vercel, Netlify, GitHub Pages).

---

## 2026-03-03 — CONSTRAINT VIOLATION: global.json Must Never Be Edited Directly
**Context:** New GitHub PAT needed to be updated across both `mcp_config.json` and `global.json`. Gemini edited both files directly instead of following the established protocol.
**Discovery / Violation:** `global.json` is a **read-only auto-sync target**. It is rebuilt entirely by `ag-switch.sh` from `mcp_config.json` on every run. The only correct way to update any value in `global.json` is to update `mcp_config.json` first, then run `ag-switch.sh`. Editing `global.json` directly bypasses the sync pipeline and could cause `ag-switch.sh` to overwrite manual changes silently on the next run — or in a large project, push stale/corrupted config to all projects simultaneously.
**Impact (this session):** Minimal — both files ended up with the same correct value. In a production project with multiple active services, a direct edit to `global.json` could silently overwrite or corrupt MCP configs for all projects on the next `ag-switch` run.
**Hard Rule:** `global.json` = **DO NOT TOUCH**. It is machine-written only. Any key change, token rotation, or server config update must go to `mcp_config.json` exclusively. `ag-switch.sh` handles propagation.
**Global Candidate:** PROMOTE TO CONSTITUTION — This is a behavioral law (not a technical tip). Must be added to GEMINI.md Section 4 (Operational Constraints / Security & Safety) as a hard stop.
