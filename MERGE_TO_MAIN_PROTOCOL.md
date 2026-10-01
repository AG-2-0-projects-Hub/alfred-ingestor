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

## Before merging — things a git merge does NOT carry (do these first)

Git only moves code. Each item below lives outside it and must already be in place on **prod**
before the merge's auto-deploy goes live (verified 2026-10-01: prod had none of the email vars):

1. **Migrations.** Every file under `migrations/` must be applied to the prod Supabase project
   (`ylaooctefesedrecshic`) — compare `list_migrations` on both projects and the per-table column
   hashes (`information_schema.columns`) rather than trusting the status header inside each `.sql`.
2. **Cloud Run env vars/secrets.** The Cloud Build trigger ships code only and preserves whatever
   env prod already has, so any *new* env var a merged commit reads (e.g. `SENDGRID_API_KEY`,
   `EMAIL_FROM`, `BACKEND_URL`) must be set on `alfred-backend` by hand beforehand. Diff
   `gcloud run services describe alfred-backend-staging` vs `alfred-backend` env names.
3. **Secret hygiene.** Never read a secret from a Windows-saved `.txt` without `tr -d '\r\n'` —
   a trailing `\r` makes HTTP header values illegal (see `lessons.md` 2026-10-01).

## After merging — prod deploys itself (code only)

- **Cloud Run (backend + scraper) auto-deploys on a `main` merge** via the `deploy-prod-on-main`
  Cloud Build trigger (europe-west3, `cloudbuild.yaml`; verified live 2026-10-01). It ships **code
  only** and preserves prod's existing env/secrets — hence the pre-merge checklist above. This
  line used to say the opposite ("no trigger exists", from before 2026-07-17); that was stale.
  Verify after the merge: `gcloud builds list --region=europe-west3` shows a SUCCESS build for the
  merge SHA, and `gcloud run services describe alfred-backend` serves 100% from the new revision.
- **Staging does not auto-deploy** — there is no trigger on `staging`; a backend fix needs a
  manual `gcloud run deploy alfred-backend-staging --source=backend ...`.
- **Frontend** — Vercel's GitHub integration auto-deploys `main` on merge, no manual step needed.
