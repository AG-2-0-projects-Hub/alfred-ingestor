# FIX-VERIFY Protocol

**Invoke explicitly:** "fix X with FIX_VERIFY_PROTOCOL.md" (or "...with the FIX-VERIFY
protocol"). Optional — not the silent default for every fix. Use it when the fix matters enough
to trade cycle speed for a mechanically-checked guarantee that nothing gets called "fixed"
without real proof, and to force building permanent test coverage instead of accepting a
coverage gap as an excuse.

**Why this exists:** the normal QA Workflow rules (failure-mode check, targeted replay,
pending-intake logging) live as prose in `CLAUDE.md` — a session has to remember to follow them,
and that erodes under long context or pressure. This protocol is deterministic instead: the
proof is a literal line in the commit message, and `_scripts/wrap_up.sh` mechanically fails the
session if it's missing. Not a promise — a structural check.

---

## The sequence

0. **Root-cause it, don't patch it.** Before FMEA: reproduce the actual failure against real data
   (not a description of it), and trace it to the literal mechanism — which line, which prompt
   section, which source text — by reading the real thing directly, never by assuming. Then
   isolate the variable: is this really caused by what you think, or is it pre-existing/
   non-deterministic noise? Re-run the *unmodified* code/prompt multiple times before accepting a
   diagnosis — this step alone has killed false "regressions" that turned out to be run-to-run
   variance rather than real bugs. Only once the mechanism is confirmed, not guessed, move to
   FMEA — and design the eventual fix as a general principle, not a patch scoped to the one case
   that surfaced it (if the fix can't be described without naming that specific case, it's still
   a patch, not a root-cause fix).
1. **FMEA, before any code.** A real failure-mode table — state × surface × data-delivery-path x  desired final state,
   not four shallow bullets — covering what this fix touches and how it can fail. Explicitly
   state whether automated test coverage already exists for this area. Silence on that question
   is not acceptable. Explain in plain words, no code or pseudo-code.
2. **Propose the fix, wait for explicit approval.** Same as every other change in this project —
   no code before a "yes"/"confirm"/"go ahead".
3. **Implement.**
4. **Verify for real — no exceptions for missing coverage:**
   - **Frontend changes:** create a real Playwright scenario under `_tests/runner/scenarios/`
     covering the fixed behavior (not merely reuse one that happens to already exist), and run
     it. This is the step that actually closes "we have no automated guard here" instead of
     working around it.
   - **Backend-only changes:** run a real check proving the fix works — a real DB query, a real
     API call, real log output. Not a code-read, not "should work now."
5. **Make the new scenario real, not orphaned — all three of these together, same commit:**
   - The scenario file itself (`_tests/runner/scenarios/<id>.ts`).
   - Wired into `_tests/runner/run.ts`'s scenario list (import + added to `pickScenarios`) — a
     file sitting unwired never actually runs again, at merge time or ever.
   - A matching row added to `_tests/scenarios.md` (the format the file's own header defines —
     `id`, `touches`, `layer`, `status`, etc.), with `status: passing` and `last_tested` set to
     today, same pattern already used by every other automated scenario in that file (e.g. A2).
     This is what lets a later `staging → main` merge simply **re-run this same file** instead of
     retesting from scratch — the row and the code stay in sync because they're written together.
6. **The commit message must include, verbatim, on their own lines:**
   ```
   Protocol: FIX_VERIFY
   Verified: <exactly how, with the actual evidence — command run, output, scenario name>
   ```
   This is what makes the commit mechanically inspectable — not a note, a required trailer.
7. **`_scripts/wrap_up.sh` enforces it.** Any commit carrying `Protocol: FIX_VERIFY` fails the
   session's wrap-up check if it lacks a `Verified:` line, or if it touched `frontend/lib/**`
   without both a matching new/changed file under `_tests/runner/scenarios/` **and** a matching
   change to `_tests/runner/run.ts` in the same commit. Structural only — it can't judge whether
   the verification was any good, only that the artifacts that make it real are all present.
8. **Only say "it's fixed" once step 4 has actually passed.** A failure at step 4 loops back to
   step 3 — never a new claim of done on top of an unverified fix.

## Example commit message

```
fix(frontend): property card no longer shows a stale badge after a background refresh

<normal body explaining the bug and the fix>

Protocol: FIX_VERIFY
Verified: added _tests/runner/scenarios/d6.ts (dashboard badge survives a 10s background
refresh with scrape_retry active), wired into run.ts, row D6 added to _tests/scenarios.md
(status: passing), ran against staging — PASS.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
```

## Exemptions

Same list QA Workflow's pending-intake rule already uses — no need for a second list to drift
out of sync with the first:
- Pure cosmetic changes (spacing, colour) with no assertable state
- Changes already covered by an existing passing scenario
- Doc-only changes
