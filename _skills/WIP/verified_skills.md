# Verified Skills

**Source:** Merged from `suggested-skills-for-Ingestor-and-or-Alfred.md` + `Skill_audit_results.md` + trusted-repo scan (anthropics/skills, obra/superpowers, VoltAgent/awesome-agent-skills)
**Audit date:** 2026-04-22
**Scan date:** 2026-04-22

**Legend:**
- 🔵 Trusted — from a verified trusted repo (anthropics/skills, obra/superpowers, VoltAgent/awesome-agent-skills) — no audit required
- ✅ Ready to install — passed all 6 audit checks
- ⚠️ Conditional — passed with warnings; requires user approval before install (see note in table)
- FAILed skills removed to [Removed Skills](#removed-skills) section

**Coverage status:**
- D1 AI Orchestration: 4 ✅ | D2 Backend: 1 ⚠️ gap | D3 Frontend: 4 ✅ | D4 Security: 5 ✅
- D5 DevOps: 6 ✅ | D6 Data & ML: 2 ⚠️ gap | D7 GTM: 4 ✅ | D8 Quality: 7 ✅

---

## Domain 1: AI Orchestration
*Focus: multi-agent, RAG, LLM chaining, knowledge distillation*

| # | Skill | Repo | Score | Why it's relevant | Status |
|---|---|---|---|---|---|
| 1 | `subagent-driven-development` | `obra/superpowers` | 12/12 | Enables Claude to orchestrate implementer and reviewer subagents for multi-agent execution. | 🔵 Trusted |
| 2 | `claude-api` | `anthropics/skills` | 11/12 | Deep guidance on Anthropic's Managed Agents, prompt caching, and Claude implementations. | 🔵 Trusted |
| 3 | `dispatching-parallel-agents` | `obra/superpowers` | 11/12 | Outlines how to execute independent tasks simultaneously across isolated agents. | 🔵 Trusted |
| 4 | `mcp-builder` | `anthropics/skills` | 11/12 | Blueprint for building custom MCP servers to bridge LLM workflows with backend services. | 🔵 Trusted |

---

## Domain 2: Backend
*Focus: Node.js, FastAPI, REST, WebSocket, Supabase*

> ⚠️ **Gap:** Trusted repos (anthropics/skills, obra/superpowers, VoltAgent/awesome-agent-skills) contain no skills covering Node.js/Express, Supabase JS SDK, BullMQ/Redis, or Telegram webhook patterns. Only 1 of 4 minimum reached. Next audit round should target a Node.js or Supabase community skills repo.

| # | Skill | Repo | Score | Why it's relevant | Status |
|---|---|---|---|---|---|
| 1 | `fastapi-router-py` | `microsoft/skills` | 11/12 | Covers FastAPI routers with CRUD and Auth, explicitly needed for Alfred's Python Ingestor backend (the-ingestor uses FastAPI + uvicorn). | ✅ Ready to install |

---

## Domain 3: Frontend
*Focus: Flutter, React, UI/UX, design systems, accessibility*

| # | Skill | Repo | Score | Why it's relevant | Status |
|---|---|---|---|---|---|
| 1 | `flutter-architecting-apps` | `flutter/skills` | 12/12 | Essential for structuring Alfred's native Flutter host dashboard cleanly across Web, iOS, and Android. | ✅ Ready to install |
| 2 | `flutter-managing-state` | `flutter/skills` | 12/12 | Critical for cross-platform state — real-time escalation alerts, Supabase Realtime subscriptions, and AI stream data all flow through Flutter state. | ✅ Ready to install |
| 3 | `flutter-testing-apps` | `flutter/skills` | 10/12 | Ensures reliability for the Flutter host dashboard across all platforms before test user rollout. | ✅ Ready to install |
| 4 | `frontend-design` | `anthropics/skills` | 8/12 | Web UI design patterns and component hierarchy applicable to Alfred's Next.js Guest Web App and Admin Dashboard — real-time chat UI, escalation dashboards, and mobile-first layout. | 🔵 Trusted |

---

## Domain 4: Security & Privacy
*Focus: auth, RLS, encryption, GDPR, API key management, data leak prevention*

| # | Skill | Repo | Score | Why it's relevant | Status |
|---|---|---|---|---|---|
| 1 | `insecure-defaults` | `trailofbits/skills` | 12/12 | Critical for detecting accidental API key leaks or bad default security configs across Alfred's many secrets (Supabase, Gemini, Pinecone, Telegram, Apify). | ✅ Ready to install |
| 2 | `security-best-practices` | `openai/skills` | 11/12 | Provides broad, enterprise-grade logic for language-specific security handling in Alfred's TypeScript and Python services. | ✅ Ready to install |
| 3 | `security-threat-model` | `openai/skills` | 11/12 | Generates a project-specific threat model identifying SaaS trust boundaries — essential for Alfred's multi-tenant host/guest architecture. | ✅ Ready to install |
| 4 | `static-analysis` | `trailofbits/skills` | 10/12 | Advanced continuous security analysis via CodeQL/Semgrep methodologies. | ⚠️ Conditional — non-standard nested multi-skill bundle (CodeQL, Semgrep, SARIF); review all three sub-skill SKILL.md files individually before installing |
| 5 | `firebase-security-rules-auditor` | `firebase/agent-skills`¹ | 9/12 | Proxy knowledge for auditing Supabase RLS policies — Alfred's multi-tenant data isolation relies entirely on correct RLS across 7 tables. | ✅ Ready to install |

¹ Listed as `firebase/skills` in suggested list; actual installable repo is `firebase/agent-skills`.

---

## Domain 5: DevOps & Infra
*Focus: CI/CD, Render deployment, env management, monitoring*

| # | Skill | Repo | Score | Why it's relevant | Status |
|---|---|---|---|---|---|
| 1 | `render-deploy` | `openai/skills` | 12/12 | Exact match — Alfred's Node.js backend is deployed on Render; covers service configuration, health checks, and zero-downtime deploys. | ⚠️ Conditional — Render dashboard URLs in instruction body outside Resources/Prerequisites; RENDER_API_KEY uses export syntax outside formal Prerequisites header; confirm secrets management policy before installing |
| 2 | `gh-fix-ci` | `openai/skills` | 11/12 | Debug and fix failing GitHub Actions PR checks across Alfred's multi-service CI pipelines. | ✅ Ready to install |
| 3 | `using-git-worktrees` | `obra/superpowers` | 9/12 | Alfred is a 4-service system (alfred-backend, alfred-web, Flutter app, the-ingestor) — worktrees enable parallel development across phases without branch-switching churn. | 🔵 Trusted |
| 4 | `finishing-a-development-branch` | `obra/superpowers` | 9/12 | Alfred's 7-phase build has discrete deliverables with strict test criteria per phase — this skill enforces a structured merge/PR gate that prevents half-baked phases from landing. | 🔵 Trusted |
| 5 | `writing-plans` | `obra/superpowers` | 8/12 | Alfred's phased build (7 phases, each blocking the next) requires detailed implementation plans with explicit dependency tracking before each phase begins. | 🔵 Trusted |
| 6 | `executing-plans` | `obra/superpowers` | 8/12 | Batch execution with checkpoints maps directly to Alfred's build phases — each has discrete test criteria that must pass before the next unlocks. | 🔵 Trusted |

---

## Domain 6: Data & ML
*Focus: vector DBs, schema design, training pipelines, embeddings*

> ⚠️ **Gap:** Trusted repos contain no skills covering Pinecone, RAG pipelines, or vector embeddings. Only 2 of 4 minimum reached. Next audit round should target a Pinecone-specific or vector search skills repo.

| # | Skill | Repo | Score | Why it's relevant | Status |
|---|---|---|---|---|---|
| 1 | `azure-search-documents-py` | `microsoft/skills` | 11/12 | Vector search paradigms (indexing, querying, metadata filtering) that map directly to Alfred's Pinecone RAG operations for the Master JSON chunk retrieval. | ⚠️ Conditional — os.environ credential references (AZURE_SEARCH_API_KEY, AZURE_SEARCH_ENDPOINT) in SDK usage examples; instructional context, but confirm acceptable in your environment |
| 2 | `jupyter-notebook` | `openai/skills` | 9/12 | Rapid testing environment for Alfred's embedding pipeline experiments — validating Pinecone topK results, Gemini embedding dimensions (768), and RAG retrieval quality. | ✅ Ready to install |

---

## Domain 7: GTM & Marketing
*Focus: landing pages, social media, funnels, content strategy*

| # | Skill | Repo | Score | Why it's relevant | Status |
|---|---|---|---|---|---|
| 1 | `page-cro` | `coreyhaines31/marketingskills` | 12/12 | Conversion Rate Optimization for Alfred's SaaS landing page targeting Airbnb hosts. | ✅ Ready to install |
| 2 | `content-strategy` | `coreyhaines31/marketingskills` | 11/12 | Outlines how to position the short-term rental AI value proposition for host acquisition. | ✅ Ready to install |
| 3 | `copywriting` | `coreyhaines31/marketingskills` | 11/12 | High-impact UI and marketing site copy — onboarding flows, magic link messages, escalation alerts. | ✅ Ready to install |
| 4 | `saas-revenue-growth-metrics` | `deanpeters/Product-Manager-Skills` | 11/12 | Crucial SaaS GTM metrics tracking (CAC, LTV, MRR/ARR) for Alfred's host subscription model. | ✅ Ready to install |

---

## Domain 8: Quality & Reliability
*Focus: QA testing, CI quality gates, RLS auditing, continuous improvement loops*

| # | Skill | Repo | Score | Why it's relevant | Status |
|---|---|---|---|---|---|
| 1 | `playwright` | `openai/skills` | 12/12 | Gold standard for E2E and visual regression testing of Alfred's guest chat workflows and admin dashboard. | ✅ Ready to install |
| 2 | `test-driven-development` | `obra/superpowers` | 11/12 | Alfred's spec already defines explicit test criteria per phase — TDD's RED-GREEN-REFACTOR maps directly onto implementing chat.service, escalation.service, vectorizer.service, and the learning loop with correctness guarantees before each phase ships. | 🔵 Trusted |
| 3 | `systematic-debugging` | `obra/superpowers` | 11/12 | Alfred runs against 4 external APIs in production (Gemini, Pinecone, Telegram, Supabase) — the 4-phase root cause process is essential when webhook failures, rate limits, or Pinecone timeout cascades occur; becomes critical at V2 scale with BullMQ workers. | 🔵 Trusted |
| 4 | `webapp-testing` | `anthropics/skills` | 9/12 | Alfred's Guest Web App (Next.js + Supabase Realtime) is the guest-facing product — magic link activation, real-time message delivery, expired booking handling, and media upload all need E2E coverage before test user rollout at 20-30 properties. | 🔵 Trusted |
| 5 | `verification-before-completion` | `obra/superpowers` | 9/12 | Alfred has multiple stateful operations with hard correctness requirements — vectorize must complete before marking 'Trained', knowledge insert before flagging is_learned=true, and The Lock must clear atomically on Kill Switch; this skill enforces validation before state transitions are declared done. | 🔵 Trusted |
| 6 | `property-based-testing` | `trailofbits/skills` | 10/12 | Heavy stress-testing for Alfred's backend APIs and booking logic — particularly the conflict detection, resolution, and vectorization pipeline. | ✅ Ready to install |
| 7 | `requesting-code-review` | `obra/superpowers` | 8/12 | Pre-review checklist before merging changes to Alfred's escalation service or learning loop — both mutate shared state across multiple RLS-protected tables and are difficult to roll back in production. | 🔵 Trusted |

---

## Removed Skills

Skills that failed audit — do not install.

| Domain | Skill | Repo | Fail Reason |
|---|---|---|---|
| AI Orchestration | ~~`gemini-api-dev`~~ | ~~`google-gemini/skills`~~ | Repo does not exist on GitHub (404) |
| Backend | ~~`postgres-best-practices`~~ | ~~`supabase/skills`~~ | Repo does not exist on GitHub (404) |
| Backend | ~~`next-best-practices`~~ | ~~`vercel-labs/skills`~~ | Skill directory not found in repo |
| Backend | ~~`auth0-express`~~ | ~~`auth0/skills`~~ | Repo does not exist on GitHub (404) |
| Backend | ~~`dd-apm`~~ | ~~`datadog-labs/skills`~~ | Repo does not exist on GitHub (404) |
| Frontend | ~~`react-best-practices`~~ | ~~`vercel-labs/skills`~~ | Skill directory not found in repo |
| Frontend | ~~`composition-patterns`~~ | ~~`vercel-labs/skills`~~ | Skill directory not found in repo |
| DevOps & Infra | ~~`sentry-workflow`~~ | ~~`getsentry/skills`~~ | Skill not found in getsentry/skills repo |
| DevOps & Infra | ~~`dd-pup`~~ | ~~`datadog-labs/skills`~~ | Repo does not exist on GitHub (404) |
| DevOps & Infra | ~~`expo-cicd-workflows`~~ | ~~`expo/skills`~~ | Live HTTP fetches to external URLs during execution |
| Data & ML | ~~`dd-llmo-eval-bootstrap`~~ | ~~`datadog-labs/skills`~~ | Repo does not exist on GitHub (404) |
| Data & ML | ~~`gemini-interactions-api`~~ | ~~`google-gemini/skills`~~ | Repo does not exist on GitHub (404) |
| Data & ML | ~~`hugging-face-datasets`~~ | ~~`huggingface/skills`~~ | Live curl calls to external API endpoints in Instructions body |
| GTM & Marketing | ~~`typefully`~~ | ~~`typefully/skills`~~ | Repo does not exist on GitHub (404) |
| Quality & Reliability | ~~`ui-test`~~ | ~~`browserbase/skills`~~ | BROWSERBASE_API_KEY credential reference in Instructions body |
| Quality & Reliability | ~~`sentry-fix-issues`~~ | ~~`getsentry/skills`~~ | Skill not found in getsentry/skills repo |
| Quality & Reliability | ~~`code-review`~~ | ~~`coderabbitai/skills`~~ | External HTTPS URLs (coderabbit.ai) in Instructions body outside Resources/Prerequisites |