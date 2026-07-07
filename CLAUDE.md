# the-ingestor — Local Law

**Active Workspace:** `projects/the-ingestor/` — all file operations scoped here unless explicitly stated otherwise.
**Inherits:** AG Global Constitution (GEMINI.md)
**Also inherits:** Root `CLAUDE.md` — read it at session start.
**Overrides:** None
**Stack:** [Define after BLAST Blueprint phase]
**Data Schema:** [Define after BLAST Blueprint phase]

## Session Start
**Before any other action:** read `CONTEXT.md` and `_Context/session-digest.md` (if present) to know exactly where the project stands and what happened last session.

### Updating `_Context/session-digest.md`
This file holds the **last 3 sessions** as separate dated entries (newest first) — including parallel sessions — so a fresh session sees everything recent, not just whichever session updated it last.
- **Never fully replace the file.** Re-read it fresh immediately before editing, **prepend** a new dated entry for the current session, and if that makes more than 3 entries, delete only the oldest one.
- If a parallel session already added its own entry since you last looked, keep it — add yours alongside, don't overwrite.
- Full permanent history (not capped at 3) always lives in `CONTEXT.md`.

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

---

## QA Workflow

### On any fix or feature
After closing out any fix or feature with observable behaviour, append **one row** to the `## Pending intake` section of `_tests/scenarios.md`. Do not create a full scenario — just log the entry. Use the `Group with` column to flag entries that share a flow and should be merged into one compound scenario when promoted.

### Promotion rule — run before every `staging → main` merge
1. Review the pending intake table
2. Group rows by flow using the `Group with` column
3. For each group: create one proper scenario (or extend an existing one) in the relevant A–H section of `_tests/scenarios.md` — multi-step assertions are preferred over micro-scenarios
4. Delete the promoted intake rows
5. Run any new Layer 1 scenarios immediately; schedule Layer 2 scenarios for the next Playwright run

### What does NOT need a pending-intake entry
- Pure cosmetic changes (spacing, colour tweaks) with no assertable state
- Changes already covered by an existing passing scenario
- Changes to this file or other docs
