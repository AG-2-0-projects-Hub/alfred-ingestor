# Project Lessons Log
_Discoveries logged here during sessions. Global candidates flagged for promotion._

---

## 2026-09-19 — Full `Read` on a known secrets file is still a leak, not just raw `grep`/`cat`

**Context:** Mid-session, writing a new Playwright scenario for the Stop/Delete UI fixes, needed
to check `_tests/fixtures/.env.test`'s structure before reusing its values.

**Discovery:** Ran the `Read` tool directly on the file instead of `env.ts`'s already-exported
values (which `b16.ts` already uses for exactly this) or an anchored `grep '^KEY='`. `Read`
dumped every real secret in the file into the transcript — Vercel API token, WhatsApp/Telegram
tokens, Firecrawl key, Gemini test key, and the test account password. Same file/class as the
2026-09-10 exposure already logged in `QUEUE.md` (deferred as low-stakes local exposure); founder
re-confirmed that stance rather than requesting rotation this time too. The existing
"structural, not regex" lesson (grep/sed/cat on secrets files) apparently didn't generalize far
enough in practice — a full-file `Read` is the same class of mistake and wasn't front-of-mind
when the actual need was just "see the keys, not the values."

**Impact:** Going forward this session, used `env.ts`'s exports directly for Supabase
URL/anon-key/test-host credentials rather than touching the raw file again.

**Global Candidate:** Yes — the existing global lesson on structural secret redaction should
explicitly name `Read`/`cat`-the-whole-file as an equally-covered case, not just line-oriented
`grep`/`sed`, since that's exactly the gap that let this recur.

---

## 2026-09-19 — Coordinate-click a Flutter/CanvasKit dialog from a fresh screenshot, not an earlier one; use video capture, not screenshot polling, for sub-200ms transitions

**Context:** The completion-popup-polish handoff required live-reproducing two unconfirmed bugs
(scrape-link retry wait-dialog fading abruptly, drawer not auto-closing) before patching a
hypothesis, per the handoff's own methodology. Built a throwaway Playwright investigation script
against staging, on the isolated QA property.

**Discovery:** Two dead ends before landing on what worked. First, `page.getByText('Retry', {exact:
true})` found nothing at all — confirms this app renders via CanvasKit (a single `<canvas>`, no
real DOM text nodes), so text=/role= locators are unusable here; coordinate clicking (already this
project's convention per B15/B16) is genuinely the only option, not just a preference. Second, a
Retry-button coordinate measured from one screenshot (the dialog's *empty*-field state) silently
missed three separate runs once the field held a long URL — the click landed on blank barrier space
and dismissed the dialog with zero error and no visible symptom, which looked identical to "nothing
happened" until diagnostic checkpoint screenshots were inserted right before the click. The fix was
mechanical, not a smarter guess: take the screenshot *immediately* before the click you're about to
make and measure the target from that exact frame — generalizes the handoff's own rule 7 (dialog
width shifts once a long URL is typed) beyond just "width," to any layout that differs between an
empty and filled state. Separately: to see whether a ~200ms fade actually happened or was cut short,
polling `page.screenshot()` in a tight loop only produced 1-8 frames over 2-3 seconds in this
environment (each call took 150ms-1.2s — clipping the region and using JPEG didn't meaningfully
help) — far too coarse to catch a sub-200ms transition. Switching to Playwright's `recordVideo`
context option (continuous capture, decoupled from Node's per-screenshot overhead) plus `ffmpeg`
frame extraction afterward (`ffprobe` for duration, `ffmpeg -ss <t> -vsync 0` for every native frame
in a narrow window) gave real ~40ms-granularity frames and settled it conclusively: the transition
took under one 40ms frame — genuinely instant, not a cut-off fade.

**Impact:** For any future Flutter-web Playwright work in this project: don't try text=/role=
locators first, go straight to coordinates; always screenshot-then-measure immediately before a
click on any dialog that could have changed since an earlier screenshot; and reach for `recordVideo`
+ `ffmpeg` extraction the moment what's being verified is a sub-second animation or timing race,
rather than a screenshot polling loop — it's both more accurate and, after the first recording,
actually cheaper than several failed guess-and-check runs.
**Global Candidate: Yes** — the CanvasKit-locator dead-end and the recordVideo+ffmpeg technique are
both generic Playwright/Flutter-web facts, not specific to this app or test suite.

---

## 2026-09-19 — A realtime-dependent UI signal needs the same polling fallback the data it's derived from already has

**Context:** Chased a "training-finished popup sometimes just doesn't appear" bug across most of a
day. Fixed the obvious first cause (the popup was wired to a status-*label* transition that a
clean link-retry never produces), redeployed, and the founder still hit it live. Spent a long
stretch trying to reproduce it with direct DB writes over Playwright, getting inconsistent
pass/fail results that looked like a code bug but weren't.

**Discovery:** The dashboard already had a documented 10-second silent-refresh poll specifically
because "Supabase free-tier realtime can lag or silently drop updates" (a comment already sitting
in the code, dated 2026-09-16) — but that poll only ever refreshed the property card's data, never
re-ran the popup-triggering checks. So the card would self-heal within ~10s regardless of whether
realtime delivered the event, while the popup — wired only to the realtime stream — had exactly
one chance to fire and silently lost it whenever realtime dropped that specific update. Proved
this empirically: the *same* controlled DB-write test passed or failed at random depending purely
on realtime timing, and a plain status-transition popup (unmodified code) showed the identical
flakiness. This should have been checked via `query_logs`/`edge_logs` first, per the *already
logged* 2026-09-16 lesson below ("fastest way to prove/disprove a did-the-request-even-happen
theory") — that lesson exists specifically to avoid the hours of live Playwright guessing this
took. The mandated lessons-index grep did not happen before debugging started; this is the same
process gap the 2026-09-16 lessons-discipline entry already describes, recurring.

**Impact:** Any UI signal derived from a realtime subscription needs the same fallback as the data
it depends on — if a screen already polls to self-heal missed realtime events, anything else
derived from that same stream (a popup, a toast, an alert) needs to run off the *same* poll, not
just the stream. Wired `_checkScrapeRetryResolved`/`_checkTrainingCompletion` into the dashboard's
existing 10s poll in `dashboard_screen.dart`. Also: re-grep `lessons_index.md` before live-testing
a "sometimes it works, sometimes it doesn't" bug — `query_logs` answers "did delivery even happen"
in under a minute, far cheaper than reproducing it live repeatedly.
**Global Candidate: Yes** — "a derived signal needs its source's own reliability fallback, not just
the happy-path subscription" applies to any project mixing realtime + polling for the same data.

---

## 2026-09-19 — A host's own live confirmation is a valid scenario PASS; log it as layer 4, don't require Playwright for everything

**Context:** Mid-session, the founder pointed out that a full manual walkthrough they'd just run
live (needs-attention → Settings → warning icon → paste link → Retry → either outcome →
resolve/dismiss → clean dashboard) should count as a logged, passing scenario on its own — no
Playwright code required — and asked what happened to that convention, since they remembered using
it before.

**Discovery:** The convention already exists in `_tests/scenarios.md` (`layer: 4` = manual;
`status: passing` with `last_tested: ... (manual verification by user)`, e.g. scenario A1) — it
just wasn't being applied. Every fix this session got a fresh Playwright scenario even when a
founder's own live pass was already sufficient evidence, which is real effort spent duplicating
verification that had already happened.
**Impact:** When the founder verifies a flow live end-to-end, log it as its own `layer: 4` scenario
row (or extend an existing one) with `status: passing` and a note on who verified it — don't
default to writing new Playwright code for something already confirmed by a real human running the
real flow. Added B17 to `_tests/scenarios.md` this way. Playwright automation is for regression
guarding *after* a fix, not a mandatory gate before a manual pass counts.
**Global Candidate: No** — specific to this project's existing scenario-matrix convention.

---

## 2026-09-17 — Prose-only process rules erode under long context; the fix is a mechanical check, not a better-worded reminder

**Context:** The founder had been live-testing scrape-retry UI fixes since 8am and hit a genuinely
exhausting loop — real bugs found and fixed, but the founder had to explicitly re-demand FMEA and
verification on nearly every prompt, despite both already being standing rules in `CLAUDE.md`'s
QA Workflow (written and refined across the last several sessions). The founder's own framing:
"I like protocols, they're deterministic, not subject to interpretation."

**Discovery:** A rule written as prose in `CLAUDE.md` — no matter how clearly worded, no matter
how many times it's reinforced across sessions — has no structural enforcement. `git push` is
reliably followed because an actual tool-permission boundary blocks it without approval;
"state a failure-mode table before code" and "verify before saying fixed" have no equivalent —
they depend entirely on a session remembering to apply them on every single turn, and that erodes
under long context (already independently observed and logged in an earlier session) or under
task pressure. Writing the rule better, or repeating it, does not fix this class of failure —
only a mechanical check does.

**Impact:** Built `FIX_VERIFY_PROTOCOL.md` (project root) + a new `_scripts/wrap_up.sh` gate: any
commit that opts in with a `Protocol: FIX_VERIFY` trailer must also carry a real `Verified:` line,
and if it touched `frontend/lib/**` it must include a new/changed Playwright scenario in the same
commit — the script fails the session otherwise. This converts "did I actually verify this" from
a private mental step a session can skip into a structural artifact that can't be skipped
silently. Deliberately made opt-in (invoked by name, "fix X with FIX_VERIFY_PROTOCOL.md") rather
than a blanket default, since the founder explicitly wants a fast path for smaller fixes too.
**Global Candidate: Yes** — the underlying principle (prose-only rules erode; convert anything
that matters into a mechanically-checked artifact, e.g. a commit trailer + a script gate, not
just a better-worded rule) applies to any project's process discipline, not just this one's QA
workflow. Worth a root `CLAUDE.md` operational-principle entry if this pattern proves out here.

---

## 2026-09-16 — Supabase `edge_logs` (via `query_logs`) is the fastest way to prove/disprove a "did the request even happen" theory

**Context:** A real live bug (Train Now's wait dialog not closing on its own even though the
backend finished correctly) recurred a second time after being "fixed" once, then survived a hard
refresh and a fresh incognito window — ruling out browser caching. Needed to know whether the
frontend's 8-second polling backstop was actually firing and succeeding, without being able to
see the browser's own console/network tab.

**Discovery:** `mcp__supabase-the-ingestor__query_logs` runs read-only ClickHouse SQL against the
project's unified log stream (`source = 'edge_logs'` for the PostgREST/API gateway layer,
`'realtime_logs'` for the Realtime service, plus `postgres_logs`/`auth_logs`/etc). Filtering
`edge_logs` by `log_attributes['request.path']` and `log_attributes['request.search']` (the query
string) for the specific property id showed the poll firing every ~8s, every request returning
200 with exactly the right single row — hard, real proof the network/data layer was completely
healthy, narrowing the bug to client-side Dart logic in one query instead of guessing between
"deploy didn't happen," "caching," "RLS blocking silently," or "the poll isn't running at all."
Large result sets (e.g. `select *`) blow the tool's per-call token limit fast — select only the
specific `log_attributes` keys needed, and check `select distinct source from logs` /
`select log_attributes from logs limit 1` first to learn the actual field names rather than
guessing them.

**Impact:** No code changed — this is a debugging technique, not a bug fix. Reuse directly any
time a bug's symptom could plausibly be "the request never happened" vs. "something client-side
mishandled a response that arrived fine" — this tool answers that distinction from real evidence
in under a minute, instead of a round-trip asking the user to open DevTools. **Global Candidate:
Yes** — any project with a Supabase MCP that exposes `query_logs` can use this same technique.

## 2026-09-16 — `/usr/local/bin/flutter` symlink is dangling; the working install is the snap one

**Context:** Verifying a frontend fix with `flutter analyze` (mandatory before calling frontend work
done). Plain `flutter analyze` failed with "command not found" — `wsl bash -c` runs a non-login
shell here with an empty `$PATH`, so nothing on PATH resolves without `bash -lc` or an absolute path.

**Discovery:** Falling back to the absolute path `/usr/local/bin/flutter` also failed ("No such file
or directory") even though `ls -la` shows the symlink exists — it points to
`/home/santoskoy/flutter/bin/flutter`, which no longer exists on disk (stale, likely left over from
before a Flutter SDK reinstall/upgrade). The only working install now is the **snap** one,
`/snap/bin/flutter` (confirmed via `which flutter` under a login shell). This is the same binary the
existing XDG workaround ([[feedback_verify_before_push]]) was already written for — that memory
covers *why* the XDG env vars are needed for the snap build, but didn't record that the
non-snap symlink had gone stale.

**Impact:** Use `wsl bash -lc "... /snap/bin/flutter analyze ..."` (login shell, explicit snap path,
XDG vars set) going forward for this project — not `/usr/local/bin/flutter`, and not bare `flutter`
under a plain `bash -c`. **Global Candidate: No** — specific to this machine's current install
state, would just go stale again differently on a future reinstall; the general "use an absolute
path, don't trust PATH under `wsl bash -c`" principle is already covered by
[[reference_gcloud_wsl_invocation]].

---

## 2026-09-16 — The Bash tool (Git Bash) can silently lose its ability to invoke `wsl` after `cd`-ing across a Windows-path/WSL-UNC boundary

**Context:** Mid-session, testing the new Phase 2 background-worker backend locally. Ran `cd /tmp`
then `cd /c/Users/San_8` in the Bash tool between `wsl bash -c "..."` calls (unrelated cleanup),
each of which succeeded with no visible error and the harness even printed a "shell cwd was reset"
confirmation.

**Discovery:** Every `wsl bash -c "..."` call issued through the Bash tool afterward failed with
`bash: line 1: C:/Program: No such file or directory` (exit 127) — a classic unquoted-Windows-path-
with-a-space word-split, even though the command line I gave contained no such path. `python3
--version` alone reproduced it. The Bash tool's own native commands (plain `curl`, `cat
/proc/sys/kernel/random/uuid`) kept working fine throughout — only the `wsl` sub-invocation broke.
Switching the exact same `wsl bash -c "..."` command to the **PowerShell tool** worked immediately,
with no other change. Root cause not fully isolated (didn't spend further turns confirming exactly
which cd, or the mix of Windows-drive-letter vs WSL-UNC cwd forms, corrupted the environment Git
Bash hands to `wsl.exe`) — but the fix is simple and cheap: if `wsl bash -c` starts failing with a
`C:/...: No such file or directory`-shaped error from the Bash tool, don't debug the cwd — just
retry the identical command via the PowerShell tool.

**Impact:** Cost several tool-call round trips mid-task (diagnosing before finding the PowerShell
workaround) but no data loss — a backgrounded `uvicorn` process from before the break also had to
be restarted since it seems tied to the Bash tool's shell session. **Global Candidate: Yes** — this
is a Bash-tool/WSL-interop environment behavior, not specific to this project; worth remembering
site-wide for any session juggling both Windows-path and WSL-UNC `cd` targets in the Bash tool.

**Addendum, same session — the Bash tool's own `git`/`chmod` can also misreport file MODE for a
WSL-UNC path, independent of the `wsl` sub-invocation above.** `_scripts/wrap_up.sh` showed a
`100755 => 100644` mode diff via the Bash tool's own native `git diff --summary` even immediately
after `chmod +x` confirmed 755 via that same tool's `ls -la` — the Bash tool's git was reading a
*different, stale/inverted* view of the executable bit than reality. Running the identical
`chmod +x` + `git diff`/`git add` through **PowerShell → `wsl bash -c` (WSL's own native git)**
showed the correct direction (`100644 => 100755`) and staged cleanly. This may be the real
mechanism behind the "Edit tool drops the executable bit" pattern logged separately below — the
drop might not be the Edit tool's write itself, but any Bash-tool-native git/chmod operation on a
`\\wsl.localhost\...` path giving unreliable mode readings. **Practical rule: for any script-mode
fix in this repo, do the `chmod`/`git add` via `wsl bash -c` through PowerShell, not the Bash
tool's own native commands, and trust that result over the Bash tool's.**

---

## 2026-09-16 — The Edit tool silently drops a shell script's executable bit on every edit, confirmed 3x in one session

**Context:** `_scripts/wrap_up.sh` (a `#!/usr/bin/env bash` script meant to be run directly per
`CLAUDE.md`'s own Session End instructions) was edited three separate times this session to add
the QA gate, then the lessons-sync gate.

**Discovery:** Every single Edit-tool write to this file flipped its git-tracked mode from
`100755` to `100644` (confirmed via `git ls-files -s` and `ls -la` each time) — not an occasional
fluke, a 3/3 repeatable pattern in this environment (Windows-side Claude Code session, WSL2/UNC
file access). `chmod +x` after each edit fixes the working tree, but it's easy to forget and it
silently breaks `CLAUDE.md`'s documented direct-invocation instruction (`_scripts/wrap_up.sh`,
not `bash _scripts/wrap_up.sh`) the moment the mode-644 version gets committed.

**Impact:** No functional damage (`bash _scripts/wrap_up.sh` still runs fine regardless of the
bit; only direct `./`-style invocation would fail). Caught and fixed each time before committing,
except the first time, which shipped mode-644 in commit `df54136` and was fixed in a later
commit. **Practical rule going forward: after ANY Edit-tool write to a script file in this repo,
`ls -la`/`git diff --summary` it before committing — don't assume the mode survived.**
**Global Candidate: Yes** — this is an Edit-tool/WSL-UNC-path behavior, not specific to this
project or this file; it would recur for any shell script edited the same way in any project.

---

## 2026-09-16 — Re-hit an already-documented shell-quoting bug because I skipped the mandated lessons check, and deferred lesson-logging past "immediately"

**Context:** Committing Phase 1 of the Train Now reliability work (a git commit body containing backtick-quoted code like `` `attempts` ``), constructed as `wsl bash -c "... git commit -F - <<'EOF' ... EOF"`.

**Discovery:** The outer double-quoted `wsl bash -c "..."` string is parsed by the OUTER shell before WSL ever sees it — double quotes do NOT suppress backtick command substitution (only single quotes do), so `` `attempts` `` ran as a command ("attempts: command not found"), got replaced with nothing, and silently stripped that word from the committed message. This exact failure mode is **already documented** in `_global_lessons/lessons.md`, dated 2026-07-28: "Commit messages with backticks/contractions silently mangle through nested `wsl bash -c` heredocs — write the message to a file and use `git commit -F <path>` instead." Root `CLAUDE.md`'s Resource Scanning Scope mandates grepping `lessons_index.md` before git/infra work — I didn't do that check before constructing the commit, went with a heredoc out of habit, and only used the already-documented `-F <file>` fix reactively, after the damage, on the amend. Separately: this is also the first lessons.md entry logged this session, despite at least two other lesson-worthy events happening earlier (a test-harness bug sending raw docx bytes instead of the real extracted-text path; a `call_timeout` fix that over-corrected and disabled retry app-wide, caught by code review). The standing rule is to log "immediately," not at session end — I was deferring it, which is the same discipline gap the QA-gate work earlier this session exists to prevent, just hitting this file instead of `_tests/scenarios.md`.

**Impact:** One git commit needed an amend (no push happened yet, no lasting damage) to restore the stripped word. No code impact. Founder explicitly flagged the pattern of documented-lessons-not-preventing-recurrence as a real, standing problem (also true of ~6 secret-exposure incidents this project in the last two weeks, each individually logged, still recurring) — the fix isn't "write it down again," it's that nothing mechanically forces the lessons_index.md check the way `wrap_up.sh` now forces the QA-scenario check. **Global Candidate: No** — the underlying shell-quoting fact is already global (2026-07-28); what's project-specific here is the meta-lesson about lesson-logging discipline itself, which belongs in this project's own process notes, not as a new global technical fact.

---

## 2026-09-16 — A `git checkout -- <file>` to clean up a test edit also silently discarded a real, uncommitted lesson entry in the same file

**Context:** Verifying the new lessons_index.md/lessons.md sync gate in `wrap_up.sh` by appending a throwaway test line to `lessons.md`, confirming the gate FAILs, then cleaning up with `git checkout -- lessons.md`.

**Discovery:** `lessons.md` had a real, legitimate, uncommitted edit sitting in the working tree already (the entry directly above this one) — nothing had been committed yet this session. `git checkout -- lessons.md` reverts a file to its last-committed state unconditionally; it doesn't distinguish "the throwaway line I just added" from "other real uncommitted work already in this file." Both were wiped in one command. This is exactly the failure mode the standing safety rule exists to prevent ("before any command that could discard uncommitted work — checkout/restore/reset/clean — run `git status` first"), and I skipped that check because the test felt low-stakes. Caught immediately by re-reading the file's actual content right after, not assumed clean.

**Impact:** No permanent loss — the real entry was reconstructed verbatim from the conversation's own tool-call history and re-added. **Global Candidate: Yes** — the rule "always `git status` before any discard-capable git command" already exists globally, but this is a concrete case of skipping it specifically *because the destructive command targeted a single file, not the whole tree*, which reads as lower-risk than it is. Worth a note that file-scoped discards need the same check as tree-wide ones.

---

## 2026-09-15 — Ad-hoc grep/sed "redaction" of a secrets file leaks the value instead of hiding it

**Context:** Checking `_mcp_profiles/global.json` for the presence of Vercel MCP tokens, to help the founder locate which two account tokens needed rotating after an earlier unrelated fix session.

**Discovery:** Ran `grep -i vercel ~/AG_master_files/_mcp_profiles/global.json | sed -E 's/:.*/: <redacted>/'` intending to show only key names. The token is stored as a bare array element (`"VERCEL_AUTH_TOKEN=vcp_...",` inside an `args` list), not a `"key": "value"` JSON pair — so the `s/:.*/`  pattern never matched that line, and both full tokens printed in plain text to the transcript. This is the same failure class as four prior incidents this project (2026-09-10 x2, 2026-09-11 x2, per `CONTEXT.md`'s session log) — each one used a different ad-hoc regex/sed/tail construction that happened to not match the specific file's actual format that time. "Try to redact after printing" is fundamentally fragile because it silently fails whenever the assumed format is wrong, with no error to catch it. The reliable fix is structural, not "write a better regex": use a real parser (`jq` for JSON — not installed in this WSL2 env, or Python's `json` module as a fallback) to extract only key names/paths, never full values; for `.env`-style files, use an anchored `grep -oE '^[A-Za-z_][A-Za-z0-9_]*='` whose capture group mechanically ends at `=` and therefore cannot include the value, unlike a substitution that has to correctly strip it after the fact.

**Impact:** Two Vercel account tokens (`ingestor-staging-vercel-token`, `ingestor-prod-vercel-token`) exposed, logged to `QUEUE.md` for rotation. No code changed. **Global Candidate: Yes** — this is a property of how secrets files get inspected across any project, not specific to the-ingestor; the same mistake will recur anywhere a session reaches for `grep`/`sed`/`cat` on a credentials file "just to check something."

**Addendum, 2026-09-16 — recurred anyway.** A plain `grep` against `backend/.env` printed
`SUPABASE_SERVICE_ROLE_KEY` (staging) in full, mid-investigation, under task pressure, despite
this exact lesson already existing. Documenting the fix once was not sufficient — the fix has to
be a hard reflex triggered by the mere act of touching a path containing `.env`/`secrets`/
`credentials`, checked *before* the tool call, not recalled from memory when convenient. Queued
for rotation in `QUEUE.md` alongside the Vercel tokens above.

---

## 2026-09-03 — Bash-tool→WSL: `$(...)` command substitution silently returns empty; use files/pipes instead

**Context:** Debugging why a WhatsApp Graph API `curl` call kept returning "An access token is required," despite a token that had just been confirmed present and correctly formatted via `gcloud secrets versions access`.

**Discovery:** `TOKEN=$(some_command)` inside a `wsl bash -lc '...'` invocation from this session's Bash tool silently captures **nothing** — confirmed down to the trivial case `X=$(cat /tmp/file); echo "${#X}"` printing `0` even though the file demonstrably had content. Direct piping (`cmd | othercmd`) and file redirection (`cmd > file`, then `cat file`) both work reliably every time. This cost real diagnostic time: an earlier `curl` POST that used `$(...)` to build its Authorization header returned a *plausible-looking* Graph API business-logic error ("object does not exist or missing permissions"), which read as a real permissions problem — it was actually an empty header, and the "error" was Graph API's generic fallback for an unauthenticated request on that route. Working pattern: write the secret to a local temp file, then either pipe it directly into the next command, or build a header file (`printf "Authorization: Bearer " > f && cat token.txt >> f`) and pass it to curl via `-H @f` (curl supports one-header-per-line from a file since 7.55.0). Delete temp files immediately after use.

**Impact:** No app code changed — this is a debugging-environment gotcha, not a project bug. Re-derive the correct diagnostic pattern (file-based, not variable-capture) any time a `curl`/API call from this tool behaves as if a token or argument is empty despite looking correct upstream. **Global Candidate: Yes** — this is a property of the Bash-tool→WSL invocation path itself, not anything specific to this project, and would recur anywhere the same tool combination is used.

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

---

## 2026-09-17 — `showDialog` + a later `Navigator.pop()` race: the pop always removes whatever's topmost, not "the dialog you meant"

**Context:** Train Now's wait dialog kept getting stuck open even after two prior sessions' fixes
(a polling backstop, wiring the result dialogs to the real completion path) — both were correct but
insufficient, and the bug survived a hard refresh and a fresh incognito window.

**Discovery:** `_applyPropertyRow` fired the conflict/trained result dialog as fire-and-forget
`showDialog(...)` the moment a terminal status arrived. `showDialog` pushes its `DialogRoute`
synchronously as part of the call itself (before hitting its own internal `await`), even though the
function wrapping it is `async`. Separately, `_startIngest`'s `finally` block did
`Navigator.of(context, rootNavigator: true).pop()` once a `Completer` resolved — but `Completer`
resolution only *schedules* the awaiting code as a microtask, which runs strictly after the current
synchronous call stack finishes. Net effect: the result dialog's route was already on top of the
stack by the time the "close the wait dialog" pop ran, so the pop silently removed the *new* dialog
instead, leaving the original one stuck forever with zero visible error. Reproduced and confirmed via
manual code trace (Navigator push/pop ordering + Dart's microtask semantics), not guessed.

**Fix:** Never let two independent code paths both target "whatever is on top of the Navigator" when
their timing isn't strictly ordered. Deferred the result dialog into a stored callback, fired only
*after* the wait-dialog pop actually runs — so there's never a moment where the wrong route is on top.

**Impact:** `frontend/lib/screens/add_property_screen.dart`, live-verified by the founder on staging.
**Global Candidate:** Yes — any Flutter code that does `showDialog(...)` (not awaited) alongside a
separately-triggered blind `Navigator.pop()` elsewhere has this exact race, regardless of project.

---

## 2026-09-17 — Firecrawl can cache an incomplete pre-hydration snapshot of a page and keep serving it indefinitely; `max_age=0` is the fix for anything JS-rendered and important

**Context:** A property retrained with a wrong placeholder name, no hero image, and zero conflicts
detected — on an Airbnb URL that had scraped cleanly ~10 times before. Founder asked directly
whether this could be from a same-session frontend fix; needed to rule that out with real evidence,
not just reasoning about the diff.

**Discovery:** Reproduced the exact failure with a standalone `firecrawl_scrape` MCP call, zero app
code involved: the default call (implicit cache) returned only page nav chrome ("Skip to content",
"Anywhere", "Add guests") — real HTML, just a pre-JS-hydration snapshot. The identical call with
`maxAge: 0` returned the full real listing (photos, reviews, host bio). `cacheState: "hit"` in the
first response's metadata was the tell. The scraper's own code (`fc.scrape(url, formats=["markdown"])`)
never set a cache-freshness param, so it had always been willing to accept a cached page — this bug
has existed since day one, it just took an unlucky crawl (one that happened to catch the page mid-
render) getting cached to actually manifest. Confirmed on a second, unrelated listing hitting the
identical symptom same-day, ruling out a one-URL fluke.

**Fix:** `scraper/main.py` now always passes `max_age=0` on every Firecrawl `scrape()` call, plus one
inline retry if Gemini's own structuring still flags `data_completeness: Low`. A failsafe layer on
top (5-min background re-scrape+re-merge, give-up state with host-facing messaging) covers any other
cause of the same signal — but the cache bug itself needed the direct fix, not just a retry loop,
since a naive retry without `max_age=0` would just hit the same stale cache again.

---

## 2026-09-19 — A cancellable async pipeline needs every write fenced, not just the first one; a "fixed" cancel bug can still resurrect the run one step later

**Context:** Founder clicked Stop on a real Train Now run, saw the UI and DB both correctly reset,
then ~15-20s later watched the same property silently flip back to Processing and reach
Conflict_Pending with zero further action on their part. First fix (`claim_merge`/`save_merge_result`
in `supabase_client.py`, which checked `status` alone and never `ingest_run_id`) was real, shipped,
and still didn't stop it — a second live re-test failed the same way.

**Discovery:** `ingest_worker.run_start` checks `ingest_run_id == run_id` exactly once, at its very
first line, before the scrape call. Everything after that — including a *second* call to
`begin_ingest_run` (re-seeding `ingest_files` with the real per-file plan once the scrape result is
known) — ran with zero further fencing. That second call's own SQL had no `ingest_run_id` precondition
at all, so it unconditionally rewrote `ingest_run_id`/`status` back to the original run's values. A
Stop landing while the scrape was still in flight (a real network call, seconds long) got silently
undone the instant the scrape returned — the row looked cancelled for exactly as long as the scrape
took, then came back to life. The first fencing fix (`claim_merge`) was still correct and still
necessary; it just wasn't the actual mechanism the founder saw, which was one step earlier in the
pipeline. Confirmed by direct Cloud Run log correlation (`/ingest-worker/start` → `/ingest-worker/
merge-step` request pairs, timestamps lining up with the resurrection) and a live re-test with a
25-second delayed re-check added specifically because the first "immediate" check was too fast to
catch it.

**Fix:** Same `expected_run_id`-fencing pattern applied to the second `begin_ingest_run` call — abort
the rest of the pipeline immediately if the row's `ingest_run_id` no longer matches what this task
was dispatched for.

**Impact:** `backend/services/supabase_client.py`, `backend/routers/ingest_worker.py`. Verified via a
direct DB-level test of the fencing query's exact semantics (not just reasoning about the SQL), then 4
live end-to-end Playwright runs against redeployed staging, plus manual re-checks of passing test rows
several minutes later confirming no delayed resurrection.

**Global Candidate:** Yes — "a cancel/fencing fix only covers the write path you tested, not
necessarily every write in the pipeline" generalizes well past this project. The specific tell worth
naming: if a *first* fencing fix doesn't fully close a "cancel still gets undone later" bug, look for
a *second* unconditional write further down the same code path before assuming the fencing logic
itself is wrong.

---

## 2026-09-19 — Flutter web's file_picker (canvas-rendered) doesn't respond to Playwright's file-chooser intercept or a synthetic HTML5 drag-and-drop

**Context:** Wanted a guide.html screenshot showing the Upload Files dropzone with a couple of real
dummy files already added, not just the empty "Drag & drop or tap to browse" state.

**Discovery:** Tried `page.waitForEvent('filechooser')` around a click on the dropzone (the standard
Playwright pattern for a native `<input type="file">`) — timed out after 30s with zero native file
dialog ever appearing, and `page.locator('input[type="file"]').count()` returned 0, confirming no such
element exists in the DOM at all (Flutter's `file_picker` web implementation isn't using a plain
clickable `<input>` the way a typical web form would). Tried simulating a real HTML5 drag-and-drop
instead — constructing an actual `DataTransfer` with real `File` objects and dispatching
`dragenter`/`dragover`/`drop` on `document.body` — which needs no native dialog at all, just DOM
events. Also no effect: the dropzone's UI never changed. Flutter's CanvasKit renderer listens for
pointer/drop events through its own internal engine plumbing (likely a specific glass-pane element,
not a bare `document.body` listener), so synthetic top-level DOM events don't reach it either.

**Impact:** Shipped the guide.html screenshot without dummy files rather than continuing to sink time
into this; logged as an open founder decision in `CONTEXT.md` (accept as-is, or supply a real
screenshot manually) rather than guessing at a third automation approach.

**Global Candidate:** Yes — this is a real, reusable finding about Flutter web + Playwright generally:
file upload automation likely needs to target the specific element/mechanism Flutter's engine
actually listens on (would need investigation inside `flutter_web_plugins`' `file_picker` source to
find it), not the generic "native input" or "generic drop event" patterns that work on a normal DOM
app.

**Impact:** `scraper/main.py`, live-verified twice (direct scraper call + full Train Now retest).
**Global Candidate:** Yes — any project using Firecrawl (or likely similar scrape-as-a-service tools)
against JS-heavy/frequently-changing pages should default to a fresh fetch, not the library default,
whenever data freshness/completeness actually matters — the cache reuse window is undocumented and
varies by domain per Firecrawl's own tool description.

---

## 2026-09-21 — "Verify" was consistently the step that got skipped or done too shallowly on a whole batch of visual (guide.html screenshot) fixes

**Context:** Reworked guide.html's screenshot highlight boxes/crops across the Add Property,
Property Enhancement, and Add a Guest tabs — cropping and positioning them, matching them to the
real in-app `WalkthroughHighlight` widget's style, and splicing new real-walkthrough captures in
via a regex-based script.

**Discovery:** The founder had to correct the same categories of mistake multiple times in a row,
including things already explicitly agreed to and claimed fixed: highlight boxes still cut into
the fields they're pointing at (agreed to fix, didn't re-verify after); the highlight style still
didn't visually match the real widget (asked for repeatedly across the session, a CSS change was
made but never re-checked against a real side-by-side afterward); a screenshot with a visibly
cut-off message box was spliced in as final even though the crop's incompleteness was evident at
capture time; a regex-based splice script's "two closing divs in a row" heuristic silently broke on
the one step (out of nine) that had an extra wrapper div, inserting a screenshot *inside* a callout
box instead of after it — the script's own success criterion was "ran without throwing," not
"landed in the visually correct place." In every case, the actual defect would have been visible
immediately by opening the real rendered page at full/zoomed size — the review process actually
used (a shrunk full-page thumbnail screenshot, viewed once, in isolation, not held next to the
original reference) was structurally incapable of catching any of it, and was trusted as sufficient
sign-off anyway.

**Impact:** `frontend/web/guide.html`. Full itemized list of what's still broken, exact root
causes where known, and a "why this kept going wrong" section written for the next session:
`_Context/HANDOFF_guide-screenshots-and-conflict-error_2026-09-21.md`. `FIX_VERIFY_PROTOCOL.md`
made mandatory for that follow-up work specifically because of this pattern.

**Global Candidate:** Yes — the general failure mode ("verify" collapsing into "looks plausible in
isolation" instead of "matches the specific reference, at real size, after every change") applies
to any visual/UI fix task, not just this project. Two concrete countermeasures worth carrying
forward: prefer element-locator screenshots over hand-guessed pixel `clip` coordinates (removes an
entire class of position-guessing bugs), and treat "I noticed this is still imperfect" during your
own work as a stop-and-fix signal, not something to ship and let the user catch.

---

## 2026-09-21 — An unverified fix for a slow Gemini call broke it completely in prod, immediately

**Context:** Investigating Submit Resolutions' "Alfred is not responding" error (founder report:
the error fired once, but clicking Submit again immediately succeeded). Reasoned by analogy to a
past bug (a 2026-09-09 incident where a Gemini call silently stalled forever with zero response)
and added a 25s call_timeout + 2-attempt retry to the resolver's Gemini call, on the theory it
might be the same class of stall.

**Discovery:** It wasn't the same bug. The founder's own report was the disproof, missed at
analysis time: "clicked Submit again, got 'Alfred is now trained' immediately" means the ORIGINAL
call (no timeout at all) had already completed successfully server-side -- a call that truly never
responds can't produce that outcome. The real cause was just latency past the frontend's 60s
timeout, not a stall. Cloud Run's own request timeout is 300s, so nothing was actually forcing a
25s ceiling -- capping it there guaranteed failure (2x25s, then a raised TimeoutError) on every real
property instead of the occasional slow-but-successful call. Shipped straight to prod (merged same
session, FIX_VERIFY_PROTOCOL.md explicitly skipped per founder request to save tokens) and broke
every live /api/resolve call immediately -- caught only because the founder was testing live and
reported it right away, not by any automated check.

**Impact:** Reverted the cap entirely (bfc1907), fixed the actual latency contributor (the resolver
was sending the full master_json twice in one prompt -- once in system_instruction, once in the
user message), and gave the frontend call more patience (120s) instead of the backend less.
Founder live-verified the revert on prod immediately after.

**Global Candidate:** Yes -- before adding a timeout/cap to "fix" a slow call, confirm it's a true
stall (zero response, ever) and not just legitimately slow relative to some OTHER, tighter timeout
in the chain (here: the frontend's 60s, not the backend's real 300s ceiling). The fix for "too slow
for timeout X" is very often "raise timeout X," not "cap the work at some shorter Y." Also: a
backend timing change with no FIX_VERIFY / no test coverage went straight to prod in the same
session it was written -- exactly the risk that protocol exists to catch, skipped here by explicit
request under token pressure. Worth deciding as a standing rule whether timing/timeout changes
specifically (as opposed to logic changes) get a lighter-weight mandatory check even under time
pressure, since their failure mode is "breaks every call of this type identically," not a rare edge
case.

## 2026-09-21 — Git Bash silently rewrites POSIX-looking script paths into Windows paths before they reach `wsl`

**Context:** Polling GCP Cloud Build status from the Bash tool via `wsl bash /tmp/some_script.sh`,
after writing the script to `\\wsl.localhost\Ubuntu\tmp\some_script.sh` (WSL's real /tmp).

**Discovery:** The command failed with `bash: C:/Users/.../AppData/Local/Temp/some_script.sh: No
such file or directory` -- Git Bash's MSYS layer auto-converts an argument that looks like an
absolute POSIX path into a Windows path when the command being invoked (wsl.exe) is a native
Windows binary, not an MSYS one. This happens even though the path is correct on the WSL side;
Git Bash never gets a chance to know that. Fixed by prefixing with `MSYS_NO_PATHCONV=1`, which
disables the auto-conversion for that one command.

**Impact:** Any `wsl <cmd> <path-looking-argument>` invocation from this environment's Bash tool
needs `MSYS_NO_PATHCONV=1 wsl ...` if the argument is a POSIX path meant for the WSL side.

**Global Candidate:** Yes -- this is an MSYS/Git-Bash behavior, not project-specific, and will recur
in any project using the Bash tool + wsl from this same host setup.

---

## 2026-09-22 — A "guaranteed" structured-data layer had a real coverage gap nobody had checked against the platform's own requirements

**Context:** Founder reported a real bug testing prod: a Mexican property's first guest message
came back in English. `welcome.py`'s language picker reads `master_json.location.country`.

**Discovery:** `UNIVERSAL_FIELDS_SCHEMA` (the schema-enforced "guaranteed always exists" layer of
`master_json`, built specifically to fix inconsistent freeform key naming) never actually defined
a `country` field -- only `location.address` (a raw string) + `coordinates`. Confirmed live on the
founder's actual property: the address string didn't even contain the word "Mexico," so no
text-parsing fallback could have covered this -- only a real schema fix. Auditing the same schema
against Airbnb's own official mandatory host-disclosure requirements (not assumption -- checked
via web research against Airbnb's Help Center) found a second, bigger gap: zero safety-disclosure
fields (smoke/CO alarms, cameras, weapons, hazards) despite Airbnb requiring hosts to disclose all
of them. Separately, a code comment in the same file claimed a smoke test
(`_UNIVERSAL_FIELDS_TEST`) verifies the schema never hallucinates ungrounded fields -- it doesn't
exist anywhere in the repo (verified via ripgrep before trusting the claim).

**Impact:** Shipped `location.{country,city,state_region,postal_code}`, a new `safety` object,
`parking`, and `commercial_photography_allowed` (`staging 2ccef20`). Verified live against a real
Gemini call before committing -- not just a code read. The missing test got queued
(`QUEUE.md`) rather than built same-session, since it wasn't the thing actually being asked for.

**Global Candidate:** Yes -- when a schema/data layer is described as "the guaranteed layer" or
"the structured fields," that description is a claim, not a fact -- verify its actual field
coverage against real consumers (what code reads from it) AND, where the domain has one, the
platform's own official required-field list, rather than trusting the layer's name or its own
design-comment's stated intent. Also: a code comment claiming a test/mechanism exists is itself
unverified until grepped for.

---

## 2026-09-22 — "Let's start simple" can be misread as license to defer the actual requested capability, not just its scope/UI

**Context:** Planning a Telegram host-escalation bridge (alert on escalation + let the host act on
it without opening the webapp). Founder said "let's start simple, add features later."

**Discovery:** First plan draft interpreted "simple" as: send a notification, plus a separate
"Intervene" button that just opens the webapp -- deferring "reply directly from Telegram" (the
blueprint's free-text relay) to an unspecified "later phase." Founder corrected this firmly: the
existing code already auto-flips `conversation.mode` to `intervene` the instant a message
escalates, so there is no button needed at all -- the host "intervening" IS them typing a reply in
Telegram, which routes to the guest. That routing was never a nice-to-have deferred feature; it
was the actual, literal thing being asked for. "Simple" meant simple alert *content* (don't send
the whole conversation history) and simple *UI* (no extra button to press), not a stubbed-down
core capability. The founder named this explicitly as the reason a pre-build FMEA/plan-alignment
step exists: "you would have spent time and effort building something that is not right."

**Impact:** Re-scoped the plan properly: host's typed Telegram reply routes to the guest via the
existing `host_send` delivery logic, disambiguated by Telegram's native reply-to-message when
multiple escalations are open at once (founder's explicit choice over "most recent wins"), with a
confirmation echo on every routed reply so the host always knows who they responded to. No wasted
build time -- caught during planning, before any code was written.

**Global Candidate:** Yes -- when a request says "keep it simple"/"start simple," that phrase is
ambiguous across at least three axes (scope of content, UI surface, and core capability) and can
be misread as license to cut the one thing actually being asked for. Before finalizing a plan built
on that instruction, restate back specifically what stays "full" vs what gets simplified, rather
than assuming which axis the word was meant to apply to.

---
