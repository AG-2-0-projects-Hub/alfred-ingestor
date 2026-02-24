# Agent Manager Context
**Runtime:** Windows host shell — treat as CMD-safe

## Workspace Root
All AG project files live here:
`\\wsl.localhost\Ubuntu-24.04\home\santoskoy\AG_master_files`

**Not the AG brain — do not write project files here:**
`C:\Users\San_8\.gemini\antigravity\` (AG's internal state only)

## How to Navigate
Always use `wsl` wrap. Never bare Linux commands, `~/`, or Windows drives.

`wsl ls /home/santoskoy/AG_master_files` — list workspace  
`wsl cat /home/santoskoy/AG_master_files/[path]` — read any file  
`wsl find /home/santoskoy/AG_master_files -name "[name]"` — find anything  

**Never search:** `C:\`, `D:\`, OneDrive, Old Santoskoy backup, BACKUP folders.

## Session Start
Run the list command above. Confirm `GEMINI.md` is visible.
If it fails, stop and report the exact error — do not proceed.

## Structural Folders
- `_skills/` — agent capabilities
- `_protocols/` — workflow frameworks  
- `_global_lessons/` — promoted cross-project knowledge
- `projects/` — individual project workspaces