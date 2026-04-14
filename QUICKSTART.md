# the-ingestor — Quickstart

## Switch MCP Profile
Activates the right tools for your current task. Run this at the start of every session or when switching tasks.
```
bash ~/AG_master_files/_scripts/ag-switch.sh the-ingestor
bash ~/AG_master_files/_scripts/ag-switch.sh the-ingestor [task-profile]
```
Or via shortcut: `Ctrl+Shift+P → Run Task → Sync AG MCP Profile`
Check `mcp-profile.json` in this workspace for available task profiles.

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
