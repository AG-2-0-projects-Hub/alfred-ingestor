-- 2026-09-22 — Telegram host-escalation alerts + reply-from-Telegram
--
-- STATUS
--   staging (gcxxilzfhwlsjcvtpsvj) : run via MCP this session
--   prod    (ylaooctefesedrecshic) : APPLIED via MCP 2026-09-23
--
-- Every migration must be applied to BOTH projects (post-split rule, CONTEXT.md).
--
-- WHY
--   Bridges the "browser tab must be open" gap in web push notifications
--   (push_notification_service.dart) by forwarding an escalation to the host's
--   Telegram and letting them reply from there. Full design:
--   C:\Users\San_8\.claude\plans\tingly-finding-cupcake.md
--
--   1. host_profiles.telegram_chat_id
--      The host-side analogue of guests.telegram_chat_id / whatsapp_wa_id.
--      UNIQUE (partial, WHERE NOT NULL) for the same reason: _dispatch() needs
--      to resolve a chat_id to AT MOST ONE host unambiguously. Reconnecting
--      from a new phone MOVES the link (see supabase_client.link_host_telegram)
--      rather than erroring, mirroring link_guest_telegram/link_guest_whatsapp.
--
--   2. host_profiles.telegram_link_code / telegram_link_code_expires_at
--      One-time-use setup code for the "Connect Telegram" deep link + QR.
--      Short-lived (backend mints ~10min expiry) and cleared on successful
--      link — a valid code grants "receive this host's escalation alerts and
--      can reply to guests as this host," so it is treated as a credential,
--      not a cosmetic id.
--
--   3. conversations.host_alert_message_id
--      The Telegram message_id of the most recent escalation alert sent to
--      the host for this conversation. Read on a Telegram reply-to so the
--      reply routes to the right guest without the host typing anything
--      identifying. Always just the LATEST alert — a resolved conversation's
--      stale value is harmless (see FMEA) and gets overwritten by the next
--      escalation.
--
-- REVERSIBILITY
--   Fully additive. Existing rows get NULL in all four columns; every current
--   code path ignores them. Safe to apply ahead of the backend deploy.


-- ── DDL ──────────────────────────────────────────────────────────────────────

alter table public.host_profiles
  add column if not exists telegram_chat_id text,
  add column if not exists telegram_link_code text,
  add column if not exists telegram_link_code_expires_at timestamptz;

create unique index if not exists host_profiles_telegram_chat_id_key
  on public.host_profiles (telegram_chat_id)
  where telegram_chat_id is not null;

alter table public.conversations
  add column if not exists host_alert_message_id bigint;


-- ── VERIFY — run this SEPARATELY, after the DDL above has been executed ───────
-- Read-only: no transaction, nothing to roll back. Expect two PASS rows.
--
-- select 'host_profiles columns' as check,
--        case when count(*) = 3 then 'PASS' else 'FAIL' end as result
--   from information_schema.columns
--  where table_schema = 'public' and table_name = 'host_profiles'
--    and column_name in ('telegram_chat_id', 'telegram_link_code',
--                         'telegram_link_code_expires_at');
--
-- select 'conversations column' as check,
--        case when count(*) = 1 then 'PASS' else 'FAIL' end as result
--   from information_schema.columns
--  where table_schema = 'public' and table_name = 'conversations'
--    and column_name = 'host_alert_message_id';
--
-- -- Must be BOTH unique AND partial (many NULL rows must coexist).
-- select 'partial unique index' as check,
--        case when count(*) = 1 then 'PASS' else 'FAIL' end as result
--   from pg_indexes
--  where schemaname = 'public'
--    and indexname  = 'host_profiles_telegram_chat_id_key'
--    and indexdef ilike '%UNIQUE%'
--    and indexdef ilike '%WHERE%telegram_chat_id IS NOT NULL%';
