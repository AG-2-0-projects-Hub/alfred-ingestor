# Project Lessons Log
_Discoveries logged here during sessions. Global candidates flagged for promotion._

---

## 2026-07-21 — Config health check: stray project-local `.mcp.json` with an unregistered Supabase ref

**Context:** Full AG_master + the-ingestor config audit before starting a new project (symlinks, MCP profile chain, git state, live Supabase connectivity).

**Discovery:** `projects/the-ingestor/.mcp.json` declares a server `supabase-prod` pointing at `project_ref=ylaooctefesedrecshic` — a ref that appears nowhere else in the system (not in `global.json`, not in `mcp_config.json`, not in this file's own documented `project_ref: gcxxilzfhwlsjcvtpsvj`). It's ungoverned: added outside the AG panel / `ag-switch` profile flow that GEMINI.md §2/§4 mandates as the only path for MCP registration. It was **not** active in the audited session (live `get_project_url` call correctly returned `gcxxilzfhwlsjcvtpsvj.supabase.co`), so no immediate risk — but if any tool ever auto-loads project-local `.mcp.json` files, it would silently point database operations at a different, unaudited Supabase project. User chose to leave it as-is for now rather than delete. **Global Candidate: No** — project-specific loose end, not a systemic gap.

**Impact:** No code changed. Flagged here as a known open item; revisit before any Supabase-touching work if the origin/purpose of `ylaooctefesedrecshic` is still unclear.

---

## 2026-07-20 — WhatsApp channel build: WSL python/pip gap, gcloud PATH trap, and a pricing-model deadline

**Context:** Building the WhatsApp guest channel as a port of the native Telegram channel (ROADMAP D2), deployed to staging (rev 00006) the same session. (The secret-naming, shared-queue, and id-regex traps found in this same session were promoted to `_global_lessons/lessons.md` on 2026-07-21 — see the index for the generalized versions.)

**Discovery:**
1. **WSL had neither `python3-venv` nor `pip`, and `ensurepip` was also absent — `sudo` needing an interactive password made the usual fix impossible mid-session.** Installing `python3-pip` via apt needs root; asking for a password non-interactively is a dead end (and shouldn't be worked around). The unblock: pip ships a **standalone zipapp** (`https://bootstrap.pypa.io/pip/pip.pyz`) that runs directly via `python3 pip.pyz install --target <dir> ...` with no system changes at all — no venv, no root, no PEP-668 externally-managed-environment block. Used to install the backend's requirements into `/tmp/wa-deps` for running `_tests/whatsapp_channel.py` and driving the FastAPI app via `TestClient` before ever deploying. `/tmp` does not survive a reboot; re-run the same command to rebuild it.
2. **`gcloud` is not on `$PATH` in this WSL shell, and the fix everyone reaches for (`export PATH=$PATH:~/google-cloud-sdk/bin`) fails with a bash syntax error** — the inherited `$PATH` carries Windows entries like `/mnt/c/Program Files (x86)/...` whose spaces and parentheses break unquoted expansion, and `~` does not expand inside a quoted assignment either. The reliable fix is calling gcloud by its absolute path every time: `~/google-cloud-sdk/bin/gcloud ...`. (Also saved to Claude's cross-session memory, since it recurs in every WSL shell regardless of project.)
3. **WhatsApp's "free" service-message window is not permanently free.** Meta's own pricing docs state per-message billing extends to service (guest-initiated) messages effective **2026-10-01** — this project's cost model (and D2's original "guest chat is free" framing) was costed on conversation-based pricing that predates that change. The 24h *rule* governing when a free-form send is allowed is unaffected; only the *cost* of using it changes. Flagged in `ROADMAP.md` D2 and the cost-telemetry backlog item for re-baselining before that date.

**Impact:** `services/task_queue.py` gained the `queue=` parameter (commit `bc143ef`); the regex fix and the secret re-creation both landed before any deploy, so neither reached staging in a broken state. `_tests/whatsapp_channel.py` (49 checks) now pins the regex behavior and the queue routing so a regression fails loudly offline instead of quietly in Cloud Tasks.

---

## Lesson: mcp-tool-manager skill does not affect Claude Code's MCP config
**Date:** 2026-04-15
**Status:** RESOLVED 2026-05-12 by the ag-switch Claude-sync extension. *(Promoted to `_global_lessons/lessons.md` 2026-07-21 as the "Claude Code's MCP registry lives in a different file than its settings" entry — see the index.)*

---

## Incident: FormatException: Invalid UTF-8 byte (at offset 41) — flutter run -d chrome
**Date:** 2026-04-14  
**Severity:** High  
**Component:** Flutter web / Chrome device launch  
**Status:** RESOLVED — 2026-04-14

### Root Cause (confirmed)
Flutter auto-detects `/mnt/c/Program Files/Google/Chrome/Application/chrome.exe` (Windows binary)
in WSL2. On German Windows 11 (CP1252 locale), Chrome emits a non-ASCII byte at **position 41**
of its startup stdout — almost certainly a German umlaut (ö/ü/ä = 0xF6/0xFC/0xE4 in CP1252,
invalid as a lone UTF-8 byte). Flutter reads Chrome's stdout via `_Socket._onData` and calls
`_Utf8Decoder.convertChunked` → FormatException → tool process crash. Byte offset 41 is
deterministic and reproducible (all 5 log files identical).

The crash has nothing to do with app source files or the missing `.env`. It occurs before the app
is even compiled.

### Fix Applied
1. **Immediate / WSL2 recommended:** Use `flutter run -d web-server --web-port 8080` via `run_dev.sh`.
   - Skips Chrome launch entirely — Flutter serves the built app on a local HTTP port.
   - Open `http://localhost:8080` in Windows Chrome manually.
   - Created `frontend/run_dev.sh` with this command.
2. **Permanent (enables `flutter run -d chrome`):** Install Google Chrome Linux native binary.
   - Download and install `google-chrome-stable_current_amd64.deb` from Google.
   - Flutter will then find `/usr/bin/google-chrome` (UTF-8 output) instead of the Windows binary.
   - Note: Ubuntu 24.04 snap-based Chromium will NOT work in this WSL env (snap unavailable).

### Bonus Bug Found and Fixed
`frontend/.env` had `SUPABASE_URL=https://inajlofycvmpitvljccy.supabase.co` but the anon key's
JWT `ref` field is `gcxxilzfhwlsjcvtpsvj` (matches CLAUDE.md `project_ref`). URL was wrong —
corrected to `https://gcxxilzfhwlsjcvtpsvj.supabase.co`.

### Fix Validation Checklist
- [x] Root cause identified — Windows Chrome CP1252 output in WSL2 pipe
- [x] `.env` file exists with corrected Supabase URL
- [ ] `flutter run -d web-server --web-port 8080` confirmed working (needs user validation)
- [ ] App loads at http://localhost:8080 in browser

---

## 2026-07-13 — 🔴 The prod website publicly served the `service_role` key (and a misdiagnosis on the way)
**Context:** Gate-2 testing. The founder signed up with a second email and saw a dashboard containing *another host's* properties, with "Email: —" and zero stats. *(The generalized lesson — never let a non-anon key reach a client bundle, rotate don't re-point, decode the credential a probe uses — was promoted to `_global_lessons/lessons.md` on 2026-07-21. This entry keeps the project-specific remediation record.)*

**Discovery:** `SUPABASE_ANON_KEY` on the prod Vercel project held the `service_role` key for ~1 day (only the new prod was affected; old prod and staging correctly shipped `anon`). Root cause: the cutover loaded six secrets by hand, and `anon`/`service_role` are both opaque JWTs that look identical at a glance.

**Impact:** guard added in `main.dart` — the app now **refuses to boot** if `SUPABASE_ANON_KEY` is a service_role JWT **or an `sb_secret_` key**, so a misconfigured deploy fails loudly instead of silently exposing the DB. `key_audit.py` (decode every deployed frontend's key) added to the checklist for any new environment.

**Remediation actually used (2026-07-14) — no JWT-secret rotation needed.** The project already had Supabase's new key system, which is independently rotatable: backend → **`sb_secret_`**, all frontends → **`sb_publishable_`**, then **Disable JWT-based API keys** in Supabase, which killed the exposed legacy `service_role` key outright. Verified after: RLS enforced (0 rows to an unprivileged key on all 8 tables), tenant isolation holds, host login, guest chat, guest realtime, ingest — all green. ⚠️ Do **not** revoke the "PREVIOUS KEY / Legacy HS256" under JWT Signing Keys: the backend still signs guest booking tokens with it.

**Three project-specific traps hit while remediating:**
1. **Vercel "Redeploy" reuses the build cache**, so the corrected env var never reached the bundle. Untick *Use existing Build Cache*, and make sure the var is set for the **Production** scope (Vercel scopes vars per environment).
2. **There are TWO Vercel projects** (`alwaysalfred` = new prod; `alfred-ingestor` = old prod + staging preview) pointing at **different Supabase projects**. A key from one is meaningless in the other — pasting the new prod's key into the old project 401'd the rollback stack. Always confirm the project name AND which Supabase project the key came from.
3. **The first guard missed `sb_secret_`** because it only decoded JWTs, and an `sb_secret_` key is not a JWT — one briefly reached a public deploy as a result.

**Wider point:** the "zero-delta parity" probe from the DB split has now missed three things — the `supabase_realtime` publication, `relrowsecurity`, and which credentials each environment actually ships. **Parity must compare switches and secrets, not just objects** (tables/policies/indexes).

---

## 2026-07-13 — Cloud Run BackgroundTasks freeze: resolution record
**Context:** Prod Telegram replies were flaky ("sometimes no answer, or 3 messages later, all stacked"). The webhook acks 200 immediately and runs all Gemini/DB work in FastAPI `BackgroundTasks`. *(The generalized "min-instances ≠ CPU-always-allocated" lesson was promoted to `_global_lessons/lessons.md` on 2026-07-21. This entry keeps the project-specific fix record.)*

**Discovery:**
1. **The freeze has misleading side-effects** that masquerade as other bugs: pooled HTTP/2 connections (supabase postgrest httpx) idle past keepalive and die with `ConnectionTerminated`, and `asyncio.sleep` retry backoffs stretch/burst, so quota errors exhaust their retries.
2. **Debugging trap (bit twice):** a conversation whose host has sent a message flips to `intervene` mode and Alfred stays silent BY DESIGN — a "frozen background task" probe (or realtime probe) on such a conversation is a false negative. Always probe a clean **autopilot** conversation.
3. **Verification method that needs no real Telegram client:** POST a crafted update to `/api/telegram/webhook` (with the real secret header, fake chat_id), then poll ONLY Supabase for the ai reply row — zero Cloud Run traffic, so a frozen task cannot be accidentally woken by your own polling.
4. **Tooling trap (how this entry originally got mangled):** appending markdown with backticks via a `wsl bash -c` heredoc command-substitutes the backticked phrases. Write files with the Write/Edit tools or a Python script instead.

**Impact:** First mitigated with `--no-cpu-throttling` (rev 00006, ~$55/mo stopgap — instance-based billing). **RESOLVED same day (rev 00007, commit `3a1d1e5`) with Cloud Tasks:** the webhook validates, enqueues and acks in ~150 ms; Cloud Tasks POSTs the payload back to `/api/telegram/process` as a fresh HTTP request with full CPU for its whole duration. Back to request-based billing (`--cpu-throttling`). Verified: reply row landed ~14s after the webhook with zero follow-up traffic. Cost: ~$55/mo → ~$12/mo (`min-instances=1`), or ~$0 with `min-instances=0` + an external keep-warm ping.

**Two traps hit designing the Cloud Tasks fix:**
1. **Do NOT just make the webhook synchronous.** Telegram serialises updates per chat — it does not send the next update until you answer the previous one. The album debounce (buffer photos of one `media_group_id` for 2s) would deadlock: photo 1 blocks waiting for siblings Telegram is holding back → the group flushes with one photo and each sibling arrives as a fresh group → one reply + one escalation notice PER PHOTO (the bug fixed in `c82b419`).
2. **An uptime ping does NOT substitute for the fix.** It keeps the instance warm but not the CPU allocated between requests.

**Album grouping without post-response CPU:** collect the group in memory, then schedule a single flush task **named after the `media_group_id`** (~3s delay). Cloud Tasks rejects a duplicate task name, so photos 2..N ride along instead of each firing their own reply. Verified: 3 photo updates → 3 fast acks → ONE worker run → ONE reply. The payload also carries the first photo as a `seed_items` fallback for resilience.

---

## 2026-07-17 — Cloud Build trigger + Vercel rename: resolution record
**Context:** Wiring the `deploy-prod-on-main` Cloud Build trigger (auto-deploy prod Cloud Run on push to `main`) and renaming the staging Vercel project. *(The generalized `--service-account` and `*.vercel.app` namespace lessons were promoted to `_global_lessons/lessons.md` on 2026-07-21.)*

**Discovery:** Applied here as `--service-account=<num>-compute@developer.gserviceaccount.com` on project `alfred-prod-502215` (no legacy Cloud Build SA existed), with `roles/run.admin` + `roles/iam.serviceAccountUser` and `options.logging: CLOUD_LOGGING_ONLY`. The GitHub↔Cloud Build host connection needed a separate `gcloud builds repositories create` step to actually link the repo. No safe dry-run existed since `cloudbuild.yaml` only reaches `main` at merge time. The obvious Vercel domain (`alfred-staging.vercel.app`) was already owned by an unrelated team; landed on `alwaysalfred-staging.vercel.app` instead.

**Impact:** Trigger live + validated on its first real fire (PR #4 → prod backend 00018 + scraper 00003). Staging frontend now `alwaysalfred-staging.vercel.app` (old domain 307-redirects). Captured in `CONTEXT.md` + `_tests/scenarios.md` section **N**.

---

## 2026-08-24 — Reflip's MCPs found active instead of the-ingestor's; fixed by retiring the shared mcp_config.json system
**Context:** Checking MCP config health this session found `supabase-reflip`/`higgsfield`/`sentry` active instead of the-ingestor's own servers — a prior session ran `ag-switch reflip` and nothing re-ran it since. First fix attempt (`ag-switch the-ingestor`) silently overwrote reflip's own live state without asking; user flagged it and it was reverted.
**Discovery:** The shared `mcp_config.json`/`ag-switch` compile step is deterministic and was never broken — the real gap is that nothing triggers it automatically on folder-open, so whichever project last ran it stays active indefinitely (a documented known limitation since 2026-03-01). Claude Code turns out to have a native fix: project-scoped `.mcp.json` + `.claude/settings.json`, auto-loaded per folder at session start, no shared file at all.
**Fix:** Built `_scripts/gen_mcp_json.py` to compile `.mcp.json`/`settings.json` per project from the same `_mcp_profiles/` source data `ag-switch` already used. the-ingestor now has its own gitignored `.mcp.json` (context7, github, supabase-the-ingestor, flutter, firecrawl-mcp) and committed `.claude/settings.json` with tool-level deny rules. Also closed a real gap this surfaced: `supabase-the-ingestor` had no tool-level gating at all in `global.json` — added the same branch/edge-function deny list `supabase-reflip` already had, since this project's backend is Cloud Run, not Supabase Edge Functions. Confirmed (not a bug): `supabase-scraper` intentionally shares the same project-ref/DB as `supabase-the-ingestor`. Gemini's `mcp_config.json` wiped clean at user's request — no longer feeds Claude Code either way.
**Impact:** the-ingestor's MCP/tool scoping is now fully automatic and isolated — opening this project folder always loads exactly its own MCPs, no manual switch step, no risk of another project's session leaving stale state behind.
**Global Candidate:** Yes — already promoted, see `_global_lessons/lessons.md` 2026-08-24 entry.
