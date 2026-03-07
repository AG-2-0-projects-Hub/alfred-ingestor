# AG_SYSTEM_MAP.md
**Version:** 1.1 | **Created:** 2026-03-01 | **Updated:** 2026-03-04 | **Status:** Current state — post-AG-Improvement-Roadmap-v1.1

> **Purpose:** Context dump for broken or fresh AG sessions. Contains the full architecture, config, paths, and logic of the AG environment as of AG Improvement Roadmap v1.1 completion. Drop this into any session that has lost context.
>
> **Storage:** `~/AG_master_files/_global_lessons/AG_SYSTEM_MAP.md` — load only when context is lost or architecture is unclear. Not loaded in normal sessions.
>
> **Governing document:** `GEMINI.md` v3.2 is the law. This document describes; GEMINI.md prescribes.

---

## 1. System Identity

| Item | Value |
|---|---|
| Machine name | `Santohub` |
| OS | Windows 11 |
| Runtime | WSL2 — Ubuntu 24.04.1 LTS |
| WSL2 username | `santoskoy` |
| GitHub user | `Santo-Sanson` |
| GitHub email | `sans.lighthouse@gmail.com` |
| Git display name | `Alonso` |
| GitHub repo | `github.com/Santo-Sanson/AG_master_files` (Private, SSH) |
| IDE | Antigravity (AG) — Google DeepMind agent-first IDE, free public preview |
| Primary model | Gemini 3 Pro (AG native) |
| Secondary model | Claude Code (extension inside AG) |

---

## 2. Installed Tool Stack (WSL2)

| Tool | Version | Install Method |
|---|---|---|
| Git | 2.43.0 | apt |
| Node.js | v24.13.1 | nvm |
| npm | 11.10.0 | bundled with Node |
| Python | 3.12.0 | pyenv |
| Claude Code CLI | 2.1.47 | npm -g |
| Dart SDK | stable | apt (dart.dev repo) |

### Critical: nvm Symlinks (Non-Interactive Shell Access)

nvm initializes via `.bashrc` — only loads in interactive shells. AG's MCP manager and background processes spawn non-interactive shells and cannot see nvm-managed tools without these symlinks. **Run after any Node.js update:**

```bash
# Use 'which node' (not 'nvm which current') — 'current' alias may not be set
sudo ln -sf $(which node) /usr/local/bin/node
sudo ln -sf $(which npm) /usr/local/bin/npm
sudo ln -sf $(which npx) /usr/local/bin/npx
sudo ln -sf $(which claude) /usr/local/bin/claude
sudo ln -sf /usr/lib/dart/bin/dart /usr/local/bin/dart

# If 'which node' fails, first activate the version:
nvm use node || nvm install node

# Verify all five work in non-interactive context:
bash -c "node --version && npm --version && npx --version && claude --version && dart --version"
```

Note: Do not add symlinks for MCP-specific tools like `vercel` or `flutter` here. They should be handled via absolute paths in `mcp_config.json`.

### python vs python3
Both point to Python 3.12. `python` command created via symlink — both work identically.

---

## 3. File System Architecture

**WSL2 root:** `~/AG_master_files/`
**Windows access path:** `\\wsl.localhost\Ubuntu-24.04\home\santoskoy\AG_master_files`

```
~/AG_master_files/
├── GEMINI.md                              # The Constitution — v3.2 — global law for all sessions
├── CLAUDE.md                              # Claude Code operating rules — extends GEMINI.md
├── AGENTS.md                              # Agent Manager path resolution anchor

├── .gitignore                             # Excludes secrets, mcp_config.json, deps, Zone.Identifier files
│
├── _protocols/
│   ├── BLAST_Framework.md                 # Workflow protocol — used at project kickoff (Phase 1: Blueprint)
│   ├── AGENT_TEAM.md                      # Agent architecture decision guide + Manual Handoff Ritual
│   └── PROJECT_KICKOFF.md                 # 6-step deterministic workflow protocol — mandatory for new projects
│
├── _skills/                               # Global skill library — single source of truth for both models
│   ├── _scanner/
│   │   └── trusted-repos.md               # Authorized repos for Skill Scanner installs
│   ├── creating-skills/SKILL.md           # Meta-skill: interviews user and generates new SKILL.md files
│   ├── error-handling-patterns/SKILL.md   # Error handling patterns for implementation tasks
│   ├── find-skills/SKILL.md               # Meta-skill: skill discovery via npx skills CLI
│   ├── gemini-api-dev/SKILL.md            # Current Gemini SDK syntax — prevents deprecated code
│   ├── mcp-tool-manager/SKILL.md          # Dynamically enable/disable MCP tools in project profiles
│   ├── planning/SKILL.md                  # Roadmap and task decomposition
│   ├── skill-scanner/SKILL.md             # Scans trusted repos for skills matching project domains
│   ├── troubleshooting-diagnostics/SKILL.md # SRE-style root cause analysis
│   └── wsl-mcp-config/SKILL.md            # Enforces correct MCP config patterns for Windows+WSL2+AG
│
├── _scripts/
│   └── new-project.sh                     # Project creation automation — single source of truth
│
├── _mcp_profiles/                         # Per-project scoped MCP lists (no keys, committed to git)
│   ├── global.json                        # Steady state master (all tools disabled) — gitignored
│   └── [project].json                     # Named profiles with explicit tool allowlists
│
├── _global_lessons/
│   ├── lessons.md                         # Promoted cross-project technical knowledge
│   └── AG_SYSTEM_MAP.md                   # This file — load only when context is lost
│
└── projects/
    ├── _template/                         # Reusable scaffold — copy this for every new project
    │   ├── CLAUDE.md                      # Project law template
    │   ├── CONTEXT.md                     # Session state template
    │   └── lessons.md                     # Project lessons template
    ├── alfred/                            # Pending migration — own workspace, own document set
    └── claude-delegation-test/            # Verification project — tests new v1.1 scaffold infrastructure
        ├── CLAUDE.md
        ├── CONTEXT.md
        ├── lessons.md
        ├── .vscode/tasks.json             # Auto-fires ag-switch.sh on VS Code folder open
        ├── _mcp/project_mcps.md           # Human-readable MCP list for this project
        └── src/                           # Source code root
```

---

## 4. The Constitution Layer (GEMINI.md v3.2)

**What it governs:** All AG sessions, all projects, all agents. Project-level `CLAUDE.md` files may override specific rules locally but may never contradict safety or destructive operation protocols.

**Key behavioral rules in force:**

| Rule | Summary |
|---|---|
| Mechanical Logic First | State the structural why before any implementation |
| Zero-Inference | Never assume facts not explicitly provided — flag as `MISSING_DEPENDENCY` and halt |
| Plan Mode | For file architecture, DB schema, or API contract changes — propose first, wait for "PROCEED" |
| Destructive Gate | No `rm -rf`, `DROP TABLE`, `DELETE FROM` without a review artifact + explicit "CONFIRM" |
| Scope | Work inside active project only — never write to global directories unless explicitly instructed |
| Skills First | Scan `_skills/` before any task — read matching `SKILL.md` and follow it |
| Answer First | Do not execute unrequested actions — propose, wait for confirmation |
| Workspace Boundary | AG never touches anything outside `~/AG_master_files/` — system-wide changes flagged to user, never executed autonomously |

**Promotion hierarchy (lessons):**

| Flag | Destination | For |
|---|---|---|
| `PROMOTE` | `_global_lessons/lessons.md` | Technical knowledge, environment gotchas, setup notes |
| `PROMOTE TO CONSTITUTION` | `GEMINI.md` | Behavioral laws, hard stops, operational principles only |
| *(no flag)* | `projects/[project]/lessons.md` | Project-specific discoveries — stay local |

---

## 5. Claude Code Operating Rules (CLAUDE.md)

**Role:** Micro-orchestrator and implementer. Receives delegated tasks from Gemini, executes them, may spawn subagents internally via Task tool.

| Rule | Value |
|---|---|
| Max delegation depth | 2 levels — Core Agent → Specialist only. Specialists never delegate further |
| Escalate to Gemini for | Architectural decisions, cross-project changes, new infrastructure |
| Mid-task escalation | Never route back to Gemini mid-task — surface as `MISSING_DEPENDENCY` and halt |
| On-demand subagents | No persona files needed — spawn inline via Task tool |
| Context degradation | Use `/compact` proactively — context degrades after ~30–40 interactions |
| Session start | Read active project's `CLAUDE.md` and `CONTEXT.md` before doing anything |
| Session end | Update `CONTEXT.md` with: accomplished, pending, unresolved decisions |

**Shared resources (never duplicate):**

| Resource | Path |
|---|---|
| Skills | `_skills/` |
| Global Lessons | `_global_lessons/lessons.md` |
| Protocols | `_protocols/` |

---

## 6. Skills Library

**Rule:** Before starting any task, scan `_skills/` for a matching skill. If found, read its `SKILL.md` and follow it. Skills override default behavior for their domain.

| Skill | Purpose | Maintenance |
|---|---|---|
| `creating-skills` | Interviews user and generates new `SKILL.md` files with zero ambiguity | Hand-crafted |
| `error-handling-patterns` | Error handling patterns for implementation tasks | Hand-crafted |
| `find-skills` | Skill discovery via `npx skills` CLI | Hand-crafted |
| `gemini-api-dev` | Current Gemini SDK syntax — prevents deprecated `google.generativeai` code | CLI-managed — update monthly |
| `mcp-tool-manager` | Dynamically enable/disable MCP tools in `_mcp_profiles/[project].json` | Hand-crafted |
| `planning` | Roadmap and task decomposition | Hand-crafted |
| `skill-scanner` | Scans trusted repos for skills matching project domains (see Section 8) | Hand-crafted |
| `troubleshooting-diagnostics` | SRE-style root cause analysis | Hand-crafted |
| `wsl-mcp-config` | Enforces correct MCP config patterns for Windows 11 + WSL2 + AG | Hand-crafted — update if MCP architecture changes |

**Maintenance paths:**
- **CLI-managed** (installed via `npx skills add`): run `npx skills check` to see what needs updating, `npx skills update` to apply. Run `npx skills list` to confirm source repo.
- **Hand-crafted** (built locally): no CLI update path — review manually when domain changes or output goes stale.

---

## 7. MCP Architecture

### Core Constraint
AG's MCP manager runs on the **Windows host**, not WSL2. All `npx`-based MCPs must route through WSL. Any config using `"command": "npx"` must be rewritten to `"command": "wsl"`.

### Config File Location & Flow

| Context | Path |
|---|---|
| Windows | `C:\Users\San_8\.gemini\antigravity\mcp_config.json` |
| WSL2 | `/mnt/c/Users/San_8/.gemini/antigravity/mcp_config.json` |

1. **global.json**: Steady state master. All MCPs present, all tools disabled by default.
2. **mcp_config.json**: Live active config for AG. Resets from global.json on every run.
3. **[project].json**: Named profiles with explicit tool allowlists (no keys, committed to git).

**Security rule:** `mcp_config.json` is in `.gitignore` — never committed. Back up keys in a password manager. If a key is accidentally committed: rotate immediately, remove from git history.

**Config rule:** API keys go in `mcp_config.json` or `.env` only — never hardcoded in any file. Never place keys in the `"env": {}` block — env variables do not forward through the `wsl` command wrapper.

### Standard Config Patterns

```json
// MCPs WITHOUT API keys:
"mcp-name": {
  "command": "wsl",
  "args": ["npx", "-y", "@package/name"]
}

// MCPs WITH API keys — always inline via env command:
"mcp-name": {
  "command": "wsl",
  "args": ["env", "API_KEY=value", "npx", "-y", "@package/name"]
}
```

### Connected MCPs

| MCP | Status | Tools | Notes |
|---|---|---|---|
| Context7 | ✅ | 2/2 | Live library docs — prevents hallucinated API signatures |
| GitHub | ✅ | 26/26 | Repo access — required for Skill Scanner |
| Notion | ✅ | 22/22 | Knowledge base read/write |
| Firecrawl | ✅ | — | Web research — must use inline env pattern |
| Supabase (global) | ✅ | — | Full account access — for creating new projects |
| Supabase (per-project) | ✅ | — | Scoped to one `project_ref` — auto-registered by `new-project.sh` |
| Pinecone | ✅ | — | Vector DB — inline env key pattern |
| Flutter | ⚠️ | — | Dart team official MCP — `FLUTTER_ROOT` must be set in env |
| Vercel | ⚠️ | — | Remote MCP via `mcp-remote` to `https://mcp.vercel.com` — requires `VERCEL_AUTH_TOKEN` inline |

### Supabase Two-Level Architecture

```json
// Global entry — full account access:
"supabase": {
  "command": "wsl",
  "args": ["env", "SUPABASE_ACCESS_TOKEN=<token>",
           "npx", "-y", "@supabase/mcp-server-supabase@latest"]
}

// Per-project entry — scoped, auto-added by new-project.sh:
"supabase-[project]": {
  "command": "wsl",
  "args": ["env", "SUPABASE_ACCESS_TOKEN=<token>",
           "npx", "-y", "@supabase/mcp-server-supabase@latest",
           "--project-ref=[project_ref]"]
}
```

Each project's `CLAUDE.md` declares which MCP to use. Agents never touch the global entry when working inside a project. Token is the same across entries — it's an account credential, not a project secret.

**After any MCP change:** Restart AG. Confirm MCP appears in active tools list with correct tool count.

---

## 8. Orchestration Model

```
You
 └── Gemini 3 Pro (macro-orchestrator)
      └── Claude Code (micro-orchestrator + implementer)
           ├── Subagent A  ← Task tool, parallel
           ├── Subagent B  ← Task tool, parallel
           └── Subagent C  ← Task tool, parallel
```

**Gemini's logic:**
1. Classify task: one domain or multiple?
2. Single domain → delegate directly to Claude Code with clear instructions and success criteria
3. Multi-domain → consult `_protocols/AGENT_TEAM.md`, decompose, delegate with explicit task boundaries
4. Never implement directly — route everything

**Claude Code's logic:**
- Receives delegated tasks, executes them
- May spawn subagents internally via Task tool — user never manages subagents directly
- Max delegation depth: 2 levels — Core Agent → Specialist only

**Agent teams** (project-level): Only active if the current project has an `agents/` folder. When it does, read `agents/README.md` for the routing table before proceeding. Full protocol: `_protocols/AGENT_TEAM.md`.

**Agent Teams (Tier 3):** Experimental, ~5x token cost — deferred until stable.

---

## 9. Project Architecture

### Required Files (Every Project)

| File/Folder | Purpose |
|---|---|
| `CLAUDE.md` | Project law — inherits GEMINI.md, declares stack, schema, MCP name, any local overrides |
| `CONTEXT.md` | Session state — updated at end of every session (accomplished, pending, unresolved decisions) |
| `lessons.md` | Project-level discoveries — flag global candidates with `Global Candidate: Yes` |
| `.vscode/tasks.json` | Auto-fires `ag-switch.sh` on VS Code folder open — syncs MCP profile |
| `_mcp/project_mcps.md` | Human-readable list of MCPs active in this project |
| `src/` | Source code root |

### Creating a New Project

**Always use the script — never scaffold manually:**

```bash
bash ~/AG_master_files/_scripts/new-project.sh
```

**What the script does:**
1. **Preflight check:** Verifies `node`, `npm`, `npx`, and `claude` exist in `/usr/local/bin` — exits with error if missing
2. Prompts for project name (lowercase, no spaces) and whether Supabase is needed
3. Scaffolds from `_template/` with pre-filled `CLAUDE.md`, `CONTEXT.md`, `lessons.md`
4. Creates `.vscode/tasks.json` to auto-fire `ag-switch.sh` on folder open
5. Creates `_mcp/project_mcps.md` and `src/` directory
6. If Supabase: prompts for `project_ref`, inherits access token from global entry, registers scoped MCP in `mcp_config.json`
7. Generates `_mcp_profiles/[project].json` with selected MCPs
8. Commits and pushes to GitHub automatically

**After script:** Open project in VS Code — `tasks.json` will auto-fire `ag-switch.sh`. Click **Refresh** in the MCP panel. Then open Claude Code.

### Project Startup Sequence (After Script)

See `_protocols/PROJECT_KICKOFF.md` for the full mandatory 6-step sequence. Summary:
1. Open project folder in VS Code (→ `tasks.json` auto-fires `ag-switch.sh`)
2. Click **Refresh** in the MCP panel — BEFORE opening Claude Code
3. Run BLAST Phase 1 (Blueprint) — define stack, schema, domains
4. Invoke Skill Scanner: *"Run the Skill Scanner for this project"*
5. Do Skill-to-Agent mapping (`_protocols/AGENT_TEAM.md` Section 9)
6. Begin implementation via the Manual Handoff Ritual

### Skill Scanner (Project Kickoff Tool)

**Location:** `_skills/skill-scanner/SKILL.md`
**Trigger:** Manual — after BLAST Phase 1 identifies project domains. Phrase: *"Run the Skill Scanner for this project."*

**Flow:**
1. Reads domains from Blueprint → confirms with user which domain to start
2. Reads `_skills/_scanner/trusted-repos.md` for authorized repo list
3. Searches repos via GitHub MCP — scores candidates on: Relevance, Quality, Non-duplication, AG compatibility (max 12 pts)
4. Surfaces only candidates scoring 8+ — max 5 per domain
5. User selects by number → Destructive Gate if name collision → installs via `npx skills add`
6. Logs install to project `lessons.md`
7. Repeats per domain until user types DONE

**Trusted repos (Primary Sources — install authorized):**

| Repo | Trust |
|---|---|
| `anthropics/skills` | ⭐ Official |
| `obra/superpowers` | ⭐ Proven |
| `VoltAgent/awesome-agent-skills` | ✅ Verified |

**Discovery index (browse only — do not install directly):** `travisvn/awesome-claude-skills`

---

## 10. Projects Registry

| Project | Status | Notes |
|---|---|---|
| `_template` | ✅ Active scaffold | Copy this for every new project — never modify directly |
| `alfred` | ⬜ Pending migration | Own workspace, own document set — dedicated session required |
| `scraper` | ✅ Active | Airbnb scraper project — Python backend, Flutter frontend |
| `claude-delegation-test` | ✅ Scaffold only | Verification project for AG Roadmap v1.1 — tests new infra, local only |

Alfred is treated as an independent project. Migration involves: copy into `projects/alfred/`, align its `CLAUDE.md` with current GEMINI.md rules, review agent team against `_protocols/AGENT_TEAM.md`, update `CONTEXT.md`, promote any global lessons candidates.

---

## 11. Known Issues & Permanent Fixes

| # | Symptom | Fix | Prevention |
|---|---|---|---|
| 1 | `node`, `npm`, `npx`, `claude` not found in AG's MCP manager or background processes | Create nvm symlinks to `/usr/local/bin/` (see Section 2) | Run all four symlinks immediately after any Node.js update |
| 2 | `nvm which current` returns `N/A` — symlinks step fails | Run `nvm use node` first to activate a version, then use `$(which node)` instead | Set a default: `nvm alias default node` after installing |
| 3 | Gemini generates deprecated Gemini API code despite skill installed | Skills Library directive in GEMINI.md — Gemini scans `_skills/` before any task | Any new capability governing Gemini must be declared in GEMINI.md explicitly |
| 4 | "cannot list directory" errors for Linux absolute paths and Windows drives | Known AG limitation — Gemini's filesystem tool probes multiple path formats before finding correct UNC path | Log and ignore — Gemini finds the workspace correctly every time. Not fixable via config |
| 5 | All npx-based MCPs fail: `npx: executable not found in %PATH%` | Route all npx commands through WSL: `"command": "wsl", "args": ["npx", "-y", "..."]` | Any MCP using Node tools must route through `wsl` command |
| 6 | Firecrawl: `FIRECRAWL_API_KEY must be provided` despite key in `env` block | Pass key inline: `"args": ["env", "FIRECRAWL_API_KEY=...", "npx", "-y", "firecrawl-mcp"]` | For WSL-routed MCPs, always use inline `env` in args — never the `env` block |
| 7 | Supabase MCP `type: http` config silently fails | AG uses `mcp_config.json` which only supports stdio servers — use npx + WSL routing + access token | Never use HTTP format for AG MCPs |
| 8 | `git revert HEAD` deleted a newly created file from filesystem | `git revert` undoes the entire commit including file creation — always run `git log --oneline` before reverting | Never use `git revert` to undo a file addition without checking commit scope first |
| 9 | `cat >>` appends to GEMINI.md produce broken markdown formatting | All GEMINI.md edits go through Gemini in the editor only | Never append to GEMINI.md via terminal |
| 10 | Gemini pre-fills `new-project.sh` prompts instead of asking interactively | Explicit rule in GEMINI.md Section 11 — never pre-fill script inputs | Script prompts must always be answered by user interactively |
| 11 | `*.Identifier` files cluttering workspace (Windows metadata on WSL2 drag-drop) | `find ~/AG_master_files -name "*.Identifier" -delete` — already blocked by `.gitignore` | Never apply system-wide registry changes — cosmetic issue, solve within AG |
| 12 | Agent Manager agents can't resolve WSL2 paths | `AGENTS.md` at workspace root with explicit absolute paths | Always maintain `AGENTS.md` at root |
| 13 | API keys exposed in `mcp_config.json` opened in editor | Rotate all exposed keys immediately | Never open `mcp_config.json` in the visible editor during a session or screenshare |
| 14 | Flutter MCP 404 — `@flutter/mcp` does not exist on npm | Flutter MCP is a Dart SDK command — use `"command": "wsl", "args": ["dart", "mcp-server"]` | Never search npm for Flutter/Dart MCP; check `docs.flutter.dev/ai/mcp-server` for the canonical config |
| 15 | Pinecone MCP 404 — `@mcp-pinecone/server` does not exist | Correct official package is `@pinecone-database/mcp` | Always verify npm package names against the official GitHub repo before adding to `mcp_config.json` |
| 16 | `dart mcp-server` not found in non-interactive shell despite `.bashrc` PATH | Create symlink: `sudo ln -sf /usr/lib/dart/bin/dart /usr/local/bin/dart` | Run dart symlink immediately after installing Dart SDK via apt |

---

## 12. Daily Workflows

### Every Session

```bash
# Start:
cd ~/AG_master_files && git pull

# End:
git add .
git commit -m "Session: [description of what was done]"
git push
```

### Starting a New Project

```bash
bash ~/AG_master_files/_scripts/new-project.sh
# → Script runs preflight, scaffolds project, generates MCP profile
# → Open project folder in VS Code
# → tasks.json auto-fires ag-switch.sh — click Refresh in MCP panel
# → THEN open Claude Code
# → Follow PROJECT_KICKOFF.md 6-step sequence
```

### Desktop Replication (When Ready)

1. Install WSL2 + Ubuntu (same as original setup)
2. Install all tools via nvm / pyenv (same steps)
3. Apply nvm symlinks fix immediately after Node install
4. Connect GitHub SSH key — name it `AG-Desktop-WSL2`
5. Clone repo:
```bash
git clone git@github.com:Santo-Sanson/AG_master_files.git ~/AG_master_files
```
6. Verify all tools return versions: `git`, `node`, `npm`, `python`, `claude`
7. Re-enter all API keys manually in AG's MCP settings panel — keys are never in the repo

---

## Document Maintenance

**Update this document when:**
- New MCPs are added or removed
- New skills are installed globally
- New projects are created or completed
- Known issues are resolved or discovered
- Tool versions are updated
- Architecture decisions change

**How to update:** Edit directly in AG via Gemini. Do not use terminal appends (`cat >>`). Bump the version number and update the date at the top. File lives at `_global_lessons/AG_SYSTEM_MAP.md`.
