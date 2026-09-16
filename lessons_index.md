# the-ingestor Lessons Index

One line per lesson in `lessons.md`. Grep this file for tags matching the current task
before infra/security/secrets/regex/deploy/MCP-config/git work — do NOT read the full
`lessons.md` for a routine task. Only open `lessons.md` (jump to the matching date
heading) once a line here looks relevant. Checked alongside (not instead of) the global
index at `_global_lessons/lessons_index.md`.

| Date | Hook | Tags |
|---|---|---|
| 2026-04-14 | RESOLVED — flutter run -d chrome crashes on Windows Chrome's CP1252 stdout in WSL2; use web-server or native Linux Chrome | flutter, chrome, wsl2, utf8, resolved |
| 2026-04-15 | RESOLVED — mcp-tool-manager skill doesn't affect Claude Code's own MCP config file | mcp-config, skill, resolved |
| 2026-07-13 | 🔴 Prod Vercel publicly served the service_role key as SUPABASE_ANON_KEY for ~1 day — decode every deployed key, never assume anon just because it's a JWT | secrets, supabase, service-role, key-rotation, critical |
| 2026-07-13 | Cloud Run BackgroundTasks freeze on Telegram replies — min-instances != CPU-always-allocated; fixed via Cloud Tasks | cloud-run, background-tasks, telegram, cloud-tasks, resolved |
| 2026-07-17 | Cloud Build trigger needs its own repo-connection step; obvious *.vercel.app subdomain may already be taken | cloud-build, vercel, deploy-trigger |
| 2026-07-20 | WSL has no pip/venv and sudo can't prompt mid-session — use pip's standalone pip.pyz zipapp instead; gcloud needs its absolute path, not a $PATH export | wsl2, pip, gcloud, setup |
| 2026-07-21 | Stray project-local .mcp.json declared an unregistered/unaudited Supabase ref (inactive, left as-is) | mcp-config, supabase, config-drift |
| 2026-08-24 | Shared mcp_config.json/ag-switch had no folder-open trigger, so a prior project's MCPs stayed active — fixed with per-project .mcp.json | mcp-config, ag-switch, isolation, resolved |
| 2026-09-03 | Bash-tool -> WSL `$(...)` command substitution silently returns empty — use file redirection/pipes instead, never capture into a var | wsl2, bash-tool, command-substitution, curl, debugging |
| 2026-09-15 | Ad-hoc grep/sed "redaction" of a secrets file leaks the value when the assumed format is wrong — use a real parser or an anchored `^KEY=` capture, never regex-strip-after | secrets, redaction, grep, sed, structural-fix |
| 2026-09-16 | Bash tool can lose its ability to invoke `wsl` after `cd`-ing across a Windows-path/WSL-UNC boundary (`C:/Program: No such file or directory` on every subsequent `wsl bash -c`) — retry via the PowerShell tool instead of debugging cwd | bash-tool, wsl2, powershell, tooling, environment |
| 2026-09-16 | The Edit tool silently drops a shell script's executable bit on every write (3/3 this session) — `ls -la`/`git diff --summary` any script file before committing, don't assume the mode survived | edit-tool, file-mode, executable-bit, wsl2, tooling |
| 2026-09-16 | Re-hit an ALREADY-DOCUMENTED shell-quoting bug (backticks in a commit message via `wsl bash -c "..."` — outer double quotes don't block backtick expansion) because the mandated lessons-index check was skipped; also deferred lesson-logging to session-end instead of immediately | shell-quoting, wsl2, git-commit, lessons-discipline, process |
| 2026-09-16 | `git checkout -- <file>` to undo a throwaway test edit also silently discarded a real uncommitted lesson entry in the same file — file-scoped discards need the same `git status` check as tree-wide ones | git-checkout, destructive-command, git-status, process |
| 2026-09-16 | `/usr/local/bin/flutter` symlink is dangling (target no longer exists) — the working install is `/snap/bin/flutter`, needs a login shell (`bash -lc`) since `bash -c` has an empty PATH | flutter, wsl2, symlink, snap, tooling |
| 2026-09-16 | Supabase `query_logs` (edge_logs/realtime_logs) proves in under a minute whether a "stuck" bug is network delivery vs. client-side logic — filter by `request.path`/`request.search`, check `select distinct source`/`limit 1` first for real field names | supabase, query_logs, debugging, edge-logs, technique |
