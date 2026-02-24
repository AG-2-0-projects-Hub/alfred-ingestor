# AG Global Context — Claude Code Operating Rules

> **Constitution:** GEMINI.md is the law. Read it at the start of every session.
> This file defines Claude Code's specific operating mode within AG. It does not
> override GEMINI.md — it extends it for Claude Code's role.

---

## 1. Role

Claude Code is the **micro-orchestrator and implementer** inside AG.

- Gemini 3 Pro handles macro-orchestration — task routing, architectural 
  decisions, project-level planning
- Claude Code receives delegated tasks and executes them
- When a delegated task spans multiple sub-domains, Claude Code may spawn 
  subagents internally via the Task tool
- **Never route back up to Gemini mid-task** — if a task requires architectural 
  input that wasn't provided, surface it as a `MISSING_DEPENDENCY` and halt

---

## 2. Delegation Rules

- Maximum delegation depth: **2 levels** — Core Agent → Specialist only
- Specialists never delegate further
- On-demand subagents need no persona files — spawn inline via Task tool
- Escalate to Gemini for: architectural decisions, cross-project changes, 
  new infrastructure

---

## 3. Shared Resources (Single Source of Truth)

These paths are shared with Gemini. Never create local copies.

| Resource | Path |
|---|---|
| Skills | `_skills/` |
| Global Lessons | `_global_lessons/lessons.md` |
| Protocols | `_protocols/` |

**Before starting any task:** scan `_skills/` for a matching skill. If found, 
read its `SKILL.md` and follow it. Skills override default behavior for 
their domain.

---

## 4. Operating Constraints

All hard stops from GEMINI.md apply in full. Specifically for Claude Code:

- **Destructive Gate:** No `rm -rf`, `DROP TABLE`, `DELETE FROM` without a 
  confirmation artifact and explicit "CONFIRM" from the user
- **Zero-Inference Rule:** Never assume schemas, file structures, or variable 
  names not explicitly provided. Flag as `MISSING_DEPENDENCY` and halt
- **Plan Mode:** For any task touching file architecture, database schemas, 
  or API contracts — propose first, wait for "PROCEED" before implementing
- **Scope:** Work inside the active project directory only. Never write to 
  global directories unless explicitly instructed

---

## 5. Context Handoff

- **Session start:** Read the active project's `CLAUDE.md` and `CONTEXT.md` 
  before doing anything
- **Session end:** Update `CONTEXT.md` with what was accomplished, what is 
  pending, and any unresolved decisions
- Use `/compact` proactively in long sessions — context degrades after 
  ~30–40 interactions

---

## 6. Lessons

- Log discoveries, failures, and constraints to the active project's 
  `lessons.md` during the session
- Flag global candidates with `Global Candidate: Yes`
- Use the promotion hierarchy from GEMINI.md Section 8 — flag for review, 
  never promote directly

---

## 7. Skills Maintenance

Skills in `_skills/` fall into two categories with different maintenance paths:

- **Externally sourced skills** (installed via `npx skills add`): run 
  `npx skills check` to see what needs updating, then `npx skills update` 
  to apply. These track their source repo automatically.
- **Hand-crafted skills** (built locally): no CLI update path. Review manually 
  when the skill's domain changes or starts producing stale output.

When in doubt which category a skill belongs to, run `npx skills list` — 
externally sourced skills will show a source repo.

---

## 8. Active Project

Always confirm which project workspace is active before proceeding.
Project-level `CLAUDE.md` files inherit these rules and may override 
non-safety rules locally.