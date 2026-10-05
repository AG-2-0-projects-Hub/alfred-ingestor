-- 2026-10-05 - Waitlist: double opt-in (confirmation e-mail) + unsubscribe
--
-- STATUS
--   staging (gcxxilzfhwlsjcvtpsvj) : applied 2026-10-05 (via MCP)
--   prod    (ylaooctefesedrecshic) : pending - apply on launch day together with
--                                    2026-10-05_waitlist_signups.sql, only on the founder's explicit "go"
--
-- Every migration must be applied to BOTH projects (post-split rule, CONTEXT.md),
-- and a git merge does NOT carry it (MERGE_TO_MAIN_PROTOCOL.md).
--
-- WHY
--   2026-10-05_waitlist_signups.sql let the browser call join_waitlist directly. That
--   can store a signup but cannot e-mail anyone (the SendGrid key lives on the backend),
--   and anyone can type somebody else's address. The confirmation e-mail fixes both: the
--   backend (routers/waitlist.py, same pattern as the host escalation-email confirmation)
--   stores a one-time token HASH, e-mails the link, and only the owner of the address can
--   confirm it (confirmed_at is the proof of consent).
--
--   New columns on waitlist_signups:
--     confirm_hash        SHA-256 of the one-time confirmation token (never the raw token)
--     confirm_expires_at  non-null = a confirmation is pending (backend mints now + 7 days)
--     confirm_sent_at     when the last confirmation e-mail went out (cooldown + daily cap)
--     unsub_token         random token in every e-mail's unsubscribe link (kept as is, like
--                         host_profiles.escalation_email_unsub_token)
--     unsubscribed_at     set when the person opts out; the row stays so we never e-mail
--                         them again; a later fresh signup clears it (new consent)
--
--   The public key no longer runs join_waitlist: the backend (service role) is the only
--   way in now. The function is kept, not dropped (reversible); drop it later.
--
-- REVERSIBILITY
--   Columns are additive; grant execute on function public.join_waitlist(text,text,text,text) to anon
--   would restore the old direct path.


alter table public.waitlist_signups
  add column if not exists confirm_hash       text,
  add column if not exists confirm_expires_at timestamptz,
  add column if not exists confirm_sent_at    timestamptz,
  add column if not exists unsub_token        text,
  add column if not exists unsubscribed_at    timestamptz;

create index if not exists waitlist_signups_confirm_hash_idx
  on public.waitlist_signups (confirm_hash) where confirm_hash is not null;

create unique index if not exists waitlist_signups_unsub_token_key
  on public.waitlist_signups (unsub_token) where unsub_token is not null;

revoke execute on function public.join_waitlist(text, text, text, text) from anon;
