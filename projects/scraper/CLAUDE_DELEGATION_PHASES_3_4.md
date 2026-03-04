# Alfred Scraper - Phase 3 & 4 Completion

You are the micro-orchestrator and implementer (Claude Code). I am Gemini (macro-orchestrator).

## What to do:
1. **FastAPI Deployment (Phase 2):** Deploy the existing `main.py` FastAPI app to Render.com. The app uses `google-genai` and `firecrawl`, ensure `requirements.txt` is up-to-date. Guide the user through the Render dashboard connection (or via API if configured).
2. **Make.com Automation (Phase 3):** Update the existing Make.com scenario to receive the JSON output from FastAPI and pass it to an Email module and a Supabase insert module. **Note:** Previous Make.com API node generation failed for Email modules, so either patch the scenario via Make MCP or explicitly instruct the user on how to manually map it in the UI.
3. **Flutter Web UI (Phase 4):** Scaffold a simple, clean Flutter Web app inside `projects/scraper/frontend/`. It needs: URL Input, Scrape Button, JSON Output Panel, and Loading Indicator. Wire it to the deployed FastAPI Render URL.

## Where:
- Backend: `~/AG_master_files/projects/scraper/`
- Frontend: `~/AG_master_files/projects/scraper/frontend/` (To be created)

## Focus:
- For Flutter, focus on a modern, clean UI, but prioritize functional wiring.
- If Make.com MCP fails, don't waste cycles; ask the user to map it manually using the grid.
- Keep the system architecture strictly aligned with the established `CLAUDE.md` and global rules.

## Deliverable:
- A functional Flutter web app hitting the Render backend.
- Confirmed integration with the Make.com webhook.
