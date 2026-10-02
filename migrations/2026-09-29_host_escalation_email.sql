-- 2026-09-29 — Host escalation email fallback
--
-- STATUS
--   staging (gcxxilzfhwlsjcvtpsvj) : APPLIED via MCP 2026-09-29
--   prod    (ylaooctefesedrecshic) : pending — apply after staging verification
--
-- Every migration must be applied to BOTH projects (post-split rule, CONTEXT.md).
--
-- WHY
--   A real beta-tester incident (host Luis Martini, "Dpto 1 taxco"): a guest asked
--   how to enter the property while the conversation was escalated
--   (mode='intervene'), and Alfred stayed silent per design, waiting on the host.
--   The host had never linked Telegram, so the only existing alert channel
--   (host_profiles.telegram_chat_id, see 2026-09-22_telegram_host_escalation.sql)
--   never fired — no fallback existed. Full design:
--   C:\Users\San_8\.claude\plans\tingly-soaring-kitten.md
--
--   1. host_profiles.notification_email
--      Host-typed email for escalation alerts, independent of their Supabase
--      Auth login email (they may want a different inbox for this).
--   2. host_profiles.escalation_email_enabled
--      Explicit opt-in checkbox state (GDPR-relevant: consent is this flag, an
--      affirmative act, not assumed from setting an email alone).
--   3. host_profiles.escalation_email_unsub_token
--      Opaque token powering a no-login-required unsubscribe link included in
--      every escalation email — protects a third party if the host mistypes
--      someone else's address. Regenerated on every (re)activation so a stale
--      link from a prior activation can't unexpectedly toggle a new one.
--
-- REVERSIBILITY
--   Fully additive. Existing rows get NULL/false; every current code path
--   ignores them until the backend change (same commit) reads them. Safe to
--   apply ahead of the backend deploy.


-- ── DDL ──────────────────────────────────────────────────────────────────────

alter table public.host_profiles
  add column if not exists notification_email text,
  add column if not exists escalation_email_enabled boolean not null default false,
  add column if not exists escalation_email_unsub_token text;


-- ── VERIFY — run this SEPARATELY, after the DDL above has been executed ───────
-- Read-only: no transaction, nothing to roll back. Expect one PASS row.
--
-- select 'host_profiles columns' as check,
--        case when count(*) = 3 then 'PASS' else 'FAIL' end as result
--   from information_schema.columns
--  where table_schema = 'public' and table_name = 'host_profiles'
--    and column_name in ('notification_email', 'escalation_email_enabled',
--                         'escalation_email_unsub_token');
