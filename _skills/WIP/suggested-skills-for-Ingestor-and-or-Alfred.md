# Suggested Skills for Project Alfred

This document contains the top 5 highly-rated skills per domain tailored for Project Alfred's multi-agent AI concierge architecture.

## Domain 1: AI Orchestration
*Focus: multi-agent, RAG, LLM chaining, knowledge distillation*

| # | Skill | Repo | Score | Why it's relevant |
|---|---|---|---|---|
| 1 | `subagent-driven-development` | `obra/superpowers` | 12/12 | Enables Claude to orchestrate implementer and reviewer subagents for multi-agent execution. |
| 2 | `google-gemini/gemini-api-dev` | `google-gemini/skills` | 12/12 | Exact match for Alfred's orchestrator AI layer (Gemini); guides structured outputs and chaining. |
| 3 | `claude-api` | `anthropics/skills` | 11/12 | Deep guidance on Anthropic's Managed Agents, prompt caching, and Claude implementations. |
| 4 | `dispatching-parallel-agents` | `obra/superpowers` | 11/12 | Outlines how to execute independent tasks simultaneously across isolated agents. |
| 5 | `mcp-builder` | `anthropics/skills` | 11/12 | Blueprint for building custom MCP servers to bridge LLM workflows with backend services. |

## Domain 2: Backend
*Focus: Node.js, FastAPI, REST, WebSocket, Supabase*

| # | Skill | Repo | Score | Why it's relevant |
|---|---|---|---|---|
| 1 | `supabase/postgres-best-practices` | `supabase/skills` | 12/12 | Critical for Project Alfred's Supabase backend to ensure optimized Postgres usage. |
| 2 | `microsoft/fastapi-router-py` | `microsoft/skills` | 11/12 | Covers FastAPI routers with CRUD and Auth, explicitly needed for Alfred's Python backend pieces. |
| 3 | `vercel-labs/next-best-practices` | `vercel-labs/skills` | 11/12 | Essential for ensuring the backend/Node layer scales correctly if tied to Next.js API routes. |
| 4 | `auth0/auth0-express` | `auth0/skills` | 10/12 | Translates best-practice Node.js REST API authentication setups. |
| 5 | `datadog-labs/dd-apm` | `datadog-labs/skills` | 9/12 | Backend application performance monitoring (APM) for complex AI server responses. |

## Domain 3: Frontend
*Focus: Flutter, React, UI/UX, design systems, accessibility*

| # | Skill | Repo | Score | Why it's relevant |
|---|---|---|---|---|
| 1 | `flutter/flutter-architecting-apps` | `flutter/skills` | 12/12 | Essential for structuring Alfred's native Flutter interface cleanly. |
| 2 | `flutter/flutter-managing-state` | `flutter/skills` | 12/12 | Critical for cross-platform app state (handling AI stream data locally). |
| 3 | `vercel-labs/react-best-practices` | `vercel-labs/skills` | 11/12 | Covers React UI interactions for any web-based admin dashboards. |
| 4 | `vercel-labs/composition-patterns` | `vercel-labs/skills` | 11/12 | Strong foundation for building scalable, reusable UI components. |
| 5 | `flutter/flutter-testing-apps` | `flutter/skills` | 10/12 | Ensures reliability for the mobile/iOS/Android Flutter clients. |

## Domain 4: Security & Privacy
*Focus: auth, RLS, encryption, GDPR, API key management, data leak prevention*

| # | Skill | Repo | Score | Why it's relevant |
|---|---|---|---|---|
| 1 | `trailofbits/insecure-defaults` | `trailofbits/skills` | 12/12 | Critical for detecting accidental API key leaks or bad default security configs. |
| 2 | `openai/security-best-practices` | `openai/skills` | 11/12 | Provides broad, enterprise-grade logic for language-specific security handling. |
| 3 | `openai/security-threat-model` | `openai/skills` | 11/12 | Generates a project-specific threat model identifying SaaS trust boundaries. |
| 4 | `trailofbits/static-analysis` | `trailofbits/skills` | 10/12 | Advanced continuous security analysis via CodeQL/Semgrep methodologies. |
| 5 | `firebase/firebase-security-rules-auditor` | `firebase/skills` | 9/12 | Great proxy knowledge for conceptualizing NoSQL/Supabase RLS access auditing. |

## Domain 5: DevOps & Infra
*Focus: CI/CD, Render deployment, env management, monitoring*

| # | Skill | Repo | Score | Why it's relevant |
|---|---|---|---|---|
| 1 | `openai/render-deploy` | `openai/skills` | 12/12 | Exact match! Defines exactly how to deploy applications reliably to Render. |
| 2 | `openai/gh-fix-ci` | `openai/skills` | 11/12 | Debug and fix failing GitHub Actions PR checks for continuous deployments. |
| 3 | `getsentry/sentry-workflow` | `getsentry/skills` | 10/12 | End-to-end production monitoring and deployment tracing. |
| 4 | `datadog-labs/dd-pup` | `datadog-labs/skills` | 10/12 | DevOps infrastructure insight and robust log parsing. |
| 5 | `expo/expo-cicd-workflows` | `expo/skills` | 10/12 | Necessary if deploying the Flutter/Mobile side through managed workflows / CD. |

## Domain 6: Data & ML
*Focus: vector DBs, schema design, training pipelines, embeddings*

| # | Skill | Repo | Score | Why it's relevant |
|---|---|---|---|---|
| 1 | `datadog-labs/dd-llmo-eval-bootstrap` | `datadog-labs/skills` | 12/12 | Analyzes production LLM traces and sets up LLM observability routines. |
| 2 | `google-gemini/gemini-interactions-api` | `google-gemini/skills` | 11/12 | Advanced data pipelines for embedding and multi-modal models. |
| 3 | `microsoft/azure-search-documents-py` | `microsoft/skills` | 11/12 | Vector search paradigms that map directly to Pinecone RAG operations. |
| 4 | `huggingface/hugging-face-datasets` | `huggingface/skills` | 10/12 | Crucial for organizing conversational datasets or short-term rental data corpuses. |
| 5 | `openai/jupyter-notebook` | `openai/skills` | 9/12 | Rapid testing environment for embedding pipelines and RAG retrieval experiments. |

## Domain 7: GTM & Marketing
*Focus: landing pages, social media, funnels, content strategy*

| # | Skill | Repo | Score | Why it's relevant |
|---|---|---|---|---|
| 1 | `coreyhaines31/page-cro` | `coreyhaines31/marketingskills` | 12/12 | Conversion Rate Optimization for Alfred's SaaS landing page. |
| 2 | `coreyhaines31/content-strategy` | `coreyhaines31/marketingskills` | 11/12 | Outlines how to position the short-term rental AI value proposition. |
| 3 | `coreyhaines31/copywriting` | `coreyhaines31/marketingskills` | 11/12 | High-impact UI and marketing site copy generation. |
| 4 | `typefully/typefully` | `typefully/skills` | 10/12 | Handles programmatic social media announcements for the product. |
| 5 | `deanpeters/saas-revenue-growth-metrics` | `deanpeters/Product-Manager-Skills` | 11/12 | Crucial SaaS GTM metrics tracking (CAC, LTV, MRR/ARR). |

## Domain 8: Quality & Reliability
*Focus: QA testing, CI quality gates, RLS auditing, continuous improvement loops*

| # | Skill | Repo | Score | Why it's relevant |
|---|---|---|---|---|
| 1 | `openai/playwright` | `openai/skills` | 12/12 | Gold standard for E2E and visual regression testing of the concierge workflows. |
| 2 | `browserbase/ui-test` | `browserbase/skills` | 11/12 | Advanced adversarial UI testing via real browsers and git diffs. |
| 3 | `getsentry/sentry-fix-issues` | `getsentry/skills` | 11/12 | Deep RCA and continuous quality improvement loops for production crashes. |
| 4 | `coderabbitai/code-review` | `coderabbitai/skills` | 10/12 | Automated AI PR reviews to maintain strict CI quality gates. |
| 5 | `trailofbits/property-based-testing` | `trailofbits/skills` | 10/12 | Heavy stress-testing for Alfred's backend APIs and booking logic. |
