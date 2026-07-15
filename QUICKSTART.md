# the-ingestor — Quickstart

## Switch MCP Profile
Activates the right tools for your current task. Run this at the start of every session or when switching tasks.
```
bash ~/AG_master_files/_scripts/ag-switch.sh the-ingestor
bash ~/AG_master_files/_scripts/ag-switch.sh the-ingestor [task-profile]
```
Or via shortcut: `Ctrl+Shift+P → Run Task → Sync AG MCP Profile`
Check `mcp-profile.json` in this workspace for available task profiles.

## Add a New MCP (visible to both Gemini and Claude)
1. Add the server via the Antigravity MCP panel (this writes the command/args/key into `config/mcp_config.json` — the only step that should touch that file).
2. Decide which specific tools it should expose (explicit allowlist, not everything).
3. Run:
   ```
   bash ~/AG_master_files/_scripts/ag-switch.sh --enable <mcp> tool1,tool2 the-ingestor
   ```
4. Restart your Claude Code session. Gemini picks it up on its next MCP panel refresh.

## Kick Off This Project
Run these in order at the start of a new project:
1. Tell Gemini: "Run BLAST Phase 1" — defines stack, schema, and project domains
2. Tell Gemini: "Run the Skill Scanner" — finds the most relevant skills for this project
3. Tell Gemini: "Run mcp-tool-manager" — populates tool allowlists in the MCP profile

## Available Skills
Browse the `_skills/` folder in this workspace to see all available global skills.
Tell Gemini to use a skill: "Read and follow `_skills/[skill-name]/SKILL.md`"

## Session Start
```
git pull
bash ~/AG_master_files/_scripts/ag-switch.sh the-ingestor
```

## Session End
```
git add . && git commit -m "Session: [description]" && git push
```

## QA System

The Alfred QA system tests scenarios end-to-end against staging. Three commands, all invoked in Claude Code:

| When | Command | What it does |
|---|---|---|
| After making code changes | `/qa-changed-since` | Runs only scenarios affected by your changes (fast, ~$1) |
| Before merging staging → main | `/qa-full` | Runs the entire scenario matrix (~$6–20, 10–30 min) |
| Weekly | `/qa-explore` | Gemini wanders the app as a confused guest, logs anomalies |

All runs target the staging URL only. Reports land in `_tests/reports/`.

**New-feature flow (PRD-driven):** describe the feature → Claude drafts scenario rows in `_tests/scenarios.md` → implement → `/qa-changed-since` until clean → `/qa-full` before merging to main.

**Bug-driven regressions:** when a bug surfaces, Claude adds a regression scenario to `_tests/scenarios.md` *before* fixing. Each bug becomes a permanent guardrail.

See `_Context/plans/alfred-phase6-perspective-parity-and-testing.md` for the full architecture.
