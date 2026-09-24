-- 2026-09-24 — First-login "Welcome to Alfred" modal seen-flag
--
-- STATUS
--   staging (gcxxilzfhwlsjcvtpsvj) : run via MCP this session
--   prod    (ylaooctefesedrecshic) : NOT YET APPLIED — run alongside the eventual staging→main merge
--
-- Every migration must be applied to BOTH projects (post-split rule, CONTEXT.md).
--
-- WHY
--   host_profiles.welcome_modal_seen
--     Gates the one-time first-login onboarding modal (5-step tour + "Add Your
--     First Property"/"Maybe later"). Server-side, not SharedPreferences (the
--     mechanism the app's other two walkthroughs use), because it must reset
--     correctly when an account is deleted and recreated with the same email
--     — a browser-local flag would not, since it's scoped per browser origin,
--     not per Supabase account. host_profiles rows are created lazily
--     (ProfileDialog's upsert on first save) — a brand-new signup has no row
--     at all yet, so the dashboard reads this as NULL/false (not seen) until
--     the first upsert, same pattern as is_dev (see
--     migrations/2026-09-09_host_is_dev_flag.sql).
--
-- REVERSIBILITY
--   Fully additive. Existing rows default to false — every current host who
--   has already been through (or past) onboarding will see the modal once on
--   their next login with zero properties. Acceptable: any host with an
--   existing property never hits the zero-properties trigger condition at
--   all, so this only actually surfaces for accounts that are currently
--   empty (test/abandoned accounts) or genuinely new ones.


-- ── DDL ──────────────────────────────────────────────────────────────────────

alter table public.host_profiles
  add column if not exists welcome_modal_seen boolean not null default false;


-- ── VERIFY — run this SEPARATELY, after the DDL above has been executed ───────
-- Read-only: no transaction, nothing to roll back. Expect one PASS row.
--
-- select 'column' as check,
--        case when count(*) = 1 then 'PASS' else 'FAIL' end as result
--   from information_schema.columns
--  where table_schema = 'public' and table_name = 'host_profiles'
--    and column_name = 'welcome_modal_seen';
