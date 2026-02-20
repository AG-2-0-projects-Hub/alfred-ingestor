# AG Superpowered IDE — Build Roadmap
**Version:** 1.1 | **Created:** 2026-02-19 | **Last Updated:** 2026-02-19 | **Status:** In Progress

> **Philosophy:** Each layer must be stable before the next builds on it.
> No skipping. Every step has a verification gate.

---

## Current Status

| Step | Description | Status |
|------|-------------|--------|
| Pre | Verify all tools accessible (git, node, npm, python, claude) | ✅ Done |
| 1 | Gemini API skill installed (Claude Code) | ✅ Done — ⚠️ See note below |
| 2 | Context7 MCP | 🔄 In Progress |
| 3 | GitHub MCP | ⬜ Pending |
| 4 | Firecrawl MCP | ⬜ Pending |
| 5 | Notion MCP | ⬜ Pending |
| 6 | Supabase MCP | ⬜ Pending |
| 7 | `_protocols/AGENT_TEAM.md` | ⬜ Pending |
| 8 | Update GEMINI.md v2.1 | ⬜ Pending |
| 9 | Rewrite CLAUDE.md (unified, comprehensive) | ⬜ Pending |
| 10 | Migrate skills from Windows to `_skills/` | ⬜ Pending |
| 11 | Skill-to-agent mapping review | ⬜ Pending |
| 12 | Skill Scanner Agent | ⬜ Pending |
| 13 | Alfred migration | ⬜ Pending |

**⚠️ Step 1 Note — Skill not yet active for Gemini:**
The `gemini-api-dev` skill was installed via `npx skills` for Claude Code only (`~/.agents/skills/`). Gemini is still generating deprecated SDK code (`google.generativeai`, `gemini-1.5-flash`). Two actions needed at Step 8:
1. Copy skill into `~/AG_master_files/_skills/gemini-api-dev/`
2. Add instruction to GEMINI.md: *"Before any Gemini API implementation, read `_skills/gemini-api-dev/SKILL.md` to verify current models and SDK syntax."*

**Long-term freshness:** Run `npx skills update` monthly to keep the skill current as Gemini evolves. Add this to your session start checklist.

---

## Architecture Overview

Before you start, understand what you're building across two distinct layers:

```
┌─────────────────────────────────────────────────────────┐
│  IDE LAYER (governs how Gemini/Claude work in sessions)  │
│  • GEMINI.md — The Constitution                          │
│  • _protocols/AGENT_TEAM.md — Orchestration rules        │
│  • _skills/ — Capabilities agents can invoke             │
│  • MCPs — External world connections                     │
└─────────────────────────────────────────────────────────┘
             ↓ Projects built inside AG may use ↓
┌─────────────────────────────────────────────────────────┐
│  PROJECT LAYER (deployed agent applications)             │
│  • Google ADK — When a project IS an agent system        │
│  • Claude Code Task tool — Sub-agent delegation          │
│  • Each project defines its own team using the protocol  │
└─────────────────────────────────────────────────────────┘
```

**The orchestration split:**
- **Gemini 3 Pro** = Macro-orchestrator. Sees the full workspace. Decides if a task needs one agent or many. Routes accordingly.
- **Claude Code** = Micro-orchestrator + implementer. Once delegated a task, it can spawn its own sub-agents internally via the Task tool. It never touches Gemini's routing domain.
- **No overlap. No duplication.**

**On Google ADK:**
ADK (`pip install google-adk`) is a Python/JS framework for building deployable agent *applications*. It is NOT the same as this protocol layer. ADK patterns (Sequential, Parallel, LLM-driven routing) deeply inform the design of `_protocols/AGENT_TEAM.md`, but ADK itself is installed at the project level when a project being built *is* an agent system. Reference: https://google.github.io/adk-docs/

---

## Layer 1 — Knowledge Foundation
> *Agents are only as smart as their knowledge. Fix this first.*

### Step 1: Install the Gemini API Skill (Global)

**Why first:** Gemini's built-in knowledge of its own SDK lags behind real releases. Gemini has evolved rapidly (1.5 → 2.0 → 2.5 → 3.0) with complete SDK rewrites. Without this, every agent and skill built on top will generate deprecated code from day one.

**Install:**
```bash
# List available skills first
npx skills add google-gemini/gemini-skills --list

# Install the Gemini API skill globally
npx skills add google-gemini/gemini-skills --skill gemini-api-dev --global
```

**Verify:** Open a fresh AG session and ask Gemini to write a simple Gemini API call. Confirm it uses current SDK syntax (not deprecated `PaLM` or `generativeai` v1 patterns).

**Gate:** ✅ Skill loads and Gemini produces current-SDK code → proceed to Layer 2.

---

## Layer 2 — External Connectivity (MCPs)
> *Without MCPs, agents are blind to the outside world. Install in priority order.*
> *Each MCP is verified with a test task before the next one is installed.*

### Step 2: Context7

**Why:** Gives agents live access to current library documentation. Agents stop hallucinating API signatures and deprecated method calls. Foundational — benefits every subsequent step.

**Install:**
```bash
# In your AG session or claude config
# Add to MCP config:
{
  "mcpServers": {
    "context7": {
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp"]
    }
  }
}
```

**Verify:** Ask an agent to look up the latest Supabase JS client API. Confirm it returns current docs, not cached knowledge.

---

### Step 3: GitHub

**Why:** Required for the Skill Scanner Agent (Layer 5). Also needed for Alfred migration and any project that interacts with repos.

**Install:**
```bash
# Add to MCP config:
{
  "github": {
    "command": "npx",
    "args": ["-y", "@modelcontextprotocol/server-github"],
    "env": {
      "GITHUB_PERSONAL_ACCESS_TOKEN": "<your-token>"
    }
  }
}
```

**Verify:** Ask an agent to list your repositories. Confirm it returns your actual GitHub repos.

---

### Step 4: Firecrawl

**Why:** Web research and scraping capability. Enables agents to pull live competitor data, documentation pages, and external context that isn't in Context7.

**Install:**
```bash
# Add to MCP config:
{
  "firecrawl": {
    "command": "npx",
    "args": ["-y", "firecrawl-mcp"],
    "env": {
      "FIRECRAWL_API_KEY": "<your-api-key>"
    }
  }
}
```

**Verify:** Ask an agent to scrape a simple webpage and summarize it.

---

### Step 5: Notion

**Why:** Knowledge base read/write. Agents can retrieve project context, log decisions, and push deliverables to Notion without manual copy-paste.

**Install:**
```bash
# Add to MCP config:
{
  "notion": {
    "command": "npx",
    "args": ["-y", "@modelcontextprotocol/server-notion"],
    "env": {
      "NOTION_API_KEY": "<your-integration-token>"
    }
  }
}
```

**Verify:** Ask an agent to retrieve a page from your Notion workspace.

---

### Step 6: Supabase

**Why:** Direct database access from inside the IDE. Lower priority than the others because Claude Code can handle Supabase via generated code, but this adds direct query capability for inspection and debugging tasks.

**Install:**
```bash
# Add to MCP config:
{
  "supabase": {
    "command": "npx",
    "args": ["-y", "@supabase/mcp-server-supabase@latest"],
    "env": {
      "SUPABASE_ACCESS_TOKEN": "<your-personal-access-token>"
    }
  }
}
```

**Verify:** Ask an agent to list the tables in a Supabase project.

---

### MCP Config Location

All MCPs live in your Claude Code config file:
```
~/.claude/claude_desktop_config.json
```
Or for Antigravity IDE, in the MCP settings panel. After each install, restart AG and verify the MCP appears in the active tools list.

---

## Layer 3 — Agent Architecture Protocol
> *Rules for building teams. Not a pre-built team — a walkthrough guide.*

### Step 7: Create `_protocols/AGENT_TEAM.md`

**Why this structure:** The protocol is a decision guide, not a template. Each project decides if it needs agents, how many, what kind — based on actual requirements. Avoid building agent teams for projects that don't need them.

**What to create:** `~/AG_master_files/_protocols/AGENT_TEAM.md`

This file should contain:

**Section 1 — The Decision Gate**
A checklist determining whether a project actually needs a multi-agent system:
- Does this project span 3+ distinct domains?
- Will it run for more than a few sessions?
- Does it require parallel workstreams?
- Would a single agent context window be a bottleneck?

If fewer than 2 answers are "yes" → use single-agent or basic workflow. Don't over-engineer.

**Section 2 — The Orchestration Model**
Document the confirmed split:
- Gemini = macro-orchestrator (reads task, decides routing, dispatches to Claude Code or sub-agents)
- Claude Code = micro-orchestrator + implementer (receives delegated tasks, may spawn Task tool sub-agents)
- Maximum delegation depth: 2 levels. No chains beyond Core Agent → Specialist.

**Section 3 — ADK Pattern Reference**
When building projects that ARE agent applications (not just governed by them), use ADK patterns:
- `SequentialAgent` — for ordered pipelines (step A must complete before step B)
- `ParallelAgent` — for independent concurrent tasks (fan-out, then synthesize)
- `LoopAgent` — for iterative refinement cycles
- `LlmAgent` with `transfer_to_agent` — for dynamic routing based on LLM interpretation
- Reference: https://google.github.io/adk-docs/agents/multi-agents/

**Section 4 — Team Design Walkthrough**
A guided process for sizing an agent team per project:
1. List all domains the project touches
2. Map each domain to a potential agent role
3. Apply Occam's Protocol — merge any agent whose domain could be handled by another without loss of quality
4. Define the Orchestrator's routing table only after team is finalized
5. Assign models: Opus for strategic/complex reasoning, Sonnet for well-scoped implementation

**Section 5 — File Structure**
The standard structure for an agent-enabled project:
```
projects/[project-name]/
├── CLAUDE.md                    ← Project law (inherits GEMINI.md)
├── agents/
│   ├── README.md                ← Agent registry & routing table
│   ├── core/                    ← Core agent persona files
│   │   ├── orchestrator.md
│   │   └── [role].md
│   └── specialists/             ← Sub-agent persona files
│       └── [specialist].md
└── .claude/
    └── agents/                  ← Claude-native wrappers (thin YAML + pointer)
        └── [agent].md
```

**Section 6 — Maintenance Rules**
- Agent personas live in `agents/` — single source of truth for both models
- Claude wrappers are thin — YAML frontmatter + pointer only. Never duplicate the persona
- Two-level maximum — specialists never delegate further
- On-demand agents need no files — the Core Agent spawns them inline via Task tool

---

### Step 8: Update `GEMINI.md` → v2.1

Add the following sections to GEMINI.md:

**Section: Agent Orchestration Protocol**
```markdown
## 9. Agent Orchestration Protocol

**Gemini's role:** Macro-orchestrator. When receiving a task:
1. Classify: Does this touch one domain or multiple?
2. Single domain → route directly to Claude Code with clear instructions
3. Multi-domain → consult `_protocols/AGENT_TEAM.md`, decompose into sub-tasks,
   dispatch Claude Code with explicit task boundaries and success criteria
4. Never do the implementation work — route it

**Agent team:** Only active if the current project has an `agents/` folder.
When it does, read `agents/README.md` to understand the routing table before proceeding.

**For projects that ARE agent applications:** See `_protocols/AGENT_TEAM.md`
for ADK patterns and team design guidance.
```

**Section: Shared Resources**
```markdown
## 10. Shared Resources (Single Source of Truth)

The following are shared between Gemini and Claude Code. Never duplicate them.

- **Skills:** `~/AG_master_files/_skills/` — All available skills for both models
- **Lessons:** `~/AG_master_files/_global_lessons/lessons.md` — Cross-project wisdom
- **Protocols:** `~/AG_master_files/_protocols/` — Workflow frameworks

**Gemini API Skill:** Before any Gemini API implementation, read
`_skills/gemini-api-dev/SKILL.md` to verify current models and SDK syntax.
Run `npx skills update` monthly to keep it current.
```

Version bump → v2.1, date stamp.

---

### Step 9: Rewrite Root `CLAUDE.md` (Comprehensive, Done Together)

**This is a full rewrite, not a patch.** We draft this together when we arrive here.

The new CLAUDE.md will cover:
- **Constitution pointer:** GEMINI.md is the law. All sessions initialize against it.
- **Shared resources:** `_skills/` and `_global_lessons/` are the single source of truth — Claude Code reads from and writes to the same locations as Gemini
- **Skill awareness:** Available skills live in `_skills/`. Read the relevant SKILL.md before starting any task that matches a skill's domain
- **Operating mode:** Implementation by default. Gemini macro-orchestrates; Claude micro-orchestrates via Task tool when needed
- **Delegation rules:** Max 2 levels. Escalate to Gemini for architectural decisions
- **Monthly maintenance:** Run `npx skills update` to keep skills current

**Do NOT use `claude /init`** — it generates generic context. We write this intentionally.

---

## Layer 4 — Skills Migration
> *Your existing skills, brought into the AG structure.*

### Step 10: Migrate Skills from Windows to WSL2

**Current location:** Windows laptop (local folder)
**Target location:** `~/AG_master_files/_skills/`

**Migration steps:**
```bash
# From Windows Explorer, drag your skills folder into:
\\wsl.localhost\Ubuntu\home\santoskoy\AG_master_files\_skills

# In WSL2, verify they arrived:
ls ~/AG_master_files/_skills/
# Expected: brainstorming, creating-projects, error-handling-patterns,
# find-skills, gemini-api-dev, integrator-assistant, planning,
# quantum-debugging, skill-creator, troubleshooting-diagnostics
```

**Zone.Identifier cleanup:**
```bash
# Windows adds metadata files on drag-drop — remove them:
find ~/AG_master_files/_skills -name "*.Identifier" -delete
```

---

### Step 11: Skill-to-Agent Mapping Review

Once migrated, review each skill against the new architecture. Each skill maps to one of three outcomes:

| Outcome | Condition | Action |
|---|---|---|
| **Keep as skill** | Standalone capability an agent invokes as a tool | Leave in `_skills/`, document in agent definitions |
| **Promote to agent** | Has identity, domain ownership, decision-making logic | Refactor into `agents/` persona format |
| **Embed into agent** | Belongs inside an agent's workflow section | Merge into the relevant agent's `.md` file |

Skills to review (from screenshot):
- `brainstorming` → likely keep as skill
- `creating-projects` → likely embed into BLAST protocol
- `error-handling-patterns` → keep as skill, reference in Systems Engineer agent
- `find-skills` → keep as skill (meta-skill for skill discovery)
- `gemini-api-dev` → now superseded by the global Gemini API skill from Step 1
- `integrator-assistant` → review for promotion to agent
- `planning` → review for promotion to agent or embed in BLAST
- `quantum-debugging` → keep as skill
- `skill-creator` → keep as skill (meta-skill)
- `troubleshooting-diagnostics` → keep as skill

Commit the mapping decisions to `_global_lessons/lessons.md`.

---

## Layer 5 — Skill Scanner Agent
> *The most complex item. Requires MCPs, agent architecture, and skills to already exist.*

### Step 12: Build the Skill Scanner Agent

**Depends on:** Steps 3 (GitHub MCP), 7 (AGENT_TEAM.md), 11 (skills baseline established)

**Purpose:** Scan your GitHub repos containing hundreds of skills, evaluate them against defined criteria, and install the best ones globally with user confirmation.

**Agent definition:** `~/AG_master_files/agents/core/skill-scanner.md`

**Evaluation criteria to define before building:**
- Relevance: Does this skill address a gap not covered by existing `_skills/`?
- Quality: Is the skill well-structured, with clear inputs/outputs and examples?
- Non-duplication: Is it meaningfully different from an existing skill?
- AG compatibility: Does it follow the format Gemini and Claude Code can consume?

**Workflow the agent follows:**
1. Connect to GitHub via GitHub MCP
2. List all skill files in target repos
3. Score each against evaluation criteria
4. Present ranked shortlist to user for approval
5. On "CONFIRM", install approved skills to `_skills/` (Destructive Gate applies — new installs are additive, but any overwrite requires confirmation)

**Build this using BLAST Framework** — do not write code until Blueprint is approved.

---

## Layer 6 — Alfred Migration
> *Once foundation is solid, Alfred moves in cleanly.*

### Step 13: Migrate Alfred into `projects/alfred/`

**Steps:**
```bash
# Copy Alfred's existing structure
cp -r [alfred-current-path] ~/AG_master_files/projects/alfred

# Clean up any non-WSL artifacts
find ~/AG_master_files/projects/alfred -name "*.Identifier" -delete
```

**Reconciliation checklist:**
- [ ] Alfred's `CLAUDE.md` aligned with GEMINI.md v2.1 rules
- [ ] Alfred's agent team reviewed against `_protocols/AGENT_TEAM.md` pattern
- [ ] Alfred's `agents/` folder structure matches the standard (Step 7)
- [ ] Alfred's Claude wrappers (`.claude/agents/`) are thin — YAML + pointer only
- [ ] Alfred's `CONTEXT.md` updated with current project state
- [ ] `lessons.md` reviewed — any global candidates? If yes, type "PROMOTE"

---

## Secondary MCPs (When Ready)

Once the primary stack is stable, add:

**NotebookLM MCP** — For long-context research synthesis across large document sets.

**Fireflies MCP** — Meeting transcription and action item extraction. Install when Alfred or another project needs meeting intelligence.

---

## Session Git Workflow (Every Session)

```bash
# Start of session:
cd ~/AG_master_files
git pull

# End of session:
git add .
git commit -m "Session: [description of what was done]"
git push
```

---

## Full Validation Checklist

Before declaring AG "Superpowered":

**Knowledge Foundation**
- [ ] Gemini API skill installed globally and verified

**MCPs**
- [ ] Context7 — live docs accessible
- [ ] GitHub — repo access verified
- [ ] Firecrawl — web scraping verified
- [ ] Notion — workspace read/write verified
- [ ] Supabase — database access verified

**Agent Architecture**
- [ ] `_protocols/AGENT_TEAM.md` created
- [ ] `GEMINI.md` updated to v2.1 with agent awareness section
- [ ] Root `CLAUDE.md` updated with Claude Code operating mode

**Skills**
- [ ] All 10 skills migrated from Windows to `_skills/`
- [ ] Skill-to-agent mapping completed and logged in `lessons.md`

**Advanced**
- [ ] Skill Scanner Agent built and tested
- [ ] Alfred migrated and reconciled

---

## What Comes After This

Once the foundation is declared complete:

1. **First real project** — Copy `_template/`, run BLAST Phase 1 (Blueprint)
2. **Promotion loop** — Review `lessons.md` files, promote global candidates to GEMINI.md v2.2
3. **Desktop replication** — When returning home, clone the repo and validate the full checklist on the new machine. New SSH key: `AG-Desktop-WSL2`

> The foundation is the leverage. Everything else multiplies on top of it.
