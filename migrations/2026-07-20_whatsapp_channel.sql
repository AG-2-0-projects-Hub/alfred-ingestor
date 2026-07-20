-- 2026-07-20 — WhatsApp guest channel (port of the native Telegram channel)
--
-- STATUS
--   staging (gcxxilzfhwlsjcvtpsvj) : APPLIED via MCP 2026-07-20
--   prod    (ylaooctefesedrecshic) : RUN THIS IN THE SQL EDITOR (no MCP on prod)
--
-- Every migration must be applied to BOTH projects (post-split rule, CONTEXT.md).
--
-- ⚠️ Run the DDL below and the VERIFY block at the bottom as SEPARATE executions.
--    The Supabase SQL editor wraps a pasted script in ONE implicit transaction, so
--    the verify block's trailing `rollback` would revert the DDL too — while still
--    printing PASS in-transaction. That is exactly how the prod RLS gap of
--    2026-07-16 happened. Paste the DDL, run it, THEN paste the verify block.
--
--
-- WHY
--   WhatsApp is being added as `conversations.active_channel = 'whatsapp'`, a port
--   of the Telegram channel. Two additive columns are needed.
--
--   1. guests.whatsapp_wa_id
--      The Telegram analogue of `telegram_chat_id`. Meta identifies a sender by
--      `wa_id` — their phone number in E.164 WITHOUT the leading '+' (e.g.
--      "5215512345678"). Stored as text for the same reason telegram_chat_id is:
--      it is an opaque identifier, never arithmetic, and leading zeros / length
--      vary by country.
--
--      UNIQUE (partial, WHERE NOT NULL) mirrors the telegram_chat_id contract: one
--      WhatsApp account maps to at most one booking at a time. The link is MOVED
--      rather than duplicated when a returning guest starts a new stay — see
--      supabase_client.link_guest_whatsapp, which releases the id from any other
--      booking first. The partial predicate is what lets the many NULL rows
--      (web-only and Telegram guests) coexist.
--
--   2. conversations.last_guest_inbound_at
--      WhatsApp-specific and NOT cosmetic. Meta only permits free-form messages
--      within 24h of the guest's last inbound message (the "customer service
--      window"). Outside it, a send is REJECTED (error 131047) unless it uses a
--      pre-approved template.
--
--      Telegram and web have no such limit, so this is genuinely new failure
--      surface: a host answering an escalation the next morning would otherwise
--      get a silent delivery failure. The backend stamps this on every inbound
--      WhatsApp message and checks it in host_send, so the dashboard can tell the
--      host WHY the message could not be delivered instead of swallowing it.
--
--      Nullable with no default: NULL means "no guest inbound recorded", which is
--      the correct starting state for every existing row and for web/Telegram
--      conversations that will never use it.
--
--
-- NOT NEEDED (verified 2026-07-20, do not add)
--   `conversations.active_channel` already accepts 'whatsapp' as-is. It is plain
--   `text NOT NULL` with NO check constraint — the only CHECK on the table is
--   `conversations_mode_check` on `mode` ('autopilot'|'intervene'). Adding a
--   constraint now would be scope creep and would have to be widened again for
--   every future channel.
--
--
-- REVERSIBILITY
--   Fully additive and inert. Existing rows get NULL in both columns; every
--   current code path ignores them. Safe to apply well ahead of the code.


-- ── DDL ──────────────────────────────────────────────────────────────────────

alter table public.guests
  add column if not exists whatsapp_wa_id text;

create unique index if not exists guests_whatsapp_wa_id_key
  on public.guests (whatsapp_wa_id)
  where whatsapp_wa_id is not null;

alter table public.conversations
  add column if not exists last_guest_inbound_at timestamptz;


-- ── VERIFY — run this SEPARATELY, after the DDL above has been executed ───────
-- Read-only: no transaction, nothing to roll back. Expect two PASS rows.
--
-- select 'columns' as check,
--        case when count(*) = 2 then 'PASS' else 'FAIL' end as result
--   from information_schema.columns
--  where table_schema = 'public'
--    and (   (table_name = 'guests'        and column_name = 'whatsapp_wa_id')
--         or (table_name = 'conversations' and column_name = 'last_guest_inbound_at'));
--
-- -- Must be BOTH unique AND partial. A non-partial unique index would reject the
-- -- second web/Telegram guest (they all carry NULL) and break guest creation.
-- select 'partial unique index' as check,
--        case when count(*) = 1 then 'PASS' else 'FAIL' end as result
--   from pg_indexes
--  where schemaname = 'public'
--    and indexname  = 'guests_whatsapp_wa_id_key'
--    and indexdef ilike '%UNIQUE%'
--    and indexdef ilike '%WHERE%whatsapp_wa_id IS NOT NULL%';
