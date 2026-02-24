---
name: skill-scanner
description: Scans trusted repositories for relevant skills based on project domains 
             identified in BLAST Blueprint. Invoked at project kickoff, one domain 
             at a time.
---

# Skill Scanner

## When to Use
After BLAST Phase 1 (Blueprint) has identified the project's domains.
User invocation only — never run automatically.
Trigger phrase: "Run the Skill Scanner for this project."

## Prerequisites
- BLAST Phase 1 complete — domains listed in project CLAUDE.md or CONTEXT.md
- GitHub MCP active (26/26 tools)
- `_skills/_scanner/trusted-repos.md` accessible

## Process

### Step 1 — Load Context
Read the active project's CLAUDE.md or CONTEXT.md and extract the domain list
from the BLAST Blueprint section.

Confirm with the user:
> "I found these domains: [list]. I'll scan them one at a time.
> Which domain should we start with?"

Wait for user to select. Do not proceed until confirmed.

---

### Step 2 — Scan One Domain
For the selected domain:

1. Read `_skills/_scanner/trusted-repos.md` to get authorised repo list
2. Use GitHub MCP (`github/get_file_contents`, `github/list_directory`) to 
   browse each Primary Source repo
3. Identify skill candidates relevant to the domain
4. Score each candidate:

| Criterion | Question | Score |
|---|---|---|
| Relevance | Does it directly match this domain? | 0-3 |
| Quality | Clear instructions, examples, defined inputs/outputs? | 0-3 |
| Non-duplication | Meaningfully different from existing `_skills/`? | 0-3 |
| AG compatibility | SKILL.md format, no platform-specific assumptions? | 0-3 |

Maximum score: 12. Only surface candidates scoring 8+.

---

### Step 3 — Present Shortlist
Present maximum 5 candidates for the domain, ranked by score:

> **Domain: [name]**
> 
> | # | Skill | Repo | Score | Why it's relevant |
> |---|---|---|---|---|
> | 1 | skill-name | anthropics/skills | 11/12 | [one line reason] |
> | 2 | skill-name | obra/superpowers | 9/12 | [one line reason] |
>
> Type a number to install, SKIP to move to next domain, or DONE to finish.

Wait for user response. Do not install anything yet.

---

### Step 4 — Install on Confirmation
When user selects a number:

1. Show the Destructive Gate if a skill with the same name exists in `_skills/`:
   > "⚠️ `[skill-name]` already exists in `_skills/`. Overwrite? (yes/no)"
   
2. On confirmation, install:
```bash
   npx skills add [repo-url] --skill [skill-name]
```

3. Confirm installation and log to project `lessons.md`:
```markdown
   ## [Date] — Skill installed: [skill-name]
   **Source:** [repo-url]
   **Domain:** [domain]
   **Score:** [X/12]
   **Reason:** [why it was selected]
```

4. Return to Step 3 shortlist for remaining candidates in this domain.

---

### Step 5 — Next Domain
When user types SKIP or finishes with current domain:

> "Domain [name] complete. Remaining domains: [list].
> Which domain next, or type DONE to finish?"

Wait for user selection.

---

### Step 6 — Finish
When user types DONE:

> "Skill Scanner complete.
> Installed: [list of installed skills]
> Skipped domains: [list if any]
> 
> Next step: Skill-to-Agent mapping (AGENT_TEAM.md Section 9)"

---

## Hard Rules
- Never install from repos not in trusted-repos.md
- Never install without explicit user confirmation (number selection)
- Never overwrite existing skills without Destructive Gate confirmation
- Maximum 5 candidates per domain — quality over quantity
- If no candidates score 8+, report: "No strong matches found for [domain]. 
  Proceeding with existing skills or consider adding a repo to trusted-repos.md"
