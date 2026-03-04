# Agent Team Protocol
**Version:** 1.0 | **Updated:** 2026-02-23

> This is a decision guide. It tells you whether a project needs agents,
> how many, and what kind. Do not build agent teams by default.

---

## 1. The Orchestration Model
```
You
 └── Gemini (macro-orchestrator)
      └── Claude Code (micro-orchestrator + implementer)
           ├── Subagent A  ← Task tool, parallel
           ├── Subagent B  ← Task tool, parallel
           └── Subagent C  ← Task tool, parallel
```

**Gemini's job:** Receive the task, plan the breakdown, delegate to Claude Code
with explicit boundaries and success criteria. Never implement directly.

**Claude Code's job:** Execute the delegated task. Decide internally whether
to run sequentially or spawn subagents via the Task tool. Report completion
back to Gemini.

### The Manual Handoff Ritual (Hard Rule)
When Gemini delegates to Claude Code, it **MUST NEVER** invoke `claude` as a subprocess. Instead, follow this exact ritual:
1. Gemini completes planning and writes `CLAUDE_DELEGATION_PHASES_X.md` to the workspace.
2. Gemini uses `notify_user` to say: "Delegation file ready. Open Claude Code and paste: 'Please execute the delegation plan in CLAUDE_DELEGATION_PHASES_X.md'"
3. User pastes the prompt into Claude Code.
4. Claude executes the work.
5. User replies to Gemini with the outcomes or confirming completion.

**Subagents:** Claude Code's internal workers. Spawned inline via Task tool
when parallelism is worth it. They report back to Claude Code only — they
don't communicate with each other or with Gemini.

**You never manage subagents directly.** That's Claude Code's decision.

---

## 2. The Decision Gate

Answer these before building any agent structure:

| Question | Yes | No |
|---|---|---|
| Does this project span 3+ distinct domains? | Agent candidate | Single agent |
| Will it run for more than a few sessions? | Agent candidate | Single agent |
| Do workstreams need to run in parallel? | Subagents useful | Sequential is fine |
| Would a single context window be a bottleneck? | Subagents useful | Single agent |

**Rule:** Fewer than 2 "yes" answers → use single agent. Don't over-engineer.

---

## 3. Delegation Tiers

### Tier 1 — Single Agent (default)
One Claude Code session handles everything sequentially.
Use for: focused tasks, single domain, short sessions.

### Tier 2 — Subagents via Task Tool
Claude Code spawns parallel workers internally. Workers report results back.
Workers do **not** communicate with each other.

Use for:
- Parallel research across multiple sources
- Independent workstreams with no shared state
- Tasks where only the result matters, not the process

**Token cost:** Moderate — each subagent runs in its own context.
**When Claude Code decides to use this:** Automatically, when it determines
parallelism speeds up a delegated task. You don't configure this.

### Tier 3 — Agent Teams *(not active — revisit when stable)*
Native Claude Code feature allowing direct teammate-to-teammate messaging.
Experimental, ~5x token cost, known bugs. Deferred.

---

## 4. Team Design (When Tier 2 Is Confirmed)

When a project genuinely needs a structured agent team, follow this process:

1. **List all domains the project touches**
2. **Map each domain to a potential agent role**
3. **Apply Occam's Protocol** — merge any role whose domain could be handled
   by another without loss of quality
4. **Define the routing table** only after the team is finalized
5. **Assign models:** Opus for strategic/complex reasoning,
   Sonnet for well-scoped implementation

---

## 5. ADK Pattern Reference

When a project being *built* is itself an agent application, use these patterns:

| Pattern | Use When |
|---|---|
| `SequentialAgent` | Step A must complete before step B |
| `ParallelAgent` | Independent tasks, fan-out then synthesize |
| `LoopAgent` | Iterative refinement cycles |
| `LlmAgent` + `transfer_to_agent` | Dynamic routing based on LLM judgment |

Reference: https://google.github.io/adk-docs/agents/multi-agents/

Note: ADK is installed at the **project level** when a project IS an agent
system. It is not an IDE-level dependency.

---

## 6. File Structure (Agent-Enabled Projects)
```
projects/[project-name]/
├── CLAUDE.md                    ← Project law (inherits GEMINI.md)
├── agents/
│   ├── README.md                ← Agent registry & routing table
│   ├── core/
│   │   ├── orchestrator.md      ← Orchestrator persona
│   │   └── [role].md
│   └── specialists/
│       └── [specialist].md
└── .claude/
    └── agents/                  ← Claude-native wrappers (thin YAML + pointer)
        └── [agent].md
```

**Rules:**
- Agent personas live in `agents/` — single source of truth
- `.claude/agents/` wrappers are thin: YAML frontmatter + pointer to persona only.
  Never duplicate the persona there.
- Two-level maximum — specialists never delegate further
- On-demand subagents need no files — spawn inline via Task tool

---

## 7. Spawn Prompt Rule

When Claude Code spawns a subagent, the prompt must include:
- **What** to do
- **Where** (specific files or paths)
- **Focus** (what matters, what to ignore)
- **Deliverable** (what done looks like)

Vague prompts waste tokens on exploration. Specific prompts go straight to work.

---

## 8. Maintenance

After a project using agents completes:
- Review `agents/README.md` — did the routing table hold?
- Log any structural decisions that should inform future teams to
  `_global_lessons/lessons.md`
- If a pattern proved reusable, document it in this file as a new section

---

## 9. Skill-to-Agent Mapping (Per Project)

> Run this process at the start of each new project, after the Skill Scanner
> has populated `_skills/` with relevant candidates.

**This is not a global decision.** The same skill may play different roles
in different projects. Decide per project, document in the project's `CLAUDE.md`.

### The Three Outcomes

| Outcome | Condition | Action |
|---|---|---|
| **Keep as skill** | Standalone capability invoked on-demand | Reference in project `CLAUDE.md` |
| **Promote to agent** | Has identity, domain ownership, decision logic | Refactor into `agents/` persona |
| **Embed into workflow** | Belongs inside a phase, not a standalone tool | Merge into relevant agent or protocol |

### The Process

1. List the domains this project touches
2. Run `npx skills list` to see what's available in `_skills/`
3. For each relevant skill, apply the three-outcome test above
4. Document decisions in the project's `CLAUDE.md` under a `## Skills` section
5. If promoting to agent, follow the file structure in Section 6

### Example `CLAUDE.md` Skills Section
```markdown
## Skills

| Skill | Role in this project |
|---|---|
| `troubleshooting-diagnostics` | Keep — invoked on-demand when bugs surface |
| `planning` | Embedded — planning runs inside BLAST Phase 1, not standalone |
| `error-handling-patterns` | Keep — reference during implementation |
```

### Rule
Never copy skills into the project directory. Always reference from `_skills/`.
Single source of truth — always.