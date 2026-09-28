# Merge-to-Main Protocol

**Run this before every `staging → main` merge.** Consolidates the pre-merge QA checklist and
post-merge deploy reality into one place, instead of scattered once-a-month rules living inline in
`CLAUDE.md` (moved out 2026-09-28 — see `lessons.md` for why: a Cloud Run deploy fact almost
landed as a standalone `CLAUDE.md` rule for a single-change reason before being redirected here).

---

## Before merging

0. Proactively ask whether to run the Critical Path check first — don't wait to be asked for it
   by name.
1. Review `_tests/scenarios.md`'s "## Pending intake" table.
2. Group rows by flow using the `Group with` column.
3. For each group: create one proper scenario (or extend an existing one) in the relevant A–H
   section of `_tests/scenarios.md` — multi-step assertions are preferred over micro-scenarios.
4. Delete the promoted intake rows.
5. Run every Critical Path scenario (`_tests/scenarios.md`'s "## Critical Path" section) —
   automated ones via `npm run full`, unautomated ones manually until they're built. Run any other
   new Layer 1 scenarios immediately too; schedule non-critical Layer 2 scenarios for the next
   Playwright run as before.

**What does NOT need a pending-intake entry:** pure cosmetic changes (spacing, colour tweaks) with
no assertable state; changes already covered by an existing passing scenario; changes to this file
or other docs.

## Merging

Open a PR from `staging`→`main` (GitHub UI or `gh pr create`) — a plain push to `main` is rejected
by branch protection. **The founder merges these PRs manually on purpose, as their own final QA
gate — never script or bypass this step.** Verify remote SHA matches local after merging.

## After merging — prod does not deploy itself

- **Cloud Run (backend + scraper) does NOT auto-deploy on a `main` merge** — no Cloud Build
  trigger exists (standing fact, not tied to any one change; original finding in `CONTEXT.md`'s
  2026-07-12 entry). The merge only updates the `main` branch — prod backend/scraper keep running
  whatever image was last manually deployed. Ask the founder whether to redeploy prod now:
  ```
  gcloud run deploy alfred-backend --source=backend --region=europe-west3 --project=alfred-prod-502215
  gcloud run deploy alfred-scraper --source=scraper --region=europe-west3 --project=alfred-prod-502215
  ```
- **Frontend is different** — Vercel's GitHub integration auto-deploys `main` on merge, no manual
  step needed.

Don't assume a merge alone shipped anything to real users — it only did for the frontend.
