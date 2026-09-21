-- 2026-09-09 — Dev/User account split flag
--
-- STATUS
--   staging (gcxxilzfhwlsjcvtpsvj) : APPLIED via MCP 2026-09-09
--   prod    (ylaooctefesedrecshic) : NOT YET APPLIED — run alongside the eventual staging→main merge
--
-- Every migration must be applied to BOTH projects (post-split rule, CONTEXT.md).
--
-- WHY
--   The webapp is about to grow a whole-app Dev/User view split: the founder's
--   own account keeps full pipeline visibility (Master JSON, raw Ingest/Merge
--   buttons, Files tab), while beta-host accounts get a streamlined view with
--   those internals hidden. `host_profiles` is already fetched once per login
--   (dashboard_screen.dart's _loadHostAvatar), so this flag rides that existing
--   query rather than adding new plumbing.
--
--   1. host_profiles.is_dev
--      Defaults false for every existing and future row — beta hosts are the
--      common case. Flipped true only for founder-named accounts; see the
--      data migration below.
--
-- REVERSIBILITY
--   Fully additive. Existing rows default to false (User mode) — the correct
--   behavior for every account that isn't explicitly named as Dev.


-- ── DDL ──────────────────────────────────────────────────────────────────────

alter table public.host_profiles
  add column if not exists is_dev boolean not null default false;


-- ── DATA — flip the founder's account to Dev mode ─────────────────────────────
-- Confirmed with founder 2026-09-09: only sans.lighthouse@gmail.com for now.
-- Founder will name any further accounts explicitly rather than this being inferred.
--
-- host_profiles rows are only created lazily (ProfileDialog's upsert, on first
-- save) — a plain UPDATE is a no-op for any account that has never opened that
-- dialog. Upsert instead so this works whether or not a row already exists.

insert into public.host_profiles (id, is_dev)
select id, true from auth.users where email = 'sans.lighthouse@gmail.com'
on conflict (id) do update set is_dev = true;


-- ── VERIFY — run this SEPARATELY, after the DDL/DATA above has been executed ──
-- Read-only: no transaction, nothing to roll back. Expect one PASS row and
-- exactly one is_dev=true row (the founder's account).
--
-- select 'column' as check,
--        case when count(*) = 1 then 'PASS' else 'FAIL' end as result
--   from information_schema.columns
--  where table_schema = 'public'
--    and table_name = 'host_profiles'
--    and column_name = 'is_dev';
--
-- select id, is_dev from public.host_profiles where is_dev = true;
