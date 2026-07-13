# Project Lessons Log
_Discoveries logged here during sessions. Global candidates flagged for promotion._

---

## 2026-05-12 — ag-switch extended to write Claude Code settings.json (resolves the 2026-04-15 gap)

**Context:** Claude Code in the AG IDE had no access to the MCPs Gemini was using. `~/.claude/settings.json` was empty, so no MCP tools loaded into Claude Code sessions. The 2026-04-15 lesson flagged this as a permanent split between the two configs.

**Discovery:**
1. **Two separate config endpoints, one source of truth is achievable.** Gemini reads `/mnt/c/Users/San_8/.gemini/antigravity/mcp_config.json`. Claude Code reads `/mnt/c/Users/San_8/.claude/settings.json` (Windows side, not WSL home). The two are independent. But ag-switch can write to both in one pass, using `global.json` + `[project].json` as the single source.
2. **Format translation is required, not a copy.** Claude Code does not understand Gemini's `disabled` / `disabledTools` fields. The translation is:
   - `disabled: true` MCP → omit from `mcpServers` entirely
   - `disabledTools: [tool_a, tool_b]` → add to `permissions.deny` as `mcp__<server>__<tool>` (hyphens in server name → underscores)
3. **Path trap (three layers — don't skip any).**
   - Layer 1: First assumption was `C:\Users\San_8\.claude\settings.json` = `/mnt/c/Users/San_8/.claude/settings.json`. WRONG for VS Code WSL Remote — the extension reads the WSL home, not the Windows mount.
   - Layer 2: Wrote `mcpServers` to `~/.claude/settings.json` (WSL home). `claude mcp list` still returned empty. `settings.json` is for Claude Code *settings* (permissions, model prefs) — it is NOT the MCP registry.
   - Layer 3 (correct): The MCP registry is `~/.claude.json` (a flat file in WSL home, distinct from the `~/.claude/` directory). `claude mcp add-json <name> <json> --scope user` writes here. `claude mcp list` reads here. ag-switch STEP 3 must write `mcpServers` to `~/.claude.json` and `permissions.deny` to `~/.claude/settings.json` — two separate files, two separate roles.
   - Bonus: `claude mcp list` run from inside WSL shows "Failed to connect" for all `wsl`-routed servers (WSL-in-WSL). This is a false negative — the VS Code extension starts these servers from the Windows host where `wsl` works fine. Do not treat this as an error indicator.
4. **Refresh model differs.** Gemini supports mid-session "Hit Refresh" in the MCP panel. Claude Code does NOT — MCPs only load at session boot. After ag-switch, you must start a new Claude Code session for the config to take effect.
5. **Non-managed fields must survive.** `~/.claude/settings.json` already holds user preferences (`effortLevel`, `model`, `permissions.allow`, hooks, etc.). The Claude-sync step must merge only `mcpServers` and `permissions.deny`, leaving everything else verbatim.

**Impact:**
- `_scripts/ag-switch.sh` gained a STEP 3 that emits a Claude-flavored config to `/mnt/c/Users/San_8/.claude/settings.json` after every switch. Also added a `--quiet` flag (uses `exec >/dev/null` after the `--list` check) for use from hooks or scripts.
- `_scripts/new-project.sh` now calls `ag-switch --quiet [project]` at the end of Step 5 so new projects bootstrap a working Claude Code MCP config automatically, and the "Next steps" block now mentions starting a new Claude Code session.
- The 2026-04-15 lesson below is **resolved by this change**. Adding a Supabase MCP for a project no longer requires a manual edit to `~/.claude/settings.json` — running ag-switch propagates it to both sides.
- One pre-existing quirk surfaced and was **not** fixed in scope: ag-switch's STEP 2 controls per-tool allowlists but not per-MCP inclusion. Any MCP marked `disabled: false` in `global.json` leaks into every project regardless of whether it's listed in `[project].json`. Example: `supabase-scraper` showed up in the-ingestor's active MCPs even though it isn't in `the-ingestor.json`. Fix would be a one-line change in STEP 2 ("disable any server not in profile"). Flagged for a future task.

**Global Candidate:** Yes — this is the canonical pattern for any AG-managed machine. Promote the workflow, the path trap, and the format-translation rules to `_global_lessons/lessons.md`.

---

## Lesson: mcp-tool-manager skill does not affect Claude Code's MCP config
**Date:** 2026-04-15
**Component:** MCP / Tool Management
**Status:** RESOLVED 2026-05-12 — see the 2026-05-12 ag-switch extension lesson above
**Global Candidate: Yes**

### Finding
`mcp-tool-manager` edits `~/AG_master_files/_mcp_profiles/global.json`, which `ag-switch.sh` compiles into Gemini's config at `/mnt/c/Users/San_8/.gemini/antigravity/mcp_config.json`. It has no effect on Claude Code's MCP config, which lives in `C:\Users\San_8\.claude\settings.json` on the Windows host and is managed separately via the Claude Code MCP panel in the AG IDE.

### Impact
Invoking `mcp-tool-manager` from inside a Claude Code session to "activate" a Supabase server will appear to succeed (global.json is updated) but the tools will never appear in the current or any future Claude Code session — because the target config file is different.

### Fix / Required Setup Step
To make a Supabase (or any MCP server) available in Claude Code:
1. Open the Claude Code MCP panel in AG (Windows side)
2. Add the server entry manually — same format as global.json but written to `C:\Users\San_8\.claude\settings.json`
3. Restart Claude Code / click Refresh

This is a **one-time setup step per MCP server** — not something `mcp-tool-manager` can automate from the WSL side.

### Workaround used this session
Used the Supabase Management REST API directly (`api.supabase.com/v1/projects/{ref}/...`) with the access token from `global.json` to manage storage buckets and policies — fully equivalent to the MCP tool path.

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

## 2026-05-04 — Claude Code Shell Environment (Git Bash vs WSL2)

**Context:** Attempting to run `npx skills find` via Claude Code inside the-ingestor project.

**Discovery:** Claude Code launches in Git Bash (Windows) by default, not WSL2. 
Node, npm, and npx are installed in WSL2 only — invisible to Git Bash. All bare 
`npx`, `node`, `python` commands fail with "command not found" unless prefixed 
with `wsl bash -c`.

**Impact:** Added Section 9 (Shell Execution Environment) to root `CLAUDE.md` 
enforcing `wsl bash -c` prefix for all terminal commands. Added root `CLAUDE.md` 
inheritance pointer to `_template/CLAUDE.md` and the-ingestor `CLAUDE.md`.

**Global Candidate:** Yes — applies to every machine and every project.

---

## 2026-05-27 — MCP Config Path Migration & Stale Directory Cleanup
**Context:** The Antigravity IDE update moved the active App Data Directory, leaving deprecated and legacy configuration directories behind that needed to be cleanly decommissioned.

**Discovery:**
1. **Active Configuration Path:** The active `mcp_config.json` path is now `/mnt/c/Users/San_8/.gemini/antigravity-ide/mcp_config.json`. All referencing scripts (`ag-switch.sh`, `new-project.sh`, etc.) and system documentation have been successfully updated.
2. **Active Plugins Trap (Critical Safety Catch):** The legacy `.gemini/config/` directory is **NOT** fully legacy. While its `mcp_config.json` was migrated, the IDE actively loads core plugins (e.g., `android-cli-plugin`, `chrome-devtools-plugin`, `google-antigravity-sdk`, `modern-web-guidance-plugin`) and active project registration files directly from `.gemini/config/plugins/` and `.gemini/config/projects/`.
   - **Crucial Rule:** Never delete `.gemini/config/` wholesale, as this will immediately destroy active plugins and break IDE tools.
3. **Safe Cleanup Strategy:**
   - The deprecated `/mnt/c/Users/San_8/.gemini/antigravity/` folder contains historical logs/brain steps (referenced by utility scripts like `projects/scraper/decode.py`) and was safely **archived** to `/mnt/c/Users/San_8/.gemini/antigravity.archived-2026-05-27/`.
   - The legacy `mcp_config.json` and `.migrated` files inside `/mnt/c/Users/San_8/.gemini/config/` were safely **deleted**, leaving the active `plugins/`, `projects/`, and `sidecars/` subdirectories untouched.

**Impact:**
- Safely cleaned up all obsolete configuration files, reducing future developer confusion.
- Successfully prevented a catastrophic loss of active IDE plugins and project configuration records.
- Preserved historical brain step executions for past utility scripts like `decode.py`.

**Global Candidate:** Yes — the safety discovery regarding the `.gemini/config/` plugin path and the clean, selective decommissioning process applies directly to the entire AG ecosystem.

---

## 2026-07-13 — 🔴 The prod website publicly served the `service_role` key (and a misdiagnosis on the way)
**Context:** Gate-2 testing. The founder signed up with a second email and saw a dashboard containing *another host's* properties, with "Email: —" and zero stats.

**Discovery:**
1. **`SUPABASE_ANON_KEY` on the prod Vercel project held the `service_role` key.** Flutter compiles `.env` into the web bundle and serves it at **`/assets/.env`**, so the live site handed an omnipotent key — bypasses all RLS, can read/delete/rewrite any table, can reset any user's password via the admin auth API — to **every visitor**, for ~1 day. Only the new prod was affected; old prod and staging correctly shipped `anon` (verified by decoding all three bundles).
2. **Cause:** the cutover loaded six secrets by hand; `anon` and `service_role` are both long opaque JWTs that look identical at a glance, and nothing validated which one landed where.
3. **⚠️ Fixing the env var is NOT enough — you must ROTATE.** Vercel keeps every past deployment live at its own immutable URL, each still serving the old bundle. Legacy `anon`/`service_role` are both signed with the project JWT secret, so revoking one means rotating the secret (which also reissues the other, invalidates host sessions, and invalidates the guest booking JWTs → update `SUPABASE_SERVICE_ROLE_KEY` **and** `SUPABASE_JWT_SECRET`, redeploy backend, then fix the Vercel var). Runbook: `_Context/plans/prod-key-rotation.md`.
4. **🚨 THE DEBUGGING LESSON — I misdiagnosed this first.** My "is RLS enforced?" probe queried prod with what I *believed* was the anon key and got rows back from every table, so I declared "RLS is not enforced, P0 data leak" and had the founder run `ALTER TABLE ... ENABLE ROW LEVEL SECURITY` on prod. Harmless (idempotent), but **wrong**: the probe was using the leaked **service_role** key, which bypasses RLS *by design*. RLS was almost certainly fine all along. **Always verify which credential a security probe is actually authenticating as — decode the JWT — before concluding the database is open.** A probe that "proves" a catastrophic finding deserves more scepticism, not less.

**Impact:** guard added in `main.dart` — the app now **refuses to boot** if `SUPABASE_ANON_KEY`'s `role` claim isn't `anon`, so a misconfigured deploy fails loudly instead of silently exposing the DB. Add `key_audit.py` (decode every deployed frontend's key) to the checklist for any new environment (e.g. Phase-8 staging→Cloud Run).

**Wider point:** the "zero-delta parity" probe from the DB split has now missed three things — the `supabase_realtime` publication, `relrowsecurity`, and which credentials each environment actually ships. **Parity must compare switches and secrets, not just objects** (tables/policies/indexes).

**Global Candidate:** Yes — "never let a non-anon key reach a client bundle", "rotate, don't just re-point", and "decode the credential your probe is using" all generalise to every AG project on Supabase/Vercel.

---

## 2026-07-13 — Cloud Run BackgroundTasks freeze: min-instances does NOT keep CPU allocated
**Context:** Prod Telegram replies were flaky ("sometimes no answer, or 3 messages later, all stacked"). The webhook acks 200 immediately and runs all Gemini/DB work in FastAPI `BackgroundTasks`.

**Discovery:**
1. **Under Cloud Run request-based billing, CPU is throttled to ~0 the instant the response is sent.** Background work after the ack freezes and only resumes when the next request grants CPU — replies then flush "stacked". `min-instances=1` only keeps the *instance* alive; it does nothing about CPU between requests. The needed flag is `--no-cpu-throttling` (annotation `run.googleapis.com/cpu-throttling: false`).
2. **The freeze has misleading side-effects** that masquerade as other bugs: pooled HTTP/2 connections (supabase postgrest httpx) idle past keepalive and die with `ConnectionTerminated`, and `asyncio.sleep` retry backoffs stretch/burst, so quota errors exhaust their retries.
3. **Debugging trap:** a conversation whose host has sent a message flips to `intervene` mode and Alfred stays silent BY DESIGN — a "frozen background task" probe on such a conversation is a false negative. Probe on a clean autopilot conversation.
4. **Verification method that needs no real Telegram client:** POST a crafted update to `/api/telegram/webhook` (with the real secret header, fake chat_id), then poll ONLY Supabase for the ai reply row — zero Cloud Run traffic, so a frozen task cannot be accidentally woken by your own polling.
5. **Tooling trap (how this entry originally got mangled):** appending markdown with backticks via a `wsl bash -c` heredoc command-substitutes the backticked phrases. Write files with the Write/Edit tools or a Python script instead.

**Impact:** Root cause fixed with one flag (rev 00006); Gate-2 P-8 probe shows replies in ~15s with zero follow-up traffic.

**⚠️ The flag is a STOPGAP, not the answer — it costs ~$55/mo (2026-07-13 founder decision: mitigate, don't accept).** `--no-cpu-throttling` switches Cloud Run to **instance-based billing**: the container is billed 24/7 whether or not a single message arrives. That charge is unrelated to traffic — a Gemini reply burns ~15 vCPU-seconds against a 180,000 vCPU-s/month free tier, so the *work* is effectively free; you are paying purely to keep an idle CPU switched on. (Also note `europe-west3`/Frankfurt is **Tier 2** pricing, ~20–25% above the headline Tier 1 rates.)

**The correct fix is to do the work INSIDE a request, then go back to request-based billing** (~$10–12/mo with `min-instances=1`; ~$0 with `min-instances=0`, since Cloud Run does **not** charge for idle instances that aren't minimum instances — so an external 5-min ping, e.g. UptimeRobot, buys warmth for free).

Two traps when designing that fix:
1. **Do NOT just make the webhook synchronous.** Telegram **serialises updates per chat — it does not send the next update until you answer the previous one.** The album debounce (buffer photos of one `media_group_id` for 2s) therefore deadlocks: photo 1 blocks waiting for siblings Telegram is holding back until photo 1 responds → the group flushes with one photo and each sibling arrives as a fresh group → one reply + one escalation notice PER PHOTO, i.e. the exact bug fixed in `c82b419`.
2. **An uptime ping does NOT substitute for the fix.** Pinging keeps the *instance* warm but not the *CPU* allocated between requests; each ping would merely lurch the frozen background task forward, so replies would still arrive minutes late and stacked. It is only useful *after* the work moves inside a request.

**RESOLVED same day (rev 00007, commit `3a1d1e5`) — Cloud Tasks.** The webhook validates, enqueues and acks in ~150 ms; Cloud Tasks POSTs the payload back to `/api/telegram/process` as a **fresh HTTP request**, which therefore gets full CPU for its whole duration (and no 60 s Telegram ceiling). The service went back to request-based billing with `--cpu-throttling`. **Verified under throttling: reply row landed ~14 s after the webhook with ZERO follow-up traffic** — the exact condition that used to freeze it. Cost: **~$55/mo → ~$12/mo** (`min-instances=1`, billed at the 10×-cheaper idle rate), or **~$0** with `min-instances=0` + an external keep-warm ping. Cloud Tasks itself is free (1M ops/month).

**Album grouping without post-response CPU:** collect the group in memory, then schedule a single flush task **named after the `media_group_id`** (~3 s delay). Cloud Tasks rejects a duplicate task name, so photos 2..N ride along instead of each firing their own reply. Verified: 3 photo updates → 3 fast acks → **ONE** worker run that pulled all 3 file_ids → **ONE** reply. The payload also carries the first photo as a `seed_items` fallback, so if the flush ever lands on an instance that doesn't hold the buffer the guest gets a degraded answer rather than silence.

**Debugging trap that bit twice:** a conversation whose host has replied is in `intervene` mode and Alfred stays silent BY DESIGN — both a "frozen task" probe and a realtime probe on such a conversation return false negatives. Always probe a clean **autopilot** conversation.

**Global Candidate:** Yes — "min-instances ≠ CPU-always-allocated" applies to every Cloud Run service in AG that does post-response background work.
