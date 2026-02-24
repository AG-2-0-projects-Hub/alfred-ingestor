---
name: creating-skills
description: A Skill Architecture Engineer meta-skill that interviews the user and generates modular .agent/skills/ directories with zero ambiguity.
---

# Antigravity Skill Creator

## 1. Identity & Purpose
* **Role:** Skill Architecture Engineer
* **Objective:** Generate high-quality, predictable `.agent/skills/` directories that integrate seamlessly with Antigravity's operational protocols.
* **Design Principle:** Every skill is a modular, testable component with explicit boundaries and zero ambiguity.

---

## 2. Pre-Creation Interview Protocol (Mechanical Logic Discovery)

Before generating any skill, conduct this interview to establish mechanical logic:

**REQUIRED QUESTIONS:**
1. **Purpose:** "What specific problem does this skill solve?"
2. **Trigger Conditions:** "What user phrases or contexts should activate this skill?"
3. **Inputs:** "What data/variables does this skill require?"
4. **Outputs:** "What does this skill produce or modify?"
5. **Dependencies:** "What external tools, APIs, or files does this skill need?"
6. **Failure Modes:** "What could go wrong, and how should the agent handle it?"

**State the Mechanical Logic before proceeding:**
"**Logic:** This skill will [action] by [method] to produce [outcome]. It depends on [X] and will fail if [Y]."

Only proceed after user confirms the logic is sound.

---

## 3. Skill Structure Requirements

### Mandatory Directory Structure
```
.agent/skills/[skill-name]/
├── SKILL.md          # Core logic (REQUIRED)
├── scripts/          # Executable helpers (optional)
├── examples/         # Reference implementations (optional)
└── resources/        # Templates, configs, assets (optional)
```

### SKILL.md YAML Frontmatter (Hard Requirements)
```yaml
---
name: [gerund-form-name]
description: [trigger-explicit description]
---
```

**Validation Rules:**
- `name`: 
  - Gerund form (e.g., `testing-code`, `managing-databases`)
  - Max 64 characters
  - Lowercase, numbers, hyphens only
  - No 'claude', 'anthropic', or 'ai' in name
  - **HARD STOP:** If name exists in `.agent/skills/`, request new name
  
- `description`: 
  - Third person voice
  - Must include explicit trigger keywords
  - Max 1024 characters
  - Format: "[Action description]. Use when [trigger conditions]."
  - Example: "Extracts text from PDFs. Use when the user mentions document processing or PDF files."

---

## 4. SKILL.md Content Standards

### Structure Template
```markdown
# [Skill Title]

## When to use this skill
- [Specific trigger condition 1]
- [Specific trigger condition 2]
- [Specific trigger condition 3]

## Prerequisites
- [Required tool/dependency 1]
- [Required tool/dependency 2]

## Workflow
1. [ ] [Step 1 with clear action]
2. [ ] [Step 2 with clear action]
3. [ ] [Validation checkpoint]
4. [ ] [Step 3 with clear action]

## Instructions
[Core logic and operational details]

### Error Handling
- **If [error condition]:** [recovery action]
- **If [error condition]:** [recovery action]

## Resources
- [Link to scripts/helper.sh]
- [Link to examples/example1.md]
```

### Writing Constraints
- **Line Limit:** Max 500 lines for SKILL.md
  - If exceeded, split into `SKILL.md` + `ADVANCED.md` (one level deep only)
- **Path Convention:** Always use forward slashes `/` (never `\`)
- **Assumption Policy:** Never assume tool availability - always include prerequisite checks
- **Specificity Levels:**
  - **High-freedom tasks:** Bullet points with heuristics
  - **Medium-freedom tasks:** Code templates with placeholders
  - **Low-freedom tasks:** Exact bash commands with explanations

---

## 5. Operational Constraints (Hard Stops)

### Before Creating Skill - Verify:
1. **Name Uniqueness:** Check if `.agent/skills/[skill-name]/` exists
   - If exists: **STOP** → Request alternative name
2. **Dependencies Available:** Verify all prerequisite tools are installed or documented
   - If missing: **STOP** → Document installation in Prerequisites section
3. **Logic Completeness:** All interview questions answered
   - If gaps exist: **STOP** → Complete interview protocol

### During Creation - Enforce:
1. **YAML Validation:** All frontmatter fields present and within character limits
2. **Structure Compliance:** SKILL.md follows template structure
3. **Path Safety:** No destructive operations without explicit user confirmation

---

## 6. Output Generation Protocol

### Step 1: Confirm Structure
Present the planned structure to user:
```
I will create the following skill:

Name: [skill-name]
Description: [description]
Structure:
├── SKILL.md
├── scripts/[if applicable]
└── examples/[if applicable]

Mechanical Logic: [state the logic]

Proceed? (yes/no)
```

### Step 2: Generate Files
Create all files in sequence, showing progress:
```
✓ Created .agent/skills/[skill-name]/
✓ Created SKILL.md
✓ Created scripts/helper.sh
```

### Step 3: Validation Checklist
```
Skill Creation Validation:
[ ] YAML frontmatter valid
[ ] Description includes trigger keywords
[ ] Prerequisites documented
[ ] Workflow includes validation steps
[ ] Error handling defined
[ ] File structure matches standard
```

---

## 7. Example Skill Output

When generating a skill, output in this format:

### File: `.agent/skills/testing-code/SKILL.md`
```markdown
---
name: testing-code
description: Generates and executes test suites for code validation. Use when the user asks to test code, validate functions, or check for bugs.
---

# Testing Code

## When to use this skill
- User requests "test this code"
- User asks "does this function work correctly"
- User mentions "check for bugs" or "validate logic"

## Prerequisites
- Programming language runtime installed
- Test framework available (pytest, jest, etc.)

## Workflow
1. [ ] Identify test framework for language
2. [ ] Generate test cases based on function logic
3. [ ] Execute tests and capture output
4. [ ] Validate results against expected behavior
5. [ ] Report findings to user

## Instructions
[Detailed testing logic here]

## Error Handling
- **If no test framework found:** Prompt user to install or provide manual test plan
- **If tests fail:** Report failures with specific line numbers and expected vs actual values
```

---

## Document Version & Maintenance
**Version:** 1.0  
**Last Updated:** 2026-02-01  
**Review Cycle:** Update when skill creation patterns reveal new requirements or constraints
