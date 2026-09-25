# Feedback Triage — the-ingestor Addendum

**Base protocol:** `_protocols/FEEDBACK_TRIAGE_PROTOCOL.md` — read and follow it in full. This
file is not a replacement; it supplies this project's required inputs (the `sources:`
declaration Step 1 needs) plus the project-specific execution rules the base protocol
deliberately delegates to "the active project."

**Deviation from the base protocol's Step 1, deliberate:** the base protocol's Initialization
says to find the `## Feedback Triage` heading and its `sources:` YAML block inside the
project's own `CLAUDE.md`. For the-ingestor, `CLAUDE.md` carries only a one-line pointer to
this file (kept lean, per the founder 2026-09-25) — **this file is where the real `sources:`
block lives.** Step 1 should read here, not expect the YAML inline in CLAUDE.md.

---

## Sources

```yaml
sources:
  - id: webapp-feedback
    abbrev: WF
    kind: Freeform host-submitted feedback via the in-app dialog (feedback_dialog.dart) — no
      frequency signal, 3-state native status field.
    mcp: supabase-the-ingestor
    tools: [execute_sql]
    retrieve: |
      SELECT id, created_at, host_id, host_email, type, message, route, status
      FROM feedback
      WHERE status = 'new'
      ORDER BY created_at DESC
    state_field: status
    state_values: [new, seen, done]   # native column, check-constrained — do not add a 4th value
    state_write: |
      UPDATE feedback SET status = $1 WHERE id = $2
      -- via supabase-the-ingestor MCP execute_sql (service-role), never the app's own RLS path
      -- new -> seen at Step 5 (triaged); seen -> done at Step 8 (shipped OR dismissed — the
      -- shipped/dismissed distinction lives in the backlog file's outcome tag, not this column)
    severity_signals: only freeform text + the reporter's own `type` tag (bug/idea/confusing/
      other) as a hint, per the base protocol's freeform calibration profile
    reach_metric: count distinct host_email values reporting the same symptom, in this batch +
      the open backlog (per the base protocol's freeform frequency substitute)

  - id: sentry-errors
    abbrev: SE
    kind: Backend + frontend + scraper error tracking — native frequency signal per issue. NOT
      YET LIVE — declared here so it activates the moment Sentry setup (QUEUE.md item) ships;
      until then this source reports SOURCE_UNAVAILABLE and is skipped per the base protocol's
      own per-run skip rule (never blocks other sources).
    mcp: sentry
    tools: [search_issues, get_sentry_resource, update_issue]
    retrieve: |
      List unresolved issues in org alonso-vazquez-ng, projects: alfred-backend,
      alfred-frontend, alfred-scraper (staging + prod both tagged via environment, not
      separate Sentry projects)
    state_field: issue.status   # native Sentry field, no duplicate needed
    state_values: [unresolved, resolved, ignored]
    state_write: |
      update_issue(project_slug, issue_id, status='resolved')  -- via sentry MCP
    severity_signals: yes — occurrence count + last-seen timestamp per issue (frequency-signal
      calibration profile, not freeform)
    reach_metric: native Sentry "users affected" count per issue
```

**Not yet a source — forward note only:** a future `dev_items` table (or equivalent) will hold
the founder's own directly-logged fix/feature requests, kept separate from host-submitted
feedback. Add it as a third declared source once it exists. Do not invent it now.

---

## FIX_VERIFY_PROTOCOL Integration (this project's Step 8 "Checkpoint A")

The base protocol's Step 8 hooks into whatever this project already uses to call a fix
"verified" — it does not define its own notion of done. For the-ingestor, that hook is:

- **S1/S2 items that touch user-facing code** (frontend, or a user-visible backend behavior):
  the full `FIX_VERIFY_PROTOCOL.md` sequence — FMEA, explicit approval, implement, a real
  Playwright scenario (or real backend check for backend-only) proving it, wired into
  `_tests/runner/run.ts` + `_tests/scenarios.md`, `Protocol: FIX_VERIFY` + `Verified:` commit
  trailer.
- **S3/S4 items, or backend-only items with no user-visible behavior change:** use
  `FIX_VERIFY_PROTOCOL.md`'s own exemption list (pure cosmetic, already covered by an existing
  scenario, doc-only) to decide — these do not require the full sequence by default.
- Checkpoint B (ship) is unchanged: this project's own Git hard rules — no push without
  explicit founder go-ahead, regardless of who approved Step 6.

---

## Automation Readiness (design intent, not built)

Steps 1–5 of the base protocol (Retrieve → Normalize/Cluster → Dedup → Rate Severity → Write
Report) are read-only by construction — safe to run on a schedule (a future cron) with zero
side effects. **Step 6 (the Approval Gate) is the one step that must stay manual** — currently
the founder, eventually a QA agent with defined authority, but never removed entirely. Steps
7–9 (Execute, Verify+Ship, Archive) still require the founder's explicit go-ahead to ship, per
this project's own Git hard rules, independent of who approved Step 6.

No cron is wired up yet. Wiring one is a separate, explicit decision, per the base protocol's
own "Explicitly Out of Scope" section.

---

## Report + Backlog Location

- Reports: `_Context/feedback_triage/<YYYY-MM-DD>_<source_id>.md`
- Backlog: `_Context/feedback_triage/BACKLOG.md` (created on first run, per base protocol Step 9)

---

## Document Version & Maintenance

**Version:** 1.0
**Created:** 2026-09-25

### Version History
* **v1.0 (2026-09-25):** Initial version. Declares the-ingestor's two feedback sources (webapp
  `feedback` table, Sentry once live) against the base `_protocols/FEEDBACK_TRIAGE_PROTOCOL.md`.
  Schema verified live against staging (`supabase-the-ingestor` MCP) before writing —
  `feedback.status` uses a native 3-state check constraint (`new`/`seen`/`done`), not the
  4-state guess (`new`/`triaged`/`resolved`/`dismissed`) initially assumed. Kept out of
  `CLAUDE.md` per the founder's explicit request to keep that file lean — `CLAUDE.md` carries
  only a one-line pointer here.
