# Project Kickoff: Deterministic Workflow Protocol
**Version:** 1.0 | **Updated:** 2026-03-04

> This checklist ensures a stable, predictable, and fully-scoped progression from initial idea to implementation. This protocol is mandatory for all new AG projects.

---

## The 6-Step Kickoff Sequence

### 1. Brainstorm & Plan (Integrator Session)
- **Actor:** User + Gemini
- **Action:** Discuss the core goals, requirements, constraints, and general architecture.
- **Output:** A finalized "Logic Digest" summarizing the mechanical logic of the proposed system.

### 2. BLAST Phase 1 — Blueprint
- **Actor:** Gemini
- **Action:** Execute Phase 1 of the BLAST framework against the Logic Digest.
- **Output:** Confirm the targeted tech stack and define the exact data schema.

### 3. Skill Scanner execution
- **Actor:** Gemini
- **Action:** For every identified project domain, run the Skill Scanner.
- **Ref:** `_skills/skill-scanner/SKILL.md`
- **Output:** Relevant skills installed/symlinked and documented.

### 4. Populate Local Law (`CLAUDE.md`)
- **Actor:** Gemini
- **Action:** Finalize writing the active project's `CLAUDE.md`.
- **Requirements:**
  - Must declare the finalized Stack.
  - Must declare the finalized Data Schema.
  - Must list all active scoped MCPs (e.g., Supabase project_refs).
  - Must list all active Skill roles.

### 5. Implementation Kickoff (The Handoff)
- **Actor:** Gemini → User → Claude Code
- **Action:** Execute the **Manual Handoff Ritual**.
- **Process:**
  1. Gemini writes `CLAUDE_DELEGATION_PHASES_1.md` containing the step-by-step implementation tasks.
  2. Gemini informs User.
  3. User pastes the prompt into Claude Code: *"Please execute the delegation plan in CLAUDE_DELEGATION_PHASES_1.md"*
  4. Claude Code executes implementation.

### 6. Session End (Context Synchronization)
- **Actor:** Claude Code (or Gemini if resuming)
- **Action:** At the end of the session, update `CONTEXT.md`.
- **Output:** Accurately document what was accomplished, what is pending, and any unresolved decisions to ensure continuity for the next session.
