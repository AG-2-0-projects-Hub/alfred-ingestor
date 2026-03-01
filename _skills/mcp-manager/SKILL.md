# MCP Manager Skill

## Purpose
Manage MCP profiles for the current project. Identify which tools are needed,
find gaps, suggest new MCPs, and keep profiles lean over time.

---

## Trigger Conditions

Run this skill when:
- Starting a new project (after BLAST Phase 1)
- A task fails because a capability is missing
- User says "add X to this project" or "I need to do Y"
- User says "trim this project's profile"
- User asks "what MCPs do I need for this?"

---

## Architecture Reference

```
_mcp_profiles/
  global.json          ← master registry with API keys (gitignored)
  [project].json       ← list of MCP names only (committed to git)

mcp_config.json        ← active config AG reads (overwritten by ag-switch)
_scripts/ag-switch.sh  ← the engine that merges profile + keys → active config
```

**Rule:** Never modify `mcp_config.json` or `global.json` directly for project
changes. Always go through `ag-switch.sh` and the profile files.

---

## Task 1 — Identify Needed Tools

When starting a project or asked "what MCPs do I need":

1. Read the project's `CLAUDE.md` and `CONTEXT.md`
2. Read the BLAST Blueprint if it exists
3. Map project domains to MCP capabilities:

| Project need | MCP to use |
|---|---|
| Read/write to Supabase | `supabase-[project]` |
| Search live documentation | `context7` |
| GitHub repo operations | `github` |
| Web scraping / research | `firecrawl-mcp` |
| Notion read/write | `notion` |
| Web search | `firecrawl-mcp` |

4. Show the user the recommended list
5. Ask for confirmation before modifying the profile
6. Run: `bash ~/AG_master_files/_scripts/ag-switch.sh --add-mcp [name]`
   for each confirmed addition

---

## Task 2 — Add a New MCP to This Project

When user says "add [mcp-name] to this project":

**Step 1 — Check if it exists in global.json (synced from mcp_config.json):**
```bash
python3 -c "
import json
with open('$HOME/AG_master_files/_mcp_profiles/global.json') as f:
    cfg = json.load(f)
servers = list(cfg.get('mcpServers', {}).keys())
print('Available:', servers)
"
```

**Step 2a — If it exists in global, add to project profile:**
```bash
bash ~/AG_master_files/_scripts/ag-switch.sh --add-mcp [name]
```
Then hit Refresh in the AG MCP panel. Done.

**Step 2b — If it does NOT exist in global:**
Tell the user:
> "This MCP isn't registered yet. Add it via the AG MCP panel to
> mcp_config.json as you normally would. ag-switch will sync it into
> global.json automatically on next run. Once added, confirm and I'll
> add it to this project's profile."

After they confirm it's added to mcp_config.json:
```bash
bash ~/AG_master_files/_scripts/ag-switch.sh --add-mcp [name]
```

---

## Task 3 — Identify Capability Gaps

When a task fails or user asks "can we do X":

1. Identify what capability is needed
2. Check current project profile:
```bash
bash ~/AG_master_files/_scripts/ag-switch.sh --list
```
3. If the capability exists in an active MCP → it's a usage issue, not a gap
4. If not covered → identify which MCP would provide it
5. Search for it via GitHub MCP if unknown:
   - Search: `site:github.com mcp-server [capability]`
   - Check `_skills/_scanner/trusted-repos.md` for known sources
6. Present finding to user: MCP name, what it does, how to add it
7. **Never install an MCP without user confirmation**

---

## Task 4 — Trim a Profile

When user says "trim this project" or approaching 100-tool cap:

1. Ask the user: "Which tools did you NOT use in recent sessions?"
   (Do not auto-detect — the user knows their workflow)
2. For each confirmed removal:
```bash
bash ~/AG_master_files/_scripts/ag-switch.sh --remove-mcp [name]
```
3. Run ag-switch to reload:
```bash
bash ~/AG_master_files/_scripts/ag-switch.sh
```
4. Log the trim decision in the project's `lessons.md`:
```markdown
## [Date] — MCP Profile Trim
**Removed:** [mcp-names]
**Reason:** Not used in practice
**Global Candidate:** No
```

---

## Task 5 — Session Start (Auto-Switch)

When Gemini initializes a session:

1. Check the open workspace — is this a project folder or AG_master_files root?
   - **If at AG_master_files root:** Do NOT run ag-switch. Say:
     "You are at the AG root level — ag-switch only runs inside a project folder.
     Open a project folder to activate its MCP profile."
   - **If inside a project folder:** Continue to step 2.

2. Read `CLAUDE.md` to confirm project name (first heading, before the dash).

3. Check if `_mcp_profiles/[project].json` exists.
   - If yes → run ag-switch:
     ```bash
     bash ~/AG_master_files/_scripts/ag-switch.sh
     ```
     Tell the user: "MCP profile switched to [project]. Hit Refresh in the MCP panel."
   - If no profile exists → tell the user:
     > "No MCP profile found for this project. Run new-project.sh or
     > create `_mcp_profiles/[project].json` manually."

---

## Hard Rules

- Never modify `global.json` to remove entries — it's the master registry
- Never run ag-switch without telling the user what's changing
- Never add an MCP to a project without confirming it's needed
- Always remind user to hit Refresh in the MCP panel after any switch
- Profile files (`[project].json`) are committed to git — they contain no secrets
- `global.json` is gitignored — it contains API keys. Never commit it.
