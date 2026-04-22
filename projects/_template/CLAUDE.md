# [Project Name] — Local Law

**Active Workspace:** `projects/[project-name]/` — all file operations scoped here.
**Inherits:** AG Global Constitution (GEMINI.md)
**Overrides:** None
**Stack:** [Define after BLAST Blueprint phase]
**Data Schema:** [Define after BLAST Blueprint phase]

---

## Shell Execution Environment

**CRITICAL:** All terminal commands run in WSL2 (Ubuntu 24.04) — never Git 
Bash, PowerShell, or cmd.
- All tools (node, npm, npx, python, pip) are installed in WSL2 only
- Windows paths (`C:\`, `D:\`) are never valid for command execution
- If a command fails with "not found" — wrong shell context, not missing tool

---

## Shared Resources

This project reads from AG shared resources. Never create local copies.

| Resource | Path |
|---|---|
| Skills | `~/AG_master_files/_skills/` |
| Global Lessons | `~/AG_master_files/_global_lessons/lessons.md` |
| Protocols | `~/AG_master_files/_protocols/` |

---

## Database (Supabase) — If applicable

Claude Code accesses Supabase via REST API — not MCP.
MCP is registered on the Gemini side only (via ag-switch profile).
REST endpoint and anon key are in `.env` — never hardcoded.

---

## Git Protocol (User Executed)

This project has its own remote separate from AG_master_files origin.
**Do not execute git pushes autonomously.** Instead, prompt the user to:
1. Push using: `git subtree push --prefix=projects/[project-name] [remote-name] main`
   *(Never use plain `git push` inside this project folder)*
2. Verify remote SHA matches local after pushing.

---

## Supabase Connection
*(Populate after new-project.sh runs)*
**MCP name:** —
**project_ref:** —
