---
name: troubleshooting-diagnostics
description: Systematic root cause analysis and error resolution using SRE principles. Use when debugging errors, investigating failures, fixing bugs, or when error messages, stack traces, or MISSING_DEPENDENCY flags appear.
dependencies:
  - error-handling-patterns
---

# Troubleshooting & Diagnostics

## When to Use This Skill

**Direct Triggers:**
- User says "fix this," "debug this error," "why is this failing?"
- User asks "what's wrong?" or "this isn't working"

**Contextual Triggers:**
- Stack trace appears in conversation
- HTTP 400/500 error codes detected
- `MISSING_DEPENDENCY` flag in terminal output
- System behavior doesn't match expected output
- Tests failing without clear cause

## Prerequisites

**Required Files:**
- `.agent/rules/tech-stack.md` - To verify fixes align with architecture
- `.agent/rules/global-rules.md` - For constraint verification
- `incident_log.md` (created automatically if missing)

**Required Access:**
- Terminal output and logs
- Project file system
- Environment variables (`.env` if exists)

## Workflow

### Phase 1: State Verification & Setup
1. [ ] Verify current working directory is project root
2. [ ] Check if `incident_log.md` exists
   - If missing: Create using `resources/incident_log_template.md`
3. [ ] Verify access to `.agent/rules/tech-stack.md`
4. [ ] Confirm error context is complete (not truncated)

### Phase 2: Error Capture & Classification
5. [ ] Extract complete error message and stack trace
6. [ ] Classify severity: Critical | High | Medium | Low
7. [ ] Identify affected component (database, API, frontend, etc.)
8. [ ] Check if this error has occurred before (search `incident_log.md`)

### Phase 3: Root Cause Analysis (RCA)
9. [ ] **MECHANICAL LOGIC CHECKPOINT:**
   - State: "This error occurs because [cause]"
   - Do NOT proceed with fixes until root cause is identified
10. [ ] Verify prerequisites from error-handling-patterns:
    - Are dependencies installed?
    - Are environment variables set?
    - Are file paths correct?
11. [ ] Check system state:
    - Review recent changes (git log if available)
    - Check for resource exhaustion (disk, memory)
    - Verify external service status

### Phase 4: Solution Design
12. [ ] Cross-reference `tech-stack.md` constraints
    - Does the fix align with architecture principles?
    - Does it introduce forbidden tools?
13. [ ] Design fix with graceful degradation in mind
14. [ ] **HARD STOP:** If fix requires destructive operations:
    - Generate Destructive Operation Review artifact
    - Wait for user confirmation

### Phase 5: Implementation & Verification
15. [ ] Apply fix (code changes, config updates, etc.)
16. [ ] Test the fix
17. [ ] Verify error no longer occurs
18. [ ] Document in `incident_log.md`

## Instructions

### Identity: Site Reliability Engineer (SRE)

You are not a "patcher" - you are a diagnostician. Your goal is:
1. **Understand** the root cause
2. **Fix** the immediate issue
3. **Prevent** recurrence

### Core Principles

**From error-handling-patterns:**
- **Fail Fast:** Validate prerequisites before attempting fixes
- **Graceful Degradation:** Prefer fallback solutions over hard failures
- **Preserve Context:** Always log full error details

**From Global Rules:**
- **Zero-Inference:** Never assume what caused the error
- **State Verification:** Confirm system state before applying changes
- **Mechanical Logic First:** Explain WHY before HOW

### Root Cause Analysis Protocol

**Ask These Questions:**
1. What is the error message telling us?
2. What was the system trying to do when it failed?
3. What prerequisite conditions were not met?
4. What changed recently that could cause this?
5. Is this a code bug, configuration issue, or environmental problem?

**Generate RCA Statement:**
````
Root Cause: [System component] failed because [specific condition].
This occurred when [trigger action] attempted to [operation] but [prerequisite] was not satisfied.
````

### Fix Validation Checklist

Before applying ANY fix:
````
[ ] Root cause identified (not guessed)
[ ] Fix aligns with tech-stack.md constraints
[ ] Fix doesn't introduce new dependencies without documentation
[ ] Fix includes error handling (doesn't just mask the problem)
[ ] Destructive operations (if any) have user confirmation
[ ] Fix has been tested (or test plan documented)
````

### Incident Log Entry Format

Use this format for every resolved incident:
````markdown
## Incident: [Brief Title]
**Date:** YYYY-MM-DD HH:MM:SS
**Severity:** [Critical | High | Medium | Low]
**Component:** [System component affected]

### Error Context
\`\`\`
[Complete error message and stack trace]
\`\`\`

### Root Cause Analysis
[Detailed explanation of why this occurred]

### Fix Applied
[What was changed and why]

**Files Modified:**
- `path/to/file` - [description]

### Verification
[How was the fix tested?]

### Prevention
[How to prevent this in the future]
- [ ] Documentation updated
- [ ] Tests added
- [ ] Architecture review needed

---
````

## Error Handling

### If Root Cause Cannot Be Determined
**STOP. Do not guess.**

Generate diagnostic artifact:
````markdown
# DIAGNOSTIC ASSISTANCE NEEDED

**Error:** [error message]
**Attempted Analysis:**
1. [What was checked]
2. [What was ruled out]

**Missing Information:**
- [What additional context is needed]

**Request:** [Specific information needed from user]
````

### If Fix Requires Destructive Operations

**Generate Destructive Operation Review:**
````markdown
# ⚠️ DESTRUCTIVE OPERATION REVIEW

**Operation:** [What will be deleted/modified]
**Impact:** [Systems/data affected]
**Reversibility:** [Can this be undone? How?]
**Backup Status:** [Verified? Where?]

**Command to Execute:**
\`\`\`bash
[exact command]
\`\`\`

**Type 'CONFIRM' to proceed, or 'CANCEL' to abort**
````

Wait for explicit user confirmation before proceeding.

### If Fix Violates Tech Stack

**STOP and report:**
````
TECH STACK VIOLATION DETECTED

Proposed fix: [description]
Violation: [what constraint is violated]
Reference: tech-stack.md Section [X]

Alternative approaches:
A) [Compliant solution 1]
B) [Compliant solution 2]
C) Request tech-stack.md update to allow this approach

Which should I proceed with?
````

## Resources

- [Error Handling Patterns](../error-handling-patterns/SKILL.md) - Prerequisite checks and graceful degradation
- `resources/incident_log_template.md` - Template for new incident entries
- `scripts/log-analyzer.sh` - Parse incident_log.md for patterns
- `scripts/dependency-checker.sh` - Verify all prerequisites before fixes

## Example Usage

**Scenario:** User reports "Database connection failed"

**Skill Execution:**
1. ✓ Verify `incident_log.md` exists
2. ✓ Extract error: `Error: connect ECONNREFUSED 127.0.0.1:5432`
3. ✓ RCA: "PostgreSQL is not running on localhost:5432"
4. ✓ Check tech-stack.md: Uses Supabase (remote), not localhost
5. ✓ Root Cause: `.env` file has incorrect `DATABASE_URL`
6. ✓ Fix: Update `.env` to use Supabase connection string
7. ✓ Test: Connection successful
8. ✓ Log to `incident_log.md`
9. ✓ Prevention: Add `.env.example` with correct format

---

**Version:** 1.0  
**Last Updated:** 2026-02-01
