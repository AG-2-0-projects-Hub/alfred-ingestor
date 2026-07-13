# Alfred / HostWhisperer — Launch Roadmap

**Version:** 1.3
**Created:** 2026-06-30 · **Updated:** 2026-07-12 (**infra cutover executed** — DB split into a fresh prod Supabase project + backend/scraper migrated to **Cloud Run**, prod isolated on its own GCP project / Telegram bot / Gemini key; full multimodal (Alfred sees images + hears voice) shipped. Gate 1 (staging) **passed**; Gate 2 (new-prod e2e) pending → then `staging→main`. Two new 🔴 M1 items added: **staging/prod platform parity** + **CI/CD trigger on `main`**. See `_Context/session-digest.md`)
**Owner:** Founder (decision-maker + direction) · Execution: AG agents (Claude Code / Gemini)
**Status:** Active — pre-closed-beta
**Structure:** Workstream tracks × launch milestones (matrix), sequenced by readiness (no hard dates)

---

## 1. How to use this document

This is the single source of truth for getting Alfred from "working product" to "launched SaaS." It is organized as **10 parallel tracks** mapped across **4 milestones** (+ a Horizon).

- **Milestones (M0→M3)** answer *"when / in what order."* Sequenced by **readiness**, not dates — each milestone's exit criteria unlock the next.
- **Tracks** answer *"what kind of work."* They run in parallel; a milestone is "done" when every track has cleared its cell.
- The **Strategic Risk Register** (§9) holds existential/strategic exposures and their (lean) mitigations.
- The **Open Decisions register** (§10) holds blockers that gate downstream work — resolve early.
- The **Operating Model** (§8) defines the autopilot: PM agent + supporting agents, founder intervening only for decisions.

### Priority tiers
Every added item is tagged so you know what's load-bearing vs optional:

- 🔴 **Necessary** — must clear before its milestone ships; legal, financial, data-safety, or guest-trust critical.
- 🟡 **Helpful** — materially de-risks or accelerates; do when bandwidth allows.
- 🟢 **Nice-to-have** — later; scale- or revenue-gated.

### Anti-over-engineering principle
**Bias to buy-not-build and the simplest solution that clears the bar.** Most "necessary" items below are a *decision* or a *toggle*, not a system to build — use managed providers (Stripe Tax, a merchant-of-record, hosted status page, provider safety filters) and add complexity only where the risk genuinely justifies it. An "agent" here is a prompt + a trigger, not a service.

---

## 2. Naming & brand architecture

Resolved decision (2026-06-30):

| Name | Role |
|---|---|
| **Alfred** | The **engine / assistant persona** — the AI guests and hosts talk to. Internal + in-product. |
| **HostWhisperer** | The **public product & company brand** — landing page, marketing, billing, domain. |

The HostWhisperer brand identity already exists (see `_Context/Design inspo/Brand_ID_guidelines.md`): ethereal glassmorphism, deep obsidian canvas, AI-aurora mesh gradients, "the Invisible Proxy" persona. Product UI and landing both build against that guide.

> **Tagline anchor:** "Give yourself the gift of time."

---

## 3. Where we are now (snapshot)

**The product largely exists and runs.** The full V1 loop is live: ingest (host files + Airbnb scrape) → merge/conflict resolution → vectorized "Brain" → guest chat → escalation / Live Tunnel → self-learning loop → host dashboard (Flutter) + guest web app (Next.js/Vercel). RLS is enforced with booking-scoped guest JWTs.

We are effectively at **Phase 6 of 7** of the V1 build. Remaining work is **hardening + go-to-market + the business/trust layer**, not net-new core product. See `_Context/session-digest.md` for live engineering state.

---

## 4. Milestone spine

- **M0 — Harden & Ship** — close out work in flight; get the current system onto solid ground. *No new product.*
  **Exit:** staging verified e2e under JWT; prod env vars set; `staging→main` merged; DB reset plan ready; QA intake promoted; backups + 2FA verified; uptime monitors green.
- **M1 — Beta-Ready** — everything a real human needs before touching Alfred: brand applied, landing/waitlist, legal + privacy, final UX, mobile, infra migrated, AI guardrails, agents stood up.
  **Exit:** brand applied; landing + waitlist live; ToS + Privacy published; security review passed; mobile-optimized; Cloud Run migrated; self-serve onboarding works; restore tested; PM + QA agents live.
- **M2 — Closed Beta** — invite 20–30 properties (family/partners). Observe, support, learn, iterate. **WhatsApp + Telegram go live here** (the channels beta testers actually use).
  **Exit:** cohort onboarded; WA/TG live; feedback loop running; stability acceptable; conversion/retention signal captured.
- **M3 — Public Launch + begin V2** — open to paying customers; add the V2 scale stack public volume requires.
  **Exit:** billing + tax live; marketing campaign shipped; V2 scale stack deployed; load-tested.
- **Horizon — V3** — OTA channel-manager + advanced automation. See §11.

---

## 5. The matrix (tracks × milestones)

| Track | M0 Harden | M1 Beta-Ready | M2 Closed Beta | M3 Public + V2 |
|---|---|---|---|---|
| **1. Engineering & Infra** | Redeploy staging, verify guest chat e2e under JWT, test soft-delete, set prod env vars, `staging→main`, ~~DB reset~~ → ✅ **DB split** | ✅ Cloud Run migration + DB split · 🔴 staging/prod **platform parity** · 🔴 **CI/CD trigger on `main`** · self-serve onboarding, harden error states, 🔴 AI guardrails + per-tenant rate limit | **WhatsApp + Telegram live**, beta stability fixes | V2: Redis/BullMQ queues, Sentry/Axiom, Resend, PostHog, scale-out |
| **2. Brand & Identity** | Lock name (done), secure domain | Finalize logo/wordmark, apply glassmorphism design system | — | Brand refresh for public |
| **3. Marketing & Growth** | — | Landing page (Evolutionary + Neuromarketing brief §7), value prop, waitlist | Beta testimonials, referral seeds | Launch campaign, pricing page, SEO/content, paid acquisition |
| **4. UX/UI & Mobile** | — | 🔨 Mobile optimization (host dashboard stopgaps done), brand visual redesign (Stitch), final UI pass, onboarding UX | Usability fixes from beta | Polish |
| **5. Privacy, Security & Trust** | 🔴 Finalize ToS | 🔴 Privacy Policy, cookie taxonomy + consent banner, document RLS, security review, bucket/retention audit | DPA / consent ops (if EU), incident response basics | SLA, compliance hardening |
| **6. QA, Maintenance & Reliability** | Promote intake → scenarios, run Layer 1, uptime monitors | Layer 2 Playwright, dedicated QA agent (§8), 🟡 AI answer eval set, QA-matrix evolution | Beta monitoring + triage | Regression suite, load test (200 concurrent) |
| **7. Agent Operations** | Define operating model (hybrid) | Stand up PM agent + near-term agents (§8) | Autopilot during beta, escalate decisions | Tune autonomy |
| **8. Business & Money** | — | 🔴 Legal entity + tax/billing approach, 🔴 unit-economics sketch, 🟡 pricing decision | (free beta — billing optional) | 🔴 Billing + tax live, 🟡 insurance, 🟢 AUP/SLA |
| **9. Reliability & Continuity** | 🔴 Verify backups + 2FA/secrets audit | 🔴 Test a restore + email deliverability (SPF/DKIM/DMARC), 🟡 status page | 🟡 Incident runbook + on-call alerting | 🟢 DR drill, SLA |
| **10. Support & Help** | — | 🔴 Support channel (help@ + FAQ), 🟡 in-app feedback/bug capture | Beta support triage | 🟢 Help center / KB, onboarding video |

---

## 6. Track detail

### Track 1 — Engineering & Infra
*Objective:* a stable, scalable backend that runs without firefighting.
- ✅ **M0:** Redeploy staging + verify guest chat e2e under booking JWT (confirmed working, staging + prod).
- ✅ **M0:** Test soft-delete/anonymization end-to-end (shipped `bd13deb`/`fdf965c`, live-verified).
- ✅ **M0:** Set prod env vars (`SUPABASE_JWT_SECRET`, `PYTHON_VERSION=3.12.10`).
- **M0:** Merge `staging→main` — new batch pending (Telegram, roadmap, dashboard, feedback, prompt fixes), deferred until after mobile UI + further QA hardening.
- ✅ **M0:** Prepare clean DB reset plan — runbook at `_Context/plans/db-reset-runbook.md` (2026-07-08). Execution stays destructive-gated (shared DB wipes prod: explicit CONFIRM + fresh verified backup; see tackle plan Wave 4).
- ✅ **M1 — Cloud Run migration + DB split (2026-07-12).** Prod now runs on its **own** stack, fully isolated from staging: fresh Supabase project **`alfred-prod`** (`ylaooctefesedrecshic`, eu-central-1 — schema reproduced from staging with **zero-delta parity** via `_Context/plans/prod-schema.sql`), backend + scraper on **Cloud Run** (`europe-west3`, GCP project `alfred-prod-502215`), secrets in **Secret Manager**, prod bot `@AlwaysAlfred_bot`, and its own Gemini key (billed to that project's $300 credit). Backend runs **`min-instances=1`** — non-negotiable: the Telegram `BackgroundTasks` reply is CPU-frozen otherwise. The old shared project (`gcxxilzfhwlsjcvtpsvj`) is now **staging** and must never be wiped. ⚠️ **Post-split rule: every migration must be applied to BOTH projects.**
- **M1 — Cutover steps remaining:** Gate 2 (new-prod e2e) → `staging→main` → retire Render prod → staging→Cloud Run (below) → CI/CD trigger (below).
- 🔴 **M1 — Staging/prod platform parity (added 2026-07-12):** staging still runs on **Render** while prod runs on **Cloud Run**. That mismatch hides a real bug class — the `min-instances=1` CPU-freeze is a **Cloud-Run-only** failure that staging could never reproduce, so a green staging test would not predict prod. Move staging onto Cloud Run (own services, staging DB + `@AlfredHostW_bot` + own key) and **retire Render entirely**. Principle: **same code + same platform; different data + credentials.**
- 🔴 **M1 — CI/CD for prod (added 2026-07-12):** Cloud Run does **not** auto-deploy on merge (initial deploys were manual `gcloud run deploy --source`), so until a **Cloud Build trigger on `main`** exists, merging `staging→main` will *not* update prod. Conversely, `render.yaml` has `autoDeploy: true` — **disable Render-prod autoDeploy before the merge**, or it will redeploy the old prod stack against the old DB.
- **M1:** Self-serve signup + guided onboarding; harden error states.
- 🔨 🔴 **M1 — AI guardrails (keep simple):** shipped to `staging` 2026-07-08 (`80d8ac6`, Render-deployed) in `backend/services/guardrails.py` + `messages.py` + prompt hardening — per-conversation **rate limit** (20/hr · 100/day, env-tunable counters, not a quota engine), **high-stakes-field fallback** (server-side backstop: address/access codes/wifi/check-times answered only from confirmed Master-JSON data, else "let me confirm with your host" + escalation — **user-verified live on Bungalito**), prompt-injection defense + 2000-char input cap. Backed by new index `idx_messages_conversation_created`. *No ML moderation pipeline.* Status: on staging → prod via the next `staging→main` merge.
- 🔨 **M1 — Self-learning quality gate (2026-07-08, `33b955a`):** two-layer triage on the resolve loop so only genuinely reusable Q&A reaches the host's Accept/Discard queue (Layer 1 drops emergencies/hostility/financial/out-of-scope by `escalation_reason`; Layer 2 = summarizer reusability judgment). Every outcome recorded in the new **permanent pseudonymized `learning_events` ledger** (no guest name; property as UUID) — the durable dataset for the Track-6 eval set + product-gap insight. Also narrowed escalation scope so off-topic/nonsensical guest messages redirect instead of escalating. Staging → prod via next merge.
- ✅ **M2:** Telegram guest channel live (native port, `@AlfredHostW_bot`, live-tested end-to-end on staging 2026-07-05).
- ✅ **M1/M2 — Multimodal guest chat (2026-07-10 `90faaa9`, refined 2026-07-12).** Alfred now **sees photos and hears voice notes** on both web and Telegram: media is stored to `chat_media` (so the host sees/hears it too) and passed to Gemini as real image/audio parts, then answered in-thread. A **photo burst** (≥2 photos within a short window — env-tunable) escalates to the host, since several photos usually means "come look at this"; a lone photo or a voice note is ordinary conversation and does **not** escalate. Telegram albums are debounced by `media_group_id` so one album yields **one** reply and **one** transition notice, not one per photo.
- 🔨 **M1/M2 — Channel isolation (Tier 1 shipped 2026-07-09, `368128a`, user-verified):** one unified conversation per booking; `conversations.active_channel` follows the guest so host replies + transition notices route only to the channel the guest is actually using. The unified web view is intentionally the **"main renter / Airbnb account-owner oversight" view** — the reputation-holder sees the whole thread across channels and can forward/relay to sub-guests. **Deferred to the WA/Airbnb multi-channel work:** optional per-channel filtering of a *sub-guest's* own view (tag each message with its channel) — a product decision, not a gap, since the account-owner oversight view is desirable.
- **M2:** 🔴 WhatsApp live. *Dependency:* WhatsApp Business API needs Meta verification — **start in M1** (R/D2). *Slots into the active-channel model — becomes another `active_channel` value; keep the conversation unified, add per-channel guest-view filtering here.*
- **M3:** V2 scale stack — Redis cache + BullMQ queues, Sentry + Axiom, Resend, PostHog.
- 🔴 **M1 — Transactional email for beta (buy-not-build):** confirm what sends auth mail today (Supabase Auth?); wire the minimum set — welcome, password reset, guest-link delivery. Full Resend template suite stays V2/M3.

### Track 2 — Brand & Identity
*Objective:* one coherent HostWhisperer identity.
- ✅ **M0:** Name locked — Alfred = engine/assistant persona, HostWhisperer = public brand (resolved 2026-06-30).
- **M0:** Secure domain + handles for HostWhisperer (open — D1).
- **M1:** Finalize wordmark (**host** bold / *whisperer* light) + key/waves symbol; codify design tokens; apply to dashboard, guest app, landing.
- **M3:** Refresh for public surface.

### Track 3 — Marketing & Growth
*Objective:* strangers → waitlist → beta → paying hosts.
- **M1:** Landing page against the brief (§7); sharpen value prop; waitlist.
- **M2:** Beta testimonials / case studies; referral seeds.
- **M3:** Launch campaign, pricing page, SEO/content, paid acquisition tests.
- 🟡 **Foundation (do in M1, lightweight):** define **ICP** (property count, region, persona) and **North-Star metric + funnel** — one page each, not a research project.
- 🟡 **M1 — Demo / sandbox property:** a live "try Alfred without signup" example for the landing + prospects; doubles as a marketing asset.
- 🟡 **M2 — Lightweight beta analytics:** basic activation/funnel signal before PostHog (M3) lands.
- 🟢 **M1 — Social/meta polish:** OG tags, favicon, link-preview image for the landing.
- 🟢 **M2/M3 — Onboarding/demo video:** marketing + support in one.

### Track 4 — UX/UI & Mobile
*Objective:* effortless on the devices people actually use.
- 🔨 **M1 — Mobile optimization (host dashboard):** in progress — stopgap fixes shipped to `staging` 2026-07-07 (property cards unclipped + tappable Settings, app-bar account/profile menu, host chat dialog usable on mobile, Chat History routed to the fixed dialog, conversation pills no longer overlap the action row). Full mobile+web redesign against the brand still pending (Stitch session).
- 🔨 **M1 — Host dashboard features (2026-07-07 evening, `96ce00a`):** shipped a host **profile menu** (name/nickname/bio/avatar/email/# properties) + a **dashboard impact-stats strip** (Alfred replies, hours saved, autopilot rate, guests helped), an **escalation-gated resolve button**, and a **conversation archive lifecycle** (auto-archive once `guests.check_out` passes via `pg_cron`, manual archive, auto-reactivate on a new guest message). `check_in/check_out` added to `guests` as placeholders for the future **Channex.io** reservation feed. Deploy-to-test on staging pending.
- **M1:** Final UI pass (dashboard + guest app); guest-app mobile pass; onboarding UX.
- **M1 — Visual redesign to brand:** apply the canonical HostWhisperer look (deep-obsidian + AI-aurora ethereal glassmorphism) per `_Context/Alfred_core_description.md` + `_Context/Design inspo/Brand_ID_guidelines.md` — the shipped app still uses the older olive/sage palette. Kick off via Google Stitch.
- **M2:** Usability fixes from beta.
- **M3:** Polish.
- 🟢 **Open:** native iOS/Android apps (Flutter can) add an app-store track — **default web-only until demand proves it** (D9).
- 🟡 **M1 — Launch-language decision (D10):** if the ICP is Spanish/LATAM hosts, ship the UI in Spanish at launch — full multi-language stays V3.
- 🟢 **M1 — Accessibility pass:** basic a11y on the guest web app (contrast, labels, keyboard nav).

### Track 5 — Privacy, Security & Trust
*Objective:* legally and technically trustworthy before real data flows.
- **M0:** 🔴 Finalize ToS (`tos-draft.md` exists) — **include an AI-accuracy disclaimer** (R/R2).
- **M1:** 🔴 Privacy Policy; cookie taxonomy (functional/analytics/marketing) + consent banner wired to the real stack (only non-essential cookies post-consent); retention policy.
- ✅ **M1 — Security review + storage hardening (2026-07-12, `14ed3c0`).** Ran the security review over the full staging diff and fixed what it found: removed the anon INSERT/SELECT policies on **`Property_assets`** (verified every touchpoint is host/`authenticated`), scoped the **`chat_media`** anon INSERT to the guest's *own* conversation folder (removing it would have broken guest uploads — tightened, not deleted), locked `host_avatars` writes to the host's own `{uid}/` folder, and added **host-token auth + ownership checks** on every host endpoint (the backend uses the service-role key, which bypasses RLS, so those endpoints must police themselves). Avatar upload is now brokered via `POST /api/host/avatar`. The hardened policy set is what `prod-schema.sql` reproduces on the new prod project.
- ✅ **M1:** Document data protection — as-built RLS / booking-JWT / soft-delete write-up at `_Context/RLS_and_data_protection.md` (2026-07-08, from live `pg_policies`); feeds the security review + Privacy Policy.
- **M2:** DPA / consent ops *if EU guests* (conditional — D4); basic incident-response runbook.
- **M3:** SLA, compliance hardening.
- 🔴 **M1 — Consent capture at signup:** a versioned ToS/Privacy "I agree" recorded per account (not just cookie consent).
- 🔴 **M1 — Sub-processor list:** enumerate PII processors (Gemini/Vertex, Supabase, Apify/Firecrawl, hosting) for the Privacy Policy.
- 🔴 **M1 — Cover the `learning_events` ledger (added 2026-07-08):** the self-learning triage now writes a **permanent** row per resolved escalation. It's pseudonymized (no guest name; property as UUID) but is the first durable guest-derived store — the Privacy Policy must disclose it, and D4 must set its lawful basis + retention. See `_Context/RLS_and_data_protection.md`.
- 🔴 **M1/M2 — Data-subject rights:** self-serve account deletion + data export (host-side soft-delete exists; user-level does not). Necessary if EU (D4).

### Track 6 — QA, Maintenance & Reliability
*Objective:* quality holds automatically as the system changes.
- ✅ **M0:** Run Layer 1 QA suite.
- ✅ **M0:** Uptime monitors live (UptimeRobot, prod + staging backend/scraper).
- **M0:** Promote pending-intake entries → `_tests/scenarios.md` (partial — B10/C8/D5 done 2026-07-01; J6–J9 Telegram fixes + older popup/merge/RLS rows still queued).
- **M1:** Layer 2 Playwright; **dedicated QA agent** (§8); evolve `scenarios.md` into the spec-first QA matrix; error monitoring.
  - 🟡 **AI answer eval set (keep small):** ~20–30 fixed guest questions with expected-good answers; re-run on model changes to catch drift. Manual-to-start; this is distinct from UI QA. **Seed it from the `learning_events` ledger (added 2026-07-08)** — real escalations Alfred couldn't answer are the best eval cases; also mine it for systematic master_json gaps.
- **M2:** Beta monitoring + triage loop.
- **M3:** Regression suite; load test (200 concurrent, p95 < 5s).

### Track 7 — Agent Operations
*Objective:* Alfred-on-autopilot — agents run day-to-day, founder decides.
- ✅ **M0:** Operating model defined (hybrid — see §8).
- **M1:** Stand up **PM agent** + near-term supporting agents (§8).
- **M2:** Autopilot through beta; escalate genuine decisions.
- **M3:** Tune autonomy by what proved trustworthy.

### Track 8 — Business & Money *(new)*
*Objective:* get paid, stay legal and solvent — with the least machinery.
- 🔴 **M1 — Legal entity + tax/billing approach (decision, not a build).** Pick a structure for liability protection; choose the billing path. *Keep it simple: a **merchant-of-record** (Paddle / Lemon Squeezy) or **Stripe + Stripe Tax** handles VAT/sales-tax registration and remittance for you — do **not** build tax logic.*
- 🔴 **M1 — Unit-economics sketch.** One spreadsheet: per-property COGS (Gemini/Claude/Pinecone/Apify/Firecrawl/infra) vs price, so pricing covers margin. Back-of-envelope, not a model.
- 🟡 **M1 — Pricing decision** — tiers, free-trial vs freemium (D3).
- 🔴 **M3 — Billing live** via the chosen provider (dunning, refunds, invoices, proration are the *provider's* job — don't build).
- 🟡 **M3 — Insurance** (E&O + cyber) once there's revenue/users to justify it — not before.
- 🟢 **M3+ — Acceptable Use Policy + SLA** (template-based).
- *Note:* the closed beta (M2) can run **free** → billing isn't required until M3.

### Track 9 — Reliability & Continuity *(new)*
*Objective:* data is safe, outages are visible, and you're not a single point of failure.
- 🔴 **M0 — Verify backups + 2FA/secrets audit.** Confirm Supabase automated backups are on; enable **2FA on every vendor account** (Supabase/Render/Vercel/Pinecone/Apify/domain registrar); store creds + recovery codes in a password manager. *Nothing to build — just turn things on.*
- 🔴 **M1 — Test a restore once** (and document the steps); set up **email deliverability** (SPF/DKIM/DMARC on the domain) so transactional/marketing mail lands.
- 🟡 **M1 — Status page** — use a hosted/free one; don't build.
- 🟡 **M2 — Incident runbook + on-call alerting** — wire existing uptime monitors to push to your phone; one-page runbook, not a system.
- 🟢 **M3 — DR drill + SLA commitments.**

### Track 10 — Support & Help *(new)*
*Objective:* a stuck tester can reach you and help themselves — without you living in your inbox.
- 🔴 **M1 — Support channel:** a `help@` inbox (or shared) + a one-page FAQ. The bar for beta, not a helpdesk.
- ✅ 🟡 **M1 — In-app feedback / bug capture:** shipped 2026-07-05 (`feedback_dialog.dart` → `feedback` table, RLS insert-only for hosts). Dashboard-side "Feedback" review card is a scoped-but-unbuilt follow-up.
- 🟡 **M2 — Beta support triage:** the Support-triage agent (§8) works this queue; you handle real decisions.
- 🟢 **M3 — Help center / knowledge base + onboarding content.**

---

## 7. Marketing principles brief (Evolutionary Marketing + Neuromarketing)

> A starting brief the landing-page work (Track 3, M1) builds against. **Basics now; deepen with research before execution.**

**Evolutionary Marketing — core idea:** speak to deep, evolved drivers, not features. For premium STR owners: **status** (run a high-end operation effortlessly), **time/resource conservation** (reclaim hours), **risk/loss aversion** (never miss a message or a review), **tribe/belonging** (join smart operators). Frame the product as restoring *freedom and time*.

**Neuromarketing — principles to apply on the landing page:**
- **Cognitive ease / low friction** — negative space, one clear action per view.
- **Loss aversion framing** — dramatize the status-quo cost (missed messages, 2am pings, bad reviews) before relief.
- **Social proof** — beta testimonials, property counts, trust signals (M2 feeds this).
- **Anchoring** — pricing against the value of time saved / a property manager's fee.
- **Visual processing & gaze cueing** — serene, decluttered hero imagery; directional cues to the CTA.
- **Authority & calm** — the "Invisible Proxy" voice: serene assurance.

**To research before building:**
1. Evidence-based Neuromarketing landing patterns (CTA placement, contrast, hierarchy, scroll depth).
2. Evolutionary-driver messaging tested in B2B SaaS / proptech.
3. Competitor teardown (Hospitable, Besty, HostAI, etc.) — positioning gaps.
4. STR host willingness-to-pay / pricing anchors.

---

## 8. Operating model (autopilot)

**Goal:** the platform runs mostly on automatic; the founder steers and decides.

### Permanent PM agent — hybrid (scheduled + event-driven)
- **Scheduled:** daily check + weekly roadmap review — updates cell status, reports progress, surfaces blockers, proposes next actions.
- **Event-driven:** reacts to errors, founder feedback, PR merges, failed deploys, QA failures — acts or escalates.
- **Escalates for:** architectural decisions, spend, brand/positioning, anything in the registers (§9–§10).

### Supporting agents

| Agent | Trigger model | Tier · sequence | Responsibility |
|---|---|---|---|
| **QA agent** | Hybrid, event-primary | 🔴 M1 | Pre-merge gate: run Layer 1 on every `staging→main` PR, **block on failure**. Nightly/weekly full Layer 2 Playwright regression + report (catches Supabase realtime/free-tier + cold-start drift). On-demand too. |
| **Release / deploy agent** | Event-driven | 🟡 M1 | Verified deploys (Render/Vercel/Cloud Run), confirm health, handle the Vercel manual-redeploy quirk, report status. |
| **Support-triage agent** | Event-driven | 🟡 M1–M2 | Watch escalations + beta feedback; classify, draft responses, route real issues to founder/PM agent. |
| **FinOps / cost agent** | Scheduled daily + anomaly | 🔴 near-term | Watch API + infra spend, attribute cost per tenant, alert on runaway *before the bill does*. Protects margin (R/R3). |
| **AI-quality / eval agent** | Scheduled + on model change | 🟡 near-term | Run the eval set, score answer quality, catch drift when Gemini/Claude update (R/R2). |
| **Incident / on-call agent** | Event-driven | 🟡 near-term | First responder to outages: run diagnostics, draft status-page update, page founder only if it can't self-resolve. |
| **Security / dependency agent** | Scheduled + on PR | 🟡 around beta | Dependency vulns, secret-leak scans, RLS-regression checks, periodic security-review. |
| **Customer-success / onboarding agent** | Event + scheduled | 🟡 around beta | Detect stuck onboarding (property never trained), nudge hosts, health-check tenants. |
| **Analytics / insights agent** | Scheduled weekly | 🟢 post-beta | Metrics digest, funnel + churn-signal surfacing. |
| **Growth / content agent** | Scheduled | 🟢 post-beta | Draft SEO/content/build-in-public, competitor monitoring, waitlist nurture. |
| **Compliance-watch agent** | Scheduled | 🟢 later | Monitor Airbnb ToS changes, GDPR/EU AI Act, platform-policy shifts (R/R1). |

**Build order (don't build all at once):** near-term = **PM, QA, FinOps, AI-quality, Incident** (protect money, trust, uptime). Around beta = Release, Support-triage, Security, Customer-success. Later = Analytics, Growth, Compliance-watch.
> **Over-engineering guard:** add an agent only when the *manual* version of its job becomes a recurring drag. Each agent is a prompt + a trigger, not a microservice.

---

## 9. Strategic risk register

| # | Risk | Severity | Lean mitigation | Tier |
|---|---|---|---|---|
| R1 | **Airbnb platform dependency / ToS** — scraping listings + moving guests off-platform ("Trojan Horse") could violate policy; Airbnb could detect & block. | **High / existential** | Keep a low profile; treat **Channex/OTA (V3) as the legitimate path**; hold a written "if Airbnb blocks us" thesis; don't over-invest in fragile scraping. Compliance-watch agent monitors policy. | 🔴 acknowledge now |
| R2 | **AI gives wrong/harmful answer** (wrong code, checkout, address). | High | ToS accuracy disclaimer + high-stakes-field fallback (Track 1) + eval set (Track 6). | 🔴 |
| R3 | **Runaway AI cost / abuse** — a spammer runs up your bill. | Med–High | Per-tenant rate limit (Track 1) + FinOps agent alerts. | 🔴 |
| R4 | **Vendor single points of failure** — Gemini/Pinecone/Render/Apify/Firecrawl. | Med | Document dependencies; **accept for now** — don't build a multi-vendor abstraction prematurely; revisit if one proves unreliable. | 🟡 |
| R5 | **Founder unavailability (bus factor)** — 24/7 service, one person. | Med | Runbooks + autopilot agents + recovery codes stored safely. | 🟡 |
| R6 | **Competition** (Hospitable, Besty, HostAI). | Med | Clear ICP + differentiation (self-learning loop, Spanish/LATAM focus). | 🟡 |

---

## 10. Open decisions / blockers register

| # | Decision / blocker | Gates | Status |
|---|---|---|---|
| D1 | Domain name + handles for HostWhisperer | Brand, landing, email | Open |
| D2 | **Start Meta Business verification for WhatsApp** (days–weeks lead) | M2 WA channel | Open — **start in M1** |
| D3 | Pricing model + free-trial vs freemium | M3 monetization; beta→paid | Open |
| D4 | EU guests / GDPR scope (drives DPA, consent ops, cookie law) | Privacy M1/M2 | Open |
| D5 | Tracking/analytics stack confirmation (PostHog + landing analytics) | Cookie taxonomy, consent banner | Open |
| D6 | Cost & burn tracking (AI + infra scale with usage) | Sustainability; FinOps agent | Watch |
| D7 | DB reset execution window before beta | M0 exit → M2 | ✅ **Resolved 2026-07-12 — split, not wipe.** Prod got a brand-new empty Supabase project instead of wiping the shared one, so no destructive reset is needed and no window is required. `_Context/plans/db-reset-runbook.md` is **retired for prod**. |
| D8 | **Legal entity + billing path** (MoR vs Stripe+Stripe Tax) | Track 8; M3 billing | Open |
| D9 | Native mobile apps vs web-only | M1/M3 UX scope | Open — **default web-only** |
| D10 | Launch language (Spanish/LATAM-first vs English-first) | M1 UX scope, marketing copy, ICP | Open |

---

## 11. Horizon — V3

Parked; detail when M3 is in sight.
- **OTA / channel-manager integration (Channex.io)** — sync to Airbnb / Booking / VRBO through one layer instead of per-platform APIs. *Also the legitimate de-risk for R1.*
- **Dynamic pricing with a heat-map view** — recommended nightly pricing across dates/properties as a visual heat map.
- Cleaning-schedule automation, multi-language expansion (candidates).

---

*Founder-facing source of truth. The PM agent keeps cell status current. Update exit criteria as scope firms up.*
