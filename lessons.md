# Project Lessons Log
_Discoveries logged here during sessions. Global candidates flagged for promotion._

---

## 2026-05-12 — ag-switch extended to write Claude Code settings.json (resolves the 2026-04-15 gap)

**Context:** Claude Code in the AG IDE had no access to the MCPs Gemini was using. `~/.claude/settings.json` was empty, so no MCP tools loaded into Claude Code sessions. The 2026-04-15 lesson flagged this as a permanent split between the two configs.

**Discovery:**
1. **Two separate config endpoints, one source of truth is achievable.** Gemini reads `/mnt/c/Users/San_8/.gemini/antigravity/mcp_config.json`. Claude Code reads `/mnt/c/Users/San_8/.claude/settings.json` (Windows side, not WSL home). The two are independent. But ag-switch can write to both in one pass, using `global.json` + `[project].json` as the single source.
2. **Format translation is required, not a copy.** Claude Code does not understand Gemini's `disabled` / `disabledTools` fields. The translation is:
   - `disabled: true` MCP → omit from `mcpServers` entirely
   - `disabledTools: [tool_a, tool_b]` → add to `permissions.deny` as `mcp__<server>__<tool>` (hyphens in server name → underscores)
3. **Path trap (three layers — don't skip any).**
   - Layer 1: First assumption was `C:\Users\San_8\.claude\settings.json` = `/mnt/c/Users/San_8/.claude/settings.json`. WRONG for VS Code WSL Remote — the extension reads the WSL home, not the Windows mount.
   - Layer 2: Wrote `mcpServers` to `~/.claude/settings.json` (WSL home). `claude mcp list` still returned empty. `settings.json` is for Claude Code *settings* (permissions, model prefs) — it is NOT the MCP registry.
   - Layer 3 (correct): The MCP registry is `~/.claude.json` (a flat file in WSL home, distinct from the `~/.claude/` directory). `claude mcp add-json <name> <json> --scope user` writes here. `claude mcp list` reads here. ag-switch STEP 3 must write `mcpServers` to `~/.claude.json` and `permissions.deny` to `~/.claude/settings.json` — two separate files, two separate roles.
   - Bonus: `claude mcp list` run from inside WSL shows "Failed to connect" for all `wsl`-routed servers (WSL-in-WSL). This is a false negative — the VS Code extension starts these servers from the Windows host where `wsl` works fine. Do not treat this as an error indicator.
4. **Refresh model differs.** Gemini supports mid-session "Hit Refresh" in the MCP panel. Claude Code does NOT — MCPs only load at session boot. After ag-switch, you must start a new Claude Code session for the config to take effect.
5. **Non-managed fields must survive.** `~/.claude/settings.json` already holds user preferences (`effortLevel`, `model`, `permissions.allow`, hooks, etc.). The Claude-sync step must merge only `mcpServers` and `permissions.deny`, leaving everything else verbatim.

**Impact:**
- `_scripts/ag-switch.sh` gained a STEP 3 that emits a Claude-flavored config to `/mnt/c/Users/San_8/.claude/settings.json` after every switch. Also added a `--quiet` flag (uses `exec >/dev/null` after the `--list` check) for use from hooks or scripts.
- `_scripts/new-project.sh` now calls `ag-switch --quiet [project]` at the end of Step 5 so new projects bootstrap a working Claude Code MCP config automatically, and the "Next steps" block now mentions starting a new Claude Code session.
- The 2026-04-15 lesson below is **resolved by this change**. Adding a Supabase MCP for a project no longer requires a manual edit to `~/.claude/settings.json` — running ag-switch propagates it to both sides.
- One pre-existing quirk surfaced and was **not** fixed in scope: ag-switch's STEP 2 controls per-tool allowlists but not per-MCP inclusion. Any MCP marked `disabled: false` in `global.json` leaks into every project regardless of whether it's listed in `[project].json`. Example: `supabase-scraper` showed up in the-ingestor's active MCPs even though it isn't in `the-ingestor.json`. Fix would be a one-line change in STEP 2 ("disable any server not in profile"). Flagged for a future task.

**Global Candidate:** Yes — this is the canonical pattern for any AG-managed machine. Promote the workflow, the path trap, and the format-translation rules to `_global_lessons/lessons.md`.

---

## Lesson: mcp-tool-manager skill does not affect Claude Code's MCP config
**Date:** 2026-04-15
**Component:** MCP / Tool Management
**Status:** RESOLVED 2026-05-12 — see the 2026-05-12 ag-switch extension lesson above
**Global Candidate: Yes**

### Finding
`mcp-tool-manager` edits `~/AG_master_files/_mcp_profiles/global.json`, which `ag-switch.sh` compiles into Gemini's config at `/mnt/c/Users/San_8/.gemini/antigravity/mcp_config.json`. It has no effect on Claude Code's MCP config, which lives in `C:\Users\San_8\.claude\settings.json` on the Windows host and is managed separately via the Claude Code MCP panel in the AG IDE.

### Impact
Invoking `mcp-tool-manager` from inside a Claude Code session to "activate" a Supabase server will appear to succeed (global.json is updated) but the tools will never appear in the current or any future Claude Code session — because the target config file is different.

### Fix / Required Setup Step
To make a Supabase (or any MCP server) available in Claude Code:
1. Open the Claude Code MCP panel in AG (Windows side)
2. Add the server entry manually — same format as global.json but written to `C:\Users\San_8\.claude\settings.json`
3. Restart Claude Code / click Refresh

This is a **one-time setup step per MCP server** — not something `mcp-tool-manager` can automate from the WSL side.

### Workaround used this session
Used the Supabase Management REST API directly (`api.supabase.com/v1/projects/{ref}/...`) with the access token from `global.json` to manage storage buckets and policies — fully equivalent to the MCP tool path.

---

## Incident: FormatException: Invalid UTF-8 byte (at offset 41) — flutter run -d chrome
**Date:** 2026-04-14  
**Severity:** High  
**Component:** Flutter web / Chrome device launch  
**Status:** RESOLVED — 2026-04-14

### Root Cause (confirmed)
Flutter auto-detects `/mnt/c/Program Files/Google/Chrome/Application/chrome.exe` (Windows binary)
in WSL2. On German Windows 11 (CP1252 locale), Chrome emits a non-ASCII byte at **position 41**
of its startup stdout — almost certainly a German umlaut (ö/ü/ä = 0xF6/0xFC/0xE4 in CP1252,
invalid as a lone UTF-8 byte). Flutter reads Chrome's stdout via `_Socket._onData` and calls
`_Utf8Decoder.convertChunked` → FormatException → tool process crash. Byte offset 41 is
deterministic and reproducible (all 5 log files identical).

The crash has nothing to do with app source files or the missing `.env`. It occurs before the app
is even compiled.

### Fix Applied
1. **Immediate / WSL2 recommended:** Use `flutter run -d web-server --web-port 8080` via `run_dev.sh`.
   - Skips Chrome launch entirely — Flutter serves the built app on a local HTTP port.
   - Open `http://localhost:8080` in Windows Chrome manually.
   - Created `frontend/run_dev.sh` with this command.
2. **Permanent (enables `flutter run -d chrome`):** Install Google Chrome Linux native binary.
   - Download and install `google-chrome-stable_current_amd64.deb` from Google.
   - Flutter will then find `/usr/bin/google-chrome` (UTF-8 output) instead of the Windows binary.
   - Note: Ubuntu 24.04 snap-based Chromium will NOT work in this WSL env (snap unavailable).

### Bonus Bug Found and Fixed
`frontend/.env` had `SUPABASE_URL=https://inajlofycvmpitvljccy.supabase.co` but the anon key's
JWT `ref` field is `gcxxilzfhwlsjcvtpsvj` (matches CLAUDE.md `project_ref`). URL was wrong —
corrected to `https://gcxxilzfhwlsjcvtpsvj.supabase.co`.

### Fix Validation Checklist
- [x] Root cause identified — Windows Chrome CP1252 output in WSL2 pipe
- [x] `.env` file exists with corrected Supabase URL
- [ ] `flutter run -d web-server --web-port 8080` confirmed working (needs user validation)
- [ ] App loads at http://localhost:8080 in browser

---

## 2026-05-04 — Claude Code Shell Environment (Git Bash vs WSL2)

**Context:** Attempting to run `npx skills find` via Claude Code inside the-ingestor project.

**Discovery:** Claude Code launches in Git Bash (Windows) by default, not WSL2. 
Node, npm, and npx are installed in WSL2 only — invisible to Git Bash. All bare 
`npx`, `node`, `python` commands fail with "command not found" unless prefixed 
with `wsl bash -c`.

**Impact:** Added Section 9 (Shell Execution Environment) to root `CLAUDE.md` 
enforcing `wsl bash -c` prefix for all terminal commands. Added root `CLAUDE.md` 
inheritance pointer to `_template/CLAUDE.md` and the-ingestor `CLAUDE.md`.

**Global Candidate:** Yes — applies to every machine and every project.
