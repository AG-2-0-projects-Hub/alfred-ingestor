# the-ingestor — Local Law

**Active Workspace:** `projects/the-ingestor/` — all file operations scoped here unless explicitly stated otherwise.
**Inherits:** AG Global Constitution (GEMINI.md)
**Also inherits:** Root `CLAUDE.md` — read it at session start.
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
| Global Lessons Index | `~/AG_master_files/_global_lessons/lessons_index.md` |
| Protocols | `~/AG_master_files/_protocols/` |

**Before infra/security/secrets/deploy/regex/MCP-config work:** grep
`_global_lessons/lessons_index.md` (not the full `lessons.md`) for tags
matching the task. If a line looks relevant, open `lessons.md` at that date
heading before proceeding.

---

## Session Start
**Before any other action:** read `CONTEXT.md` and `_Context/session-digest.md` (if present) to know exactly where the project stands and what happened last session.

**Conditional:** if `graphify-out/GRAPH_REPORT.md` exists for this project, consult it before raw
files for architecture/structure questions (see root `CLAUDE.md` §10). Skip if it doesn't exist —
nothing else changes.

### Updating `_Context/session-digest.md`
This file holds the **last 3 sessions** as separate dated entries (newest first) — including parallel sessions — so a fresh session sees everything recent, not just whichever session updated it last.
- **Never fully replace the file.** Re-read it fresh immediately before editing, **prepend** a new dated entry for the current session, and if that makes more than 3 entries, delete only the oldest one.
- If a parallel session already added its own entry since you last looked, keep it — add yours alongside, don't overwrite.
- Full permanent history (not capped at 3) always lives in `CONTEXT.md`.

---

## Session End / Wrap-up

**Whenever the user asks to wrap up, end the session, or otherwise signals they're done for now
— update both of these, every time, without being asked individually for each:**
1. `CONTEXT.md` — **append** a new entry to the bottom of `## Accomplished` (oldest-first,
   append-only — never prepend, never rewrite/move an existing entry; see the length-target rule
   immediately below), and refresh `## Pending`/`## Unresolved Decisions` at the top of the file
   to drop resolved items and add new ones.
2. `_Context/session-digest.md` — prepend a new dated entry per the rules above (cap at 3).
3. **Conditional — Graphify:** if `graphify-out/` exists for this project, refresh it
   (`graphify update .` — free/local unless docs changed), then re-export the Obsidian vault
   notes for this project (`graphify export obsidian --dir ~/AG_master_files/.obsidian-vault/Projects/the-ingestor`)
   so the vault reflects the refreshed graph — and fold any touched
   `~/AG_master_files/.obsidian-vault/Global/` notes into this same commit — never a separate
   one. Skip entirely if graphify isn't installed/run for this project yet.

### `CONTEXT.md`'s entry-length target (keeps it from re-bloating without splitting the file)

`CONTEXT.md` is a single file, append-only, single source of truth — no separate archive, no
lossy condensing, nothing ever rewritten after the fact (established 2026-08-07 in reflip after an
earlier two-tier/archive-file design was tried and explicitly rejected; see global lesson of the
same date). What keeps it from re-growing unbounded is discipline at write time, not a later
cleanup pass:

- **Target ~25-40 lines per session entry, hard ceiling ~50.** Capture decisions, why, real
  bugs found+fixed, and what shipped. Skip step-by-step verification narration (which command
  was run, what each log line said) — that already lives in git commit history and the code itself.
- If a session genuinely needs a deeper record (rare — a big multi-day build, a research
  session), write it to its own doc under `_Context/` and link it from the terse entry.
- Session start only ever reads the **last ~5 entries** of `## Accomplished` (see Session Start
  above) — the length target keeps that tail read cheap forever, regardless of how large the
  full file grows underneath it.

---

## Fix/Feature Completion Workflow

**After finishing a fix or feature (tests passing, typecheck clean, locally verified where
possible) — proactively ask something like "ready to redeploy and test?" instead of going quiet
and waiting for the user to notice it's done and separately prompt for a deploy.** This does not
relax the Git hard rules below — a push/deploy still needs the user's explicit go-ahead — it
just means Claude surfaces that question itself rather than making the user chase it. Applies
whether the fix was requested standalone or is one item off a running queue/backlog within the
same session.

---

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
