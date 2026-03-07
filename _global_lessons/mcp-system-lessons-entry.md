## 2026-03-01 — MCP Profile System

**Context:** AG has a hard 100-tool limit across all MCP servers. As projects
and MCPs multiply, manually toggling tools in the UI is unsustainable — it
causes silent failures when a tool is off in one project and forgotten in
another. There is no native per-project MCP config in AG (open feature request
on AG's forum as of March 2026).

**Discovery:** Built a profile-based MCP management system. Each project
declares which MCPs it needs. ag-switch builds the active config from that
declaration. AG reads mcp_config.json as always — it never knows the difference.

**Architecture:**
```
mcp_config.json                       ← Live active config. Add all new MCPs here
                                        via the AG MCP panel as always.
                                        Never committed to git.
_mcp_profiles/global.json             ← Steady state master. All MCPs present,
                                        all tools disabled.
                                        ag-switch absorbs new MCPs here automatically.
                                        Gitignored. NEVER edit manually.
_mcp_profiles/[project].json          ← Named profiles with explicit tool allowlists.
                                        (No API keys). Committed to git.
_scripts/ag-switch.sh                 ← The engine. On every run:
                                        0. Absorbs missing MCPs into global.json
                                        1. Resets mcp_config.json from global.json
                                        2. Applies project profile, enabling declared tools
_skills/mcp-tool-manager/SKILL.md     ← Edits project profiles. NEVER touches global.json
```

**How it works step by step:**
1. You add a new MCP to mcp_config.json via the AG MCP panel as always
2. ag-switch absorbs that entry into global.json automatically on next run (tools disabled)
3. You tell Gemini to run mcp-tool-manager to add the tools to a named profile in [project].json
4. ag-switch resets mcp_config.json, then enables only the tools declared in the active profile
5. AG reads the result — only the right tools are live for this task

**How to start a project session:**
Open project folder in AG. tasks.json auto-fires ag-switch (applies base profile).
Hit Refresh in the AG MCP panel. Done.
Mid-session task switch: run ag-switch [project] [task-profile], then hit Refresh.

**How to add an MCP to a project mid-session:**
1. Add it to mcp_config.json via the AG MCP panel (as always)
2. Tell Gemini: "Add [mcp-name] to this project's profile and run ag-switch"
3. Hit Refresh. Other projects unaffected.

**How to add an MCP at the global level only (not for any specific project):**
Add it via the AG MCP panel to mcp_config.json. Do nothing else.
It sits available in the registry until a project needs it.
ag-switch syncs it into global.json automatically on next run.

**How to trim a profile:**
Tell Gemini: "Trim the [project] MCP profile"
Gemini asks which tools you didn't use, removes them from [project].json,
re-runs ag-switch. You confirm before anything is saved.

**How to see what's currently active:**
Tell Gemini: "List active MCPs"

**Working at AG_master_files root (no project open):**
Do NOT run ag-switch at root level — it will exit with a clear message.
mcp_config.json retains whatever profile was last activated.

**Security:**
- `mcp_config.json` is the original home of all API keys — gitignored, never committed
- `_mcp_profiles/global.json` mirrors those keys — also gitignored, also never committed
- Back up BOTH manually in a password manager
- `_mcp_profiles/[project].json` files contain MCP names only — safe to commit

**Known limitation:**
ag-switch requires a terminal run + manual Refresh click in the MCP panel.
AG has no hook to trigger scripts on folder open (as of March 2026).
GEMINI.md Section 14 instructs Gemini to run it at session start, but Gemini
fires after you send the first message — not before.

**Global Candidate:** Yes — promoted here.
