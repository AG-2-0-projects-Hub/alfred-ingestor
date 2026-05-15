# the-ingestor — Local Law

**Active Workspace:** `projects/the-ingestor/` — all file operations scoped here unless explicitly stated otherwise.
**Inherits:** AG Global Constitution (GEMINI.md)
**Also inherits:** Root `CLAUDE.md` — read it at session start.
**Overrides:** None
**Stack:** [Define after BLAST Blueprint phase]
**Data Schema:** [Define after BLAST Blueprint phase]

## Git — HARD RULES

**NEVER run `git commit` or `git push` on your own.**

Always use the safe-commit-n-push workflow:
1. Show the user what will be committed (files + proposed message)
2. Wait for explicit "yes" / "confirm" / "go ahead" approval
3. Only then stage, commit, and push

This applies to ALL commits — documentation, fixes, features, everything. No exceptions, no matter how small the change.

---

## Supabase Connection
**MCP name:** `supabase-the-ingestor`
**project_ref:** `gcxxilzfhwlsjcvtpsvj`
**Scoped to this project only.**
Use ONLY this MCP for all database operations in this project.
Never use the global `supabase` MCP when working inside this project.
