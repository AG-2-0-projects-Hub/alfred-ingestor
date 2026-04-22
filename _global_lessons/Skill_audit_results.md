# Skill Audit Results
**Purpose:** Log of all skill candidate audits run through skill-auditor.
**Format:** One entry per audit, chronological.

---

## Skill Audit: gemini-api-dev
**Source:** https://github.com/google-gemini/skills
**Date:** 2026-04-22

| # | Check | Result | Note |
|---|---|---|---|
| 1 | Repo exists | ❌ FAIL | github.com/google-gemini/skills returns HTTP 404 — repo does not exist |
| 2 | Active maintenance | N/A | Repo not found |
| 3 | No external calls | N/A | Repo not found |
| 4 | No credential fishing | N/A | Repo not found |
| 5 | No hidden instructions | N/A | Repo not found |
| 6 | Scope is bounded | N/A | Repo not found |

**Verdict: FAIL**
**Reason:** The repository google-gemini/skills does not exist on GitHub.
**Action:** Do not install — source repo is invalid.

---

## Skill Audit: gemini-interactions-api
**Source:** https://github.com/google-gemini/skills
**Date:** 2026-04-22

| # | Check | Result | Note |
|---|---|---|---|
| 1 | Repo exists | ❌ FAIL | github.com/google-gemini/skills returns HTTP 404 — repo does not exist |
| 2 | Active maintenance | N/A | Repo not found |
| 3 | No external calls | N/A | Repo not found |
| 4 | No credential fishing | N/A | Repo not found |
| 5 | No hidden instructions | N/A | Repo not found |
| 6 | Scope is bounded | N/A | Repo not found |

**Verdict: FAIL**
**Reason:** The repository google-gemini/skills does not exist on GitHub.
**Action:** Do not install — source repo is invalid.

---

## Skill Audit: postgres-best-practices
**Source:** https://github.com/supabase/skills
**Date:** 2026-04-22

| # | Check | Result | Note |
|---|---|---|---|
| 1 | Repo exists | ❌ FAIL | github.com/supabase/skills returns HTTP 404 — repo does not exist |
| 2 | Active maintenance | N/A | Repo not found |
| 3 | No external calls | N/A | Repo not found |
| 4 | No credential fishing | N/A | Repo not found |
| 5 | No hidden instructions | N/A | Repo not found |
| 6 | Scope is bounded | N/A | Repo not found |

**Verdict: FAIL**
**Reason:** The repository supabase/skills does not exist on GitHub.
**Action:** Do not install — source repo is invalid.

---

## Skill Audit: next-best-practices
**Source:** https://github.com/vercel-labs/skills
**Date:** 2026-04-22

| # | Check | Result | Note |
|---|---|---|---|
| 1 | Repo exists | ✅ PASS | github.com/vercel-labs/skills is a valid public repo (15.1k stars) |
| 2 | Active maintenance | ✅ PASS | pushed_at 2026-04-21, within 90-day window |
| 3 | No external calls | ❌ FAIL | HALT — Cannot read SKILL.md; skill directory `next-best-practices` does not exist in repo (only `find-skills` present) |
| 4 | No credential fishing | N/A | SKILL.md not found |
| 5 | No hidden instructions | N/A | SKILL.md not found |
| 6 | Scope is bounded | N/A | SKILL.md not found |

**Verdict: FAIL**
**Reason:** The skill `next-best-practices` does not exist in the vercel-labs/skills repository — SKILL.md cannot be located at any expected path.
**Action:** Do not install — skill artifact is missing from source repo.

---

## Skill Audit: react-best-practices
**Source:** https://github.com/vercel-labs/skills
**Date:** 2026-04-22

| # | Check | Result | Note |
|---|---|---|---|
| 1 | Repo exists | ✅ PASS | github.com/vercel-labs/skills is a valid public repo (15.1k stars) |
| 2 | Active maintenance | ✅ PASS | pushed_at 2026-04-21, within 90-day window |
| 3 | No external calls | ❌ FAIL | HALT — Cannot read SKILL.md; skill directory `react-best-practices` does not exist in repo |
| 4 | No credential fishing | N/A | SKILL.md not found |
| 5 | No hidden instructions | N/A | SKILL.md not found |
| 6 | Scope is bounded | N/A | SKILL.md not found |

**Verdict: FAIL**
**Reason:** The skill `react-best-practices` does not exist in the vercel-labs/skills repository — SKILL.md cannot be located at any expected path.
**Action:** Do not install — skill artifact is missing from source repo.

---

## Skill Audit: composition-patterns
**Source:** https://github.com/vercel-labs/skills
**Date:** 2026-04-22

| # | Check | Result | Note |
|---|---|---|---|
| 1 | Repo exists | ✅ PASS | github.com/vercel-labs/skills is a valid public repo (15.1k stars) |
| 2 | Active maintenance | ✅ PASS | pushed_at 2026-04-21, within 90-day window |
| 3 | No external calls | ❌ FAIL | HALT — Cannot read SKILL.md; skill directory `composition-patterns` does not exist in repo |
| 4 | No credential fishing | N/A | SKILL.md not found |
| 5 | No hidden instructions | N/A | SKILL.md not found |
| 6 | Scope is bounded | N/A | SKILL.md not found |

**Verdict: FAIL**
**Reason:** The skill `composition-patterns` does not exist in the vercel-labs/skills repository — SKILL.md cannot be located at any expected path.
**Action:** Do not install — skill artifact is missing from source repo.

---

## Skill Audit: fastapi-router-py
**Source:** https://github.com/microsoft/skills
**Date:** 2026-04-22

| # | Check | Result | Note |
|---|---|---|---|
| 1 | Repo exists | ✅ PASS | Public repo at microsoft/skills, 2.1k stars, 240 forks |
| 2 | Active maintenance | ✅ PASS | Repo pushed_at: 2026-04-22, well after 90-day cutoff |
| 3 | No external calls | ✅ PASS | No http/https calls, curl, fetch, axios, or webhook directives in instruction sections; HTTP status code constants are Python enum references in code examples, not network calls |
| 4 | No credential fishing | ✅ PASS | No API_KEY, TOKEN, SECRET, os.environ, or .env references anywhere |
| 5 | No hidden instructions | ✅ PASS | No override, disregard, ignore previous, or role-switching language found |
| 6 | Scope is bounded | ✅ PASS | Instructions stay within FastAPI router creation domain; no filesystem writes, agent spawning, or unexpected network calls |

**Verdict: PASS**
**Reason:** Clean, minimal skill scoped entirely to FastAPI router boilerplate with no external calls, credential access, or out-of-scope instructions.
**Action:** Install approved

---

## Skill Audit: azure-search-documents-py
**Source:** https://github.com/microsoft/skills
**Date:** 2026-04-22

| # | Check | Result | Note |
|---|---|---|---|
| 1 | Repo exists | ✅ PASS | Public repo at microsoft/skills, confirmed valid |
| 2 | Active maintenance | ✅ PASS | Repo pushed_at: 2026-04-22, well after 90-day cutoff |
| 3 | No external calls | ✅ PASS | `https://<service-name>.search.windows.net` is a placeholder template in a doc section, not a live call; no curl, fetch, axios, or webhook directives |
| 4 | No credential fishing | ⚠️ WARN | `os.environ["AZURE_SEARCH_API_KEY"]`, `os.environ["AZURE_SEARCH_ENDPOINT"]`, and `os.environ["AZURE_SEARCH_INDEX_NAME"]` appear in Python code examples demonstrating SDK authentication patterns; context is instructional (showing how to wire up the SDK), not exfiltration; key is also explicitly flagged as not recommended for production |
| 5 | No hidden instructions | ✅ PASS | No override, disregard, ignore previous, or role-switching language found |
| 6 | Scope is bounded | ✅ PASS | Instructions stay within Azure AI Search SDK usage; no unexpected filesystem writes, agent spawning, or global config reads |

**Verdict: CONDITIONAL**
**Reason:** The `os.environ` references are SDK usage examples in an instructional context rather than credential harvesting, but the pattern technically matches the check-4 criteria and warrants human review.
**Action:** User approval required before install — confirm the `os.environ` calls are acceptable in your environment

---

## Skill Audit: flutter-architecting-apps
**Source:** https://github.com/flutter/skills
**Date:** 2026-04-22

| # | Check | Result | Note |
|---|---|---|---|
| 1 | Repo exists | ✅ PASS | Public repo at flutter/skills, 1.2k stars, 68 forks |
| 2 | Active maintenance | ✅ PASS | Repo pushed_at: 2026-04-16; SKILL.md last_modified: 2026-03-12 — both after 90-day cutoff |
| 3 | No external calls | ✅ PASS | No http/https calls, curl, fetch, axios, or webhook directives in instruction sections |
| 4 | No credential fishing | ✅ PASS | No API_KEY, TOKEN, SECRET, PASSWORD, os.environ, process.env, or .env references anywhere |
| 5 | No hidden instructions | ✅ PASS | No override, disregard, ignore previous, or role-switching language found |
| 6 | Scope is bounded | ✅ PASS | Instructions stay within Flutter layered architecture domain; workflow touches only Dart source files and test execution |

**Verdict: PASS**
**Reason:** Clean skill scoped entirely to Flutter app architecture patterns with no external calls, credential access, or out-of-scope instructions.
**Action:** Install approved

---

## Skill Audit: flutter-managing-state
**Source:** https://github.com/flutter/skills
**Date:** 2026-04-22

| # | Check | Result | Note |
|---|---|---|---|
| 1 | Repo exists | ✅ PASS | Public repo at flutter/skills, confirmed valid |
| 2 | Active maintenance | ✅ PASS | Repo pushed_at: 2026-04-16; SKILL.md last_modified: 2026-03-12 — both after 90-day cutoff |
| 3 | No external calls | ✅ PASS | No http/https calls, curl, fetch, axios, or webhook directives in instruction sections |
| 4 | No credential fishing | ✅ PASS | No API_KEY, TOKEN, SECRET, PASSWORD, os.environ, process.env, or .env references anywhere |
| 5 | No hidden instructions | ✅ PASS | No override, disregard, ignore previous, or role-switching language found |
| 6 | Scope is bounded | ✅ PASS | Instructions stay within Flutter state management domain (MVVM + Provider); workflow touches only Dart source files |

**Verdict: PASS**
**Reason:** Clean skill scoped entirely to Flutter state management patterns with no external calls, credential access, or out-of-scope instructions.
**Action:** Install approved

---

## Skill Audit: flutter-testing-apps
**Source:** https://github.com/flutter/skills
**Date:** 2026-04-22

| # | Check | Result | Note |
|---|---|---|---|
| 1 | Repo exists | ✅ PASS | Public repo at flutter/skills, confirmed valid |
| 2 | Active maintenance | ✅ PASS | Repo pushed_at: 2026-04-16; SKILL.md last_modified: 2026-03-12 — both after 90-day cutoff |
| 3 | No external calls | ✅ PASS | No http/https calls, curl, fetch, axios, or webhook directives; chromedriver/Firebase Test Lab references are local tool invocations, not agent-initiated network calls |
| 4 | No credential fishing | ✅ PASS | No API_KEY, TOKEN, SECRET, PASSWORD, os.environ, process.env, or .env references anywhere |
| 5 | No hidden instructions | ✅ PASS | No override, disregard, ignore previous, or role-switching language found |
| 6 | Scope is bounded | ✅ PASS | Instructions stay within Flutter testing domain (unit, widget, integration tests); no unexpected filesystem writes outside test directories or agent spawning |

**Verdict: PASS**
**Reason:** Clean skill scoped entirely to Flutter testing patterns with no external calls, credential access, or out-of-scope instructions.
**Action:** Install approved

---

## Skill Audit: security-best-practices
**Source:** https://github.com/openai/skills
**Date:** 2026-04-22

| # | Check | Result | Note |
|---|---|---|---|
| 1 | Repo exists | ✅ PASS | Valid public repo at openai/skills, 17.2k stars |
| 2 | Active maintenance | ✅ PASS | pushed_at: 2026-04-21, within 90-day window |
| 3 | No external calls | ✅ PASS | No http/https/curl/fetch/POST/GET/webhook/axios found outside permitted sections |
| 4 | No credential fishing | ✅ PASS | No API_KEY/TOKEN/SECRET/PASSWORD/env patterns found |
| 5 | No hidden instructions | ✅ PASS | No override/jailbreak phrases found |
| 6 | Scope is bounded | ✅ PASS | Instructions stay within declared security review domain; writes report to `security_best_practices_report.md` — expected filesystem output |

**Verdict: PASS**
**Reason:** All six checks pass; skill performs language-specific security best-practice reviews with no external calls, no credential fishing, and no hidden instructions.
**Action:** Install approved

---

## Skill Audit: security-threat-model
**Source:** https://github.com/openai/skills
**Date:** 2026-04-22

| # | Check | Result | Note |
|---|---|---|---|
| 1 | Repo exists | ✅ PASS | Valid public repo at openai/skills |
| 2 | Active maintenance | ✅ PASS | pushed_at: 2026-04-21, within 90-day window |
| 3 | No external calls | ✅ PASS | No http/https/curl/fetch/POST/GET/webhook/axios found |
| 4 | No credential fishing | ✅ PASS | No credential or environment variable patterns found |
| 5 | No hidden instructions | ✅ PASS | No override/jailbreak phrases found |
| 6 | Scope is bounded | ✅ PASS | Instructions stay within AppSec threat modeling; output is a `<repo-name>-threat-model.md` file — expected for this domain |

**Verdict: PASS**
**Reason:** All six checks pass; well-scoped AppSec threat modeling workflow with no network calls, credential fishing, or injection attempts.
**Action:** Install approved

---

## Skill Audit: render-deploy
**Source:** https://github.com/openai/skills
**Date:** 2026-04-22

| # | Check | Result | Note |
|---|---|---|---|
| 1 | Repo exists | ✅ PASS | Valid public repo at openai/skills |
| 2 | Active maintenance | ✅ PASS | pushed_at: 2026-04-21, within 90-day window |
| 3 | No external calls | ⚠️ WARN | Multiple `https://dashboard.render.com` URLs and `https://mcp.render.com/mcp` appear in workflow instruction steps (not just ## Prerequisites/Resources); deployment target URLs inherent to the skill's function but outside formal permitted sections |
| 4 | No credential fishing | ⚠️ WARN | `RENDER_API_KEY` with `export RENDER_API_KEY` appears in `## Prerequisites Check` section (functionally prerequisites-equivalent but not the exact `## Prerequisites` header); `JWT_SECRET` appears in a code example — doc context |
| 5 | No hidden instructions | ✅ PASS | No override/jailbreak phrases found |
| 6 | Scope is bounded | ✅ PASS | All instructions stay within Render deployment domain |

**Verdict: CONDITIONAL**
**Reason:** Two WARNs: external Render dashboard URLs in instruction body outside formal Resources/Prerequisites header, and `RENDER_API_KEY` with export instruction in a prerequisites-style section lacking the exact required header name.
**Action:** User approval required before install — confirm Render API key handling matches your secrets management policy

---

## Skill Audit: gh-fix-ci
**Source:** https://github.com/openai/skills
**Date:** 2026-04-22

| # | Check | Result | Note |
|---|---|---|---|
| 1 | Repo exists | ✅ PASS | Valid public repo at openai/skills |
| 2 | Active maintenance | ✅ PASS | pushed_at: 2026-04-21, within 90-day window |
| 3 | No external calls | ✅ PASS | All network-adjacent commands use the `gh` CLI — no raw http/https, curl, fetch, POST, GET, webhook, or axios calls |
| 4 | No credential fishing | ✅ PASS | No API_KEY/TOKEN/SECRET/PASSWORD/env patterns found |
| 5 | No hidden instructions | ✅ PASS | No override/jailbreak phrases found |
| 6 | Scope is bounded | ✅ PASS | Instructions stay within GitHub CI debugging domain; proposes fixes with explicit user approval gate |

**Verdict: PASS**
**Reason:** All six checks pass; skill uses the GitHub CLI for all GitHub interactions with no raw HTTP calls, no credential fishing, and a required user approval gate.
**Action:** Install approved

---

## Skill Audit: jupyter-notebook
**Source:** https://github.com/openai/skills
**Date:** 2026-04-22

| # | Check | Result | Note |
|---|---|---|---|
| 1 | Repo exists | ✅ PASS | Valid public repo at openai/skills |
| 2 | Active maintenance | ✅ PASS | pushed_at: 2026-04-21, within 90-day window |
| 3 | No external calls | ✅ PASS | No http/https/curl/fetch/POST/GET/webhook/axios found |
| 4 | No credential fishing | ✅ PASS | No credential or environment variable patterns found |
| 5 | No hidden instructions | ✅ PASS | No override/jailbreak phrases found |
| 6 | Scope is bounded | ✅ PASS | Instructions stay within Jupyter notebook creation domain; outputs go to `output/jupyter-notebook/` — expected filesystem writes |

**Verdict: PASS**
**Reason:** All six checks pass; cleanly scoped notebook scaffolding workflow with no external calls, no credential patterns, and no injection attempts.
**Action:** Install approved

---

## Skill Audit: playwright
**Source:** https://github.com/openai/skills
**Date:** 2026-04-22

| # | Check | Result | Note |
|---|---|---|---|
| 1 | Repo exists | ✅ PASS | Valid public repo at openai/skills |
| 2 | Active maintenance | ✅ PASS | pushed_at: 2026-04-21, within 90-day window |
| 3 | No external calls | ✅ PASS | `https://example.com` and `https://playwright.dev` appear only as argument examples in CLI command demonstrations — skill does not make autonomous HTTP calls; these are user-directed browser navigation targets |
| 4 | No credential fishing | ✅ PASS | No API_KEY/TOKEN/SECRET/PASSWORD/env patterns found |
| 5 | No hidden instructions | ✅ PASS | No override/jailbreak phrases found |
| 6 | Scope is bounded | ✅ PASS | Instructions stay within browser automation domain; artifact output to `output/playwright/` is expected |

**Verdict: PASS**
**Reason:** All six checks pass; example URLs are CLI argument placeholders, not autonomous network calls, and the skill stays cleanly within its declared domain.
**Action:** Install approved

---

## Skill Audit: insecure-defaults
**Source:** https://github.com/trailofbits/skills
**Date:** 2026-04-22

| # | Check | Result | Note |
|---|---|---|---|
| 1 | Repo exists | ✅ PASS | Valid public repo at trailofbits/skills, 4.7k stars |
| 2 | Active maintenance | ✅ PASS | pushed_at: 2026-04-21, within 90-day window |
| 3 | No external calls | ✅ PASS | No http/https/curl/fetch/POST/GET/webhook/axios found |
| 4 | No credential fishing | ✅ PASS | References to `process.env.JWT_SECRET`, `API_KEY`, `SECRET`, `.env` appear solely as detection-target patterns (what to search FOR in user code) — explicitly doc/warning context for a security audit skill |
| 5 | No hidden instructions | ✅ PASS | No override/jailbreak phrases found |
| 6 | Scope is bounded | ✅ PASS | Instructions stay within security auditing of insecure defaults; no unexpected filesystem writes, agent spawning, or global config reads |

**Verdict: PASS**
**Reason:** All six checks pass; credential-like strings appear only as regex detection patterns in a security audit skill — their documented and expected purpose.
**Action:** Install approved

---

## Skill Audit: static-analysis
**Source:** https://github.com/trailofbits/skills
**Date:** 2026-04-22

| # | Check | Result | Note |
|---|---|---|---|
| 1 | Repo exists | ✅ PASS | Valid public repo at trailofbits/skills |
| 2 | Active maintenance | ✅ PASS | pushed_at: 2026-04-21, within 90-day window |
| 3 | No external calls | ✅ PASS | No http/https/curl/fetch/POST/GET/webhook/axios found in semgrep SKILL.md; skill explicitly requires `--metrics=off` flag to prevent telemetry |
| 4 | No credential fishing | ✅ PASS | No credential or environment variable patterns found |
| 5 | No hidden instructions | ✅ PASS | No override/jailbreak phrases found |
| 6 | Scope is bounded | ⚠️ WARN | No top-level SKILL.md — plugin is a multi-skill bundle (CodeQL, Semgrep, SARIF) nested at non-standard paths; full scope verification impossible from canonical path; semgrep sub-skill itself is clean |

**Verdict: CONDITIONAL**
**Reason:** One WARN: the plugin uses a non-standard nested structure with no top-level SKILL.md, making canonical scope verification impossible; the semgrep sub-skill itself is clean but the full plugin boundary cannot be confirmed from a single authoritative file.
**Action:** User approval required before install — review all three sub-skill SKILL.md files (semgrep, codeql, sarif-parsing) individually before installing

---

## Skill Audit: property-based-testing
**Source:** https://github.com/trailofbits/skills
**Date:** 2026-04-22

| # | Check | Result | Note |
|---|---|---|---|
| 1 | Repo exists | ✅ PASS | Valid public repo at trailofbits/skills |
| 2 | Active maintenance | ✅ PASS | pushed_at: 2026-04-21, within 90-day window |
| 3 | No external calls | ✅ PASS | No http/https/curl/fetch/POST/GET/webhook/axios found |
| 4 | No credential fishing | ✅ PASS | No credential or environment variable patterns found |
| 5 | No hidden instructions | ✅ PASS | No override/jailbreak phrases found |
| 6 | Scope is bounded | ✅ PASS | Instructions stay within property-based testing guidance; references internal `{baseDir}/references/` paths only — no unexpected filesystem writes or network calls |

**Verdict: PASS**
**Reason:** All six checks pass; well-scoped testing methodology guide with no external calls, no credential patterns, and no injection attempts.
**Action:** Install approved

---

## Skill Audit: auth0-express
**Source:** https://github.com/auth0/skills
**Date:** 2026-04-22

| # | Check | Result | Note |
|---|---|---|---|
| 1 | Repo exists | ❌ FAIL | Repository https://github.com/auth0/skills returns HTTP 404 — does not exist as a public repository |
| 2 | Active maintenance | N/A | Blocked by Check 1 failure |
| 3 | No external calls | N/A | Blocked by Check 1 failure |
| 4 | No credential fishing | N/A | Blocked by Check 1 failure |
| 5 | No hidden instructions | N/A | Blocked by Check 1 failure |
| 6 | Scope is bounded | N/A | Blocked by Check 1 failure |

**Verdict: FAIL**
**Reason:** The repository `auth0/skills` does not exist on GitHub — the source URL returns a 404.
**Action:** Do not install — source repository is invalid

---

## Skill Audit: firebase-security-rules-auditor
**Source:** https://github.com/firebase/agent-skills
**Date:** 2026-04-22

| # | Check | Result | Note |
|---|---|---|---|
| 1 | Repo exists | ✅ PASS | Repo found at firebase/agent-skills (redirected from firebase/skills); valid public repo |
| 2 | Active maintenance | ✅ PASS | pushed_at: 2026-04-21 |
| 3 | No external calls | ✅ PASS | No http/https/curl/fetch/POST/GET/webhook/axios found in SKILL.md instructions |
| 4 | No credential fishing | ✅ PASS | No API_KEY, TOKEN, SECRET, PASSWORD, os.environ, process.env, .env, credentials patterns found |
| 5 | No hidden instructions | ✅ PASS | No override/ignore previous/act as/you are now patterns found |
| 6 | Scope is bounded | ✅ PASS | Declared domain is Firestore security rules auditing; instructions stay strictly within that domain |

**Verdict: PASS**
**Reason:** All six checks pass; self-contained read-and-evaluate auditor with no external calls, no credential fishing, and no scope creep. Note: listed as `firebase/skills` but actual repo is `firebase/agent-skills`.
**Action:** Install approved

---

## Skill Audit: dd-apm
**Source:** https://github.com/datadog-labs/skills
**Date:** 2026-04-22

| # | Check | Result | Note |
|---|---|---|---|
| 1 | Repo exists | ❌ FAIL | GitHub returned 404 for datadog-labs/skills — repository does not exist |
| 2 | Active maintenance | N/A | |
| 3 | No external calls | N/A | |
| 4 | No credential fishing | N/A | |
| 5 | No hidden instructions | N/A | |
| 6 | Scope is bounded | N/A | |

**Verdict: FAIL**
**Reason:** The source repository datadog-labs/skills does not exist on GitHub.
**Action:** Do not install — source repo invalid

---

## Skill Audit: dd-pup
**Source:** https://github.com/datadog-labs/skills
**Date:** 2026-04-22

| # | Check | Result | Note |
|---|---|---|---|
| 1 | Repo exists | ❌ FAIL | GitHub returned 404 for datadog-labs/skills — repository does not exist |
| 2 | Active maintenance | N/A | |
| 3 | No external calls | N/A | |
| 4 | No credential fishing | N/A | |
| 5 | No hidden instructions | N/A | |
| 6 | Scope is bounded | N/A | |

**Verdict: FAIL**
**Reason:** The source repository datadog-labs/skills does not exist on GitHub.
**Action:** Do not install — source repo invalid

---

## Skill Audit: dd-llmo-eval-bootstrap
**Source:** https://github.com/datadog-labs/skills
**Date:** 2026-04-22

| # | Check | Result | Note |
|---|---|---|---|
| 1 | Repo exists | ❌ FAIL | GitHub returned 404 for datadog-labs/skills — repository does not exist |
| 2 | Active maintenance | N/A | |
| 3 | No external calls | N/A | |
| 4 | No credential fishing | N/A | |
| 5 | No hidden instructions | N/A | |
| 6 | Scope is bounded | N/A | |

**Verdict: FAIL**
**Reason:** The source repository datadog-labs/skills does not exist on GitHub.
**Action:** Do not install — source repo invalid

---

## Skill Audit: sentry-workflow
**Source:** https://github.com/getsentry/skills
**Date:** 2026-04-22

| # | Check | Result | Note |
|---|---|---|---|
| 1 | Repo exists | ✅ PASS | getsentry/skills is a valid public repository |
| 2 | Active maintenance | ✅ PASS | pushed_at: 2026-04-20 |
| 3 | No external calls | ❌ FAIL | HALT — Cannot read SKILL.md: skill named `sentry-workflow` does not exist in repo's skills/ directory (confirmed by full directory listing); SKILL.md unreachable on both main and master branches |
| 4 | No credential fishing | N/A | |
| 5 | No hidden instructions | N/A | |
| 6 | Scope is bounded | N/A | |

**Verdict: FAIL**
**Reason:** The skill `sentry-workflow` does not exist in getsentry/skills — no matching directory found and SKILL.md cannot be retrieved from either branch.
**Action:** Do not install — skill not found in repo

---

## Skill Audit: sentry-fix-issues
**Source:** https://github.com/getsentry/skills
**Date:** 2026-04-22

| # | Check | Result | Note |
|---|---|---|---|
| 1 | Repo exists | ✅ PASS | getsentry/skills is a valid public repository |
| 2 | Active maintenance | ✅ PASS | pushed_at: 2026-04-20 |
| 3 | No external calls | ❌ FAIL | HALT — Cannot read SKILL.md: skill named `sentry-fix-issues` does not exist in repo's skills/ directory (confirmed by full directory listing); SKILL.md unreachable on both main and master branches |
| 4 | No credential fishing | N/A | |
| 5 | No hidden instructions | N/A | |
| 6 | Scope is bounded | N/A | |

**Verdict: FAIL**
**Reason:** The skill `sentry-fix-issues` does not exist in getsentry/skills — no matching directory found and SKILL.md cannot be retrieved from either branch.
**Action:** Do not install — skill not found in repo

---

## Skill Audit: expo-cicd-workflows
**Source:** https://github.com/expo/skills
**Date:** 2026-04-22

| # | Check | Result | Note |
|---|---|---|---|
| 1 | Repo exists | ✅ PASS | expo/skills is a valid public repository |
| 2 | Active maintenance | ✅ PASS | pushed_at: 2026-04-20 |
| 3 | No external calls | ❌ FAIL | Instructions section contains multiple explicit `https://` URLs (api.expo.dev/v2/workflows/schema, raw.githubusercontent.com/expo/expo/...) fetched at runtime via a `node fetch.js <url>` script — active network calls during skill execution, not confined to Resources/Prerequisites |
| 4 | No credential fishing | N/A | Blocked by Check 3 failure |
| 5 | No hidden instructions | N/A | Blocked by Check 3 failure |
| 6 | Scope is bounded | N/A | Blocked by Check 3 failure |

**Verdict: FAIL**
**Reason:** The skill instructs the agent to make live HTTP fetches to external URLs during normal execution, outside any Resources or Prerequisites section.
**Action:** Do not install — external runtime network calls present

---

## Skill Audit: page-cro
**Source:** https://github.com/coreyhaines31/marketingskills
**Date:** 2026-04-22

| # | Check | Result | Note |
|---|---|---|---|
| 1 | Repo exists | ✅ PASS | Public repo, 22.9k stars |
| 2 | Active maintenance | ✅ PASS | pushed_at 2026-04-22 |
| 3 | No external calls | ✅ PASS | No http/https, curl, fetch, webhook, or axios found in SKILL.md |
| 4 | No credential fishing | ✅ PASS | No API_KEY, TOKEN, SECRET, PASSWORD, or env patterns found |
| 5 | No hidden instructions | ✅ PASS | No override, ignore previous, act as, or jailbreak patterns found |
| 6 | Scope is bounded | ✅ PASS | Instructions stay within CRO analysis and marketing copy domain; no filesystem writes, network calls, or agent spawning |

**Verdict: PASS**
**Reason:** Clean marketing-focused skill with no external calls, credential references, or prompt injection patterns.
**Action:** Install approved

---

## Skill Audit: content-strategy
**Source:** https://github.com/coreyhaines31/marketingskills
**Date:** 2026-04-22

| # | Check | Result | Note |
|---|---|---|---|
| 1 | Repo exists | ✅ PASS | Public repo, 22.9k stars |
| 2 | Active maintenance | ✅ PASS | pushed_at 2026-04-22 |
| 3 | No external calls | ✅ PASS | No http/https, curl, fetch, webhook, or axios found in SKILL.md |
| 4 | No credential fishing | ✅ PASS | No API_KEY, TOKEN, SECRET, PASSWORD, or env patterns found |
| 5 | No hidden instructions | ✅ PASS | No override, ignore previous, act as, or jailbreak patterns found |
| 6 | Scope is bounded | ✅ PASS | Instructions stay within content strategy planning domain |

**Verdict: PASS**
**Reason:** Clean content planning skill with no external calls, credential references, or prompt injection patterns.
**Action:** Install approved

---

## Skill Audit: copywriting
**Source:** https://github.com/coreyhaines31/marketingskills
**Date:** 2026-04-22

| # | Check | Result | Note |
|---|---|---|---|
| 1 | Repo exists | ✅ PASS | Public repo, 22.9k stars |
| 2 | Active maintenance | ✅ PASS | pushed_at 2026-04-22 |
| 3 | No external calls | ✅ PASS | No http/https, curl, fetch, webhook, or axios found in SKILL.md |
| 4 | No credential fishing | ✅ PASS | No API_KEY, TOKEN, SECRET, PASSWORD, or env patterns found |
| 5 | No hidden instructions | ✅ PASS | No override, ignore previous, act as, or jailbreak patterns found |
| 6 | Scope is bounded | ✅ PASS | Instructions stay within conversion copywriting domain; references related skills but does not spawn agents or write to filesystem |

**Verdict: PASS**
**Reason:** Clean copywriting skill with no external calls, credential references, or prompt injection patterns.
**Action:** Install approved

---

## Skill Audit: typefully
**Source:** https://github.com/typefully/skills
**Date:** 2026-04-22

| # | Check | Result | Note |
|---|---|---|---|
| 1 | Repo exists | ❌ FAIL | GitHub returns 404 — repository does not exist |
| 2 | Active maintenance | N/A | — |
| 3 | No external calls | N/A | — |
| 4 | No credential fishing | N/A | — |
| 5 | No hidden instructions | N/A | — |
| 6 | Scope is bounded | N/A | — |

**Verdict: FAIL**
**Reason:** The repository `typefully/skills` does not exist on GitHub (404).
**Action:** Do not install — source repo is missing

---

## Skill Audit: saas-revenue-growth-metrics
**Source:** https://github.com/deanpeters/Product-Manager-Skills
**Date:** 2026-04-22

| # | Check | Result | Note |
|---|---|---|---|
| 1 | Repo exists | ✅ PASS | Public repo, 3.6k stars, v0.75 released 2026-03-17 |
| 2 | Active maintenance | ✅ PASS | pushed_at 2026-04-02 |
| 3 | No external calls | ✅ PASS | No http/https, curl, fetch, webhook, or axios found in SKILL.md |
| 4 | No credential fishing | ✅ PASS | No API_KEY, TOKEN, SECRET, PASSWORD, or env patterns found |
| 5 | No hidden instructions | ✅ PASS | No override, ignore previous, act as, or jailbreak patterns found |
| 6 | Scope is bounded | ✅ PASS | Instructions stay within SaaS revenue metrics analysis; purely educational, no filesystem writes or network calls |

**Verdict: PASS**
**Reason:** Clean PM metrics reference skill with no external calls, credential references, or prompt injection patterns.
**Action:** Install approved

---

## Skill Audit: ui-test
**Source:** https://github.com/browserbase/skills
**Date:** 2026-04-22

| # | Check | Result | Note |
|---|---|---|---|
| 1 | Repo exists | ✅ PASS | Public repo, 515 stars |
| 2 | Active maintenance | ✅ PASS | pushed_at 2026-04-21 |
| 3 | No external calls | ⚠️ WARN | `curl -s -o /dev/null` used in server-detection step; `https://staging.your-app.com` as example test target — both appear in Instructions body outside Resources/Prerequisites |
| 4 | No credential fishing | ❌ FAIL | `BROWSERBASE_API_KEY` referenced in Instructions as a required environment variable for remote browser sessions, outside any warning or documentation context |
| 5 | No hidden instructions | N/A | Blocked by Check 4 failure |
| 6 | Scope is bounded | N/A | Blocked by Check 4 failure |

**Verdict: FAIL**
**Reason:** `BROWSERBASE_API_KEY` is referenced in the Instructions body as a required env variable, constituting credential fishing outside an acceptable warning/doc context.
**Action:** Do not install — request publisher move credential references to a Prerequisites or Warning section only

---

## Skill Audit: code-review
**Source:** https://github.com/coderabbitai/skills
**Date:** 2026-04-22

| # | Check | Result | Note |
|---|---|---|---|
| 1 | Repo exists | ✅ PASS | Public repo, v1.1.1, 24 commits |
| 2 | Active maintenance | ✅ PASS | pushed_at 2026-04-22 |
| 3 | No external calls | ❌ FAIL | `https://www.coderabbit.ai/cli` appears in an installation code block inside Instructions; `https://docs.coderabbit.ai/cli` in a Documentation section — both outside Resources/Prerequisites sections |
| 4 | No credential fishing | N/A | Blocked by Check 3 failure |
| 5 | No hidden instructions | N/A | Blocked by Check 3 failure |
| 6 | Scope is bounded | N/A | Blocked by Check 3 failure |

**Verdict: FAIL**
**Reason:** External HTTPS URLs directing to `coderabbit.ai` domains appear in the Instructions body outside Resources/Prerequisites, triggering the external-calls block check.
**Action:** Do not install — request publisher move installation and documentation URLs to a Resources or Prerequisites section

---

## Skill Audit: hugging-face-datasets
**Source:** https://github.com/huggingface/skills
**Date:** 2026-04-22

| # | Check | Result | Note |
|---|---|---|---|
| 1 | Repo exists | ✅ PASS | Public repo, 10.3k stars; actual skill directory is `huggingface-datasets` |
| 2 | Active maintenance | ✅ PASS | pushed_at 2026-04-22 |
| 3 | No external calls | ❌ FAIL | `https://datasets-server.huggingface.co` appears as base API URL in Instructions body with `curl` examples making live GET calls — all outside Resources/Prerequisites sections |
| 4 | No credential fishing | N/A | Blocked by Check 3 failure |
| 5 | No hidden instructions | N/A | Blocked by Check 3 failure |
| 6 | Scope is bounded | N/A | Blocked by Check 3 failure |

**Verdict: FAIL**
**Reason:** The skill's Instructions body contains live `https://` API endpoints and `curl` call examples outside Resources/Prerequisites, triggering the external-calls block check.
**Action:** Do not install — request publisher move API base URL and curl examples to Resources/Prerequisites or a clearly delimited API Reference section
