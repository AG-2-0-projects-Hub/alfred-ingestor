-- 2026-09-23 — Telegram host "locked-in conversation" + multi-escalation picker
--
-- STATUS
--   staging (gcxxilzfhwlsjcvtpsvj) : run via MCP this session
--   prod    (ylaooctefesedrecshic) : NOT YET APPLIED — run alongside the eventual staging→main merge
--
-- Every migration must be applied to BOTH projects (post-split rule, CONTEXT.md).
--
-- WHY
--   Live-testing the base host-escalation feature (2026-09-22) surfaced real friction with 2+
--   simultaneous escalations: the host had to scroll up and reply-to the specific alert every
--   time, which gets confusing fast with several guests active at once. Founder reviewed the
--   legacy Make.com blueprint's own answer to this (a "locked-in conversation" pointer + an
--   inline-button picker) and asked for the same model, adapted onto the current schema.
--
--   host_profiles.active_conversation_booking_id
--     Which booking_id a host's PLAIN (non-reply-to) Telegram messages currently route to.
--     NULL means "unlocked" — the next plain message triggers the zero/one/many logic in
--     routers/telegram.py's _handle_host_reply (auto-route if exactly one escalation is active,
--     otherwise show the picker). Set by: replying-to a specific alert (also acts as "select"),
--     tapping a picker button, or auto-locking when exactly one escalation is active. Cleared by:
--     resolving the LOCKED conversation specifically (resolving a different one does not touch
--     it), or auto-detected as stale (the locked conversation was resolved some other way, e.g.
--     the dashboard) on the next plain message.
--
--     Named "_booking_id" (not "_conversation_id", unlike the legacy blueprint's misleadingly-
--     named `active_conversation_id`, which actually held a booking_id too) to avoid that exact
--     ambiguity on this project's own schema, where conversations.id and guests/conversations.
--     booking_id are both real, different identifiers in active use.
--
-- REVERSIBILITY
--   Fully additive. Existing rows get NULL (unlocked); every current code path already handles
--   an unset lock as the starting state. Safe to apply ahead of the backend deploy.


-- ── DDL ──────────────────────────────────────────────────────────────────────

alter table public.host_profiles
  add column if not exists active_conversation_booking_id text;


-- ── VERIFY — run this SEPARATELY, after the DDL above has been executed ───────
-- Read-only: no transaction, nothing to roll back. Expect one PASS row.
--
-- select 'host_profiles column' as check,
--        case when count(*) = 1 then 'PASS' else 'FAIL' end as result
--   from information_schema.columns
--  where table_schema = 'public' and table_name = 'host_profiles'
--    and column_name = 'active_conversation_booking_id';
