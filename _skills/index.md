# Skills Index

A registry of all skills in `_skills/`. One entry per skill.

---

### skill-auditor
**Source:** hand-crafted
**Domains:** #security #quality
**What it does:** Security gate that audits skill candidates before install — checks for prompt injection, credential fishing, and scope creep
**Use when:** Any skill candidate comes from outside trusted-repos.md, or before installing any open-registry (skills.sh / npx) result
**Installed:** yes

### subagent-driven-development
**Source:** obra/superpowers
**Domains:** #ai-orchestration
**What it does:** Enables Claude to orchestrate implementer and reviewer subagents for multi-agent execution.
**Use when:** Whenever working on #ai-orchestration tasks related to subagent-driven-development best practices.
**Installed:** yes

### claude-api
**Source:** anthropics/skills
**Domains:** #ai-orchestration
**What it does:** Deep guidance on Anthropic's Managed Agents, prompt caching, and Claude implementations.
**Use when:** Whenever working on #ai-orchestration tasks related to claude-api best practices.
**Installed:** yes

### dispatching-parallel-agents
**Source:** obra/superpowers
**Domains:** #ai-orchestration
**What it does:** Outlines how to execute independent tasks simultaneously across isolated agents.
**Use when:** Whenever working on #ai-orchestration tasks related to dispatching-parallel-agents best practices.
**Installed:** yes

### mcp-builder
**Source:** anthropics/skills
**Domains:** #ai-orchestration
**What it does:** Blueprint for building custom MCP servers to bridge LLM workflows with backend services.
**Use when:** Whenever working on #ai-orchestration tasks related to mcp-builder best practices.
**Installed:** yes

### fastapi-router-py
**Source:** microsoft/skills
**Domains:** #backend
**What it does:** Covers FastAPI routers with CRUD and Auth, explicitly needed for Alfred's Python Ingestor backend.
**Use when:** Whenever working on #backend tasks related to fastapi-router-py best practices.
**Installed:** yes

### flutter-architecting-apps
**Source:** flutter/skills
**Domains:** #frontend
**What it does:** Essential for structuring Alfred's native Flutter host dashboard cleanly across Web, iOS, and Android.
**Use when:** Whenever working on #frontend tasks related to flutter-architecting-apps best practices.
**Installed:** yes

### flutter-managing-state
**Source:** flutter/skills
**Domains:** #frontend
**What it does:** Critical for cross-platform state.
**Use when:** Whenever working on #frontend tasks related to flutter-managing-state best practices.
**Installed:** yes

### flutter-testing-apps
**Source:** flutter/skills
**Domains:** #frontend
**What it does:** Ensures reliability for the Flutter host dashboard across all platforms before test user rollout.
**Use when:** Whenever working on #frontend tasks related to flutter-testing-apps best practices.
**Installed:** yes

### frontend-design
**Source:** anthropics/skills
**Domains:** #frontend
**What it does:** Web UI design patterns and component hierarchy applicable to Alfred's Next.js Guest Web App and Admin Dashboard.
**Use when:** Whenever working on #frontend tasks related to frontend-design best practices.
**Installed:** yes

### insecure-defaults
**Source:** trailofbits/skills
**Domains:** #security
**What it does:** Critical for detecting accidental API key leaks or bad default security configs.
**Use when:** Whenever working on #security tasks related to insecure-defaults best practices.
**Installed:** yes

### security-best-practices
**Source:** openai/skills
**Domains:** #security
**What it does:** Provides broad, enterprise-grade logic for language-specific security handling.
**Use when:** Whenever working on #security tasks related to security-best-practices best practices.
**Installed:** yes

### security-threat-model
**Source:** openai/skills
**Domains:** #security
**What it does:** Generates a project-specific threat model identifying SaaS trust boundaries.
**Use when:** Whenever working on #security tasks related to security-threat-model best practices.
**Installed:** yes

### firebase-security-rules-auditor
**Source:** firebase/agent-skills
**Domains:** #security
**What it does:** Proxy knowledge for auditing Supabase RLS policies.
**Use when:** Whenever working on #security tasks related to firebase-security-rules-auditor best practices.
**Installed:** yes

### gh-fix-ci
**Source:** openai/skills
**Domains:** #devops
**What it does:** Debug and fix failing GitHub Actions PR checks.
**Use when:** Whenever working on #devops tasks related to gh-fix-ci best practices.
**Installed:** yes

### using-git-worktrees
**Source:** obra/superpowers
**Domains:** #devops
**What it does:** worktrees enable parallel development across phases.
**Use when:** Whenever working on #devops tasks related to using-git-worktrees best practices.
**Installed:** yes

### finishing-a-development-branch
**Source:** obra/superpowers
**Domains:** #devops
**What it does:** enforces a structured merge/PR gate.
**Use when:** Whenever working on #devops tasks related to finishing-a-development-branch best practices.
**Installed:** yes

### writing-plans
**Source:** obra/superpowers
**Domains:** #devops
**What it does:** explicit dependency tracking before each phase begins.
**Use when:** Whenever working on #devops tasks related to writing-plans best practices.
**Installed:** yes

### executing-plans
**Source:** obra/superpowers
**Domains:** #devops
**What it does:** Batch execution with checkpoints maps directly to Alfred's build phases.
**Use when:** Whenever working on #devops tasks related to executing-plans best practices.
**Installed:** yes

### jupyter-notebook
**Source:** openai/skills
**Domains:** #data-ml
**What it does:** Rapid testing environment for Alfred's embedding pipeline experiments.
**Use when:** Whenever working on #data-ml tasks related to jupyter-notebook best practices.
**Installed:** yes

### page-cro
**Source:** coreyhaines31/marketingskills
**Domains:** #gtm
**What it does:** Conversion Rate Optimization for Alfred's SaaS landing page.
**Use when:** Whenever working on #gtm tasks related to page-cro best practices.
**Installed:** yes

### content-strategy
**Source:** coreyhaines31/marketingskills
**Domains:** #gtm
**What it does:** Outlines how to position the short-term rental AI value proposition.
**Use when:** Whenever working on #gtm tasks related to content-strategy best practices.
**Installed:** yes

### copywriting
**Source:** coreyhaines31/marketingskills
**Domains:** #gtm
**What it does:** High-impact UI and marketing site copy.
**Use when:** Whenever working on #gtm tasks related to copywriting best practices.
**Installed:** yes

### saas-revenue-growth-metrics
**Source:** deanpeters/Product-Manager-Skills
**Domains:** #gtm
**What it does:** Crucial SaaS GTM metrics tracking.
**Use when:** Whenever working on #gtm tasks related to saas-revenue-growth-metrics best practices.
**Installed:** yes

### playwright
**Source:** openai/skills
**Domains:** #quality
**What it does:** Gold standard for E2E and visual regression testing.
**Use when:** Whenever working on #quality tasks related to playwright best practices.
**Installed:** yes

### test-driven-development
**Source:** obra/superpowers
**Domains:** #quality
**What it does:** TDD's RED-GREEN-REFACTOR maps directly onto implementing core services.
**Use when:** Whenever working on #quality tasks related to test-driven-development best practices.
**Installed:** yes

### systematic-debugging
**Source:** obra/superpowers
**Domains:** #quality
**What it does:** essential when webhook failures, rate limits, or Pinecone timeout cascades occur.
**Use when:** Whenever working on #quality tasks related to systematic-debugging best practices.
**Installed:** yes

### webapp-testing
**Source:** anthropics/skills
**Domains:** #quality
**What it does:** magic link activation, real-time message delivery coverage.
**Use when:** Whenever working on #quality tasks related to webapp-testing best practices.
**Installed:** yes

### verification-before-completion
**Source:** obra/superpowers
**Domains:** #quality
**What it does:** enforces validation before state transitions are declared done.
**Use when:** Whenever working on #quality tasks related to verification-before-completion best practices.
**Installed:** yes

### property-based-testing
**Source:** trailofbits/skills
**Domains:** #quality
**What it does:** Heavy stress-testing for Alfred's backend APIs and booking logic.
**Use when:** Whenever working on #quality tasks related to property-based-testing best practices.
**Installed:** yes

### requesting-code-review
**Source:** obra/superpowers
**Domains:** #quality
**What it does:** Pre-review checklist before merging changes.
**Use when:** Whenever working on #quality tasks related to requesting-code-review best practices.
**Installed:** yes

