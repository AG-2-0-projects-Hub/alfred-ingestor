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
mcp_config.json                        ← SOURCE OF TRUTH. Add all new MCPs here
                                          via the AG MCP panel as always.
                                          API keys live here originally.
                                          Never committed to git.
_mcp_profiles/global.json             ← Auto-synced mirror of mcp_config.json.
                                          Keys are copied here by ag-switch,
                                          not entered here directly.
                                          Gitignored. NEVER edit manually.
_mcp_profiles/[project].json          ← List of MCP names only (no keys).
                                          Committed to git. Safe to share.
_scripts/ag-switch.sh                 ← The engine. On every run:
                                          1. Syncs mcp_config.json → global.json
                                          2. Builds scoped mcp_config.json from
                                             profile + keys in global.json
_skills/mcp-manager/SKILL.md          ← Governs all MCP operations for Gemini
```

**How it works step by step:**
1. You add a new MCP to mcp_config.json via the AG MCP panel as always
2. ag-switch syncs that entry into global.json automatically on next run
3. You tell Gemini to add the MCP to the relevant project's profile
4. ag-switch builds a scoped mcp_config.json with only that project's MCPs
5. AG reads the result — only the right tools are live for this project

**How to start a project session:**
Open project folder in AG. Gemini reads GEMINI.md Section 14 and runs ag-switch.
Hit Refresh in the AG MCP panel. Done.

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
