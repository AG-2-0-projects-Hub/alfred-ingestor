-- 2026-10-05 - Waitlist signups for the Mayordommo landing
--
-- STATUS
--   staging (gcxxilzfhwlsjcvtpsvj) : applied 2026-10-05 (two steps via MCP: table + function, then revoke from authenticated)
--   prod    (ylaooctefesedrecshic) : pending - apply on launch day, only on the founder's explicit "go"
--
-- Every migration must be applied to BOTH projects (post-split rule, CONTEXT.md),
-- and a git merge does NOT carry it (MERGE_TO_MAIN_PROTOCOL.md).
--
-- WHY
--   The landing's waitlist form (landing/_preview/preview-v4.html) was a preview
--   that sent nothing. This is the real store: one table, one function, nothing
--   else reachable from the browser.
--
--   1. Table waitlist_signups. One row per e-mail (unique on the trimmed,
--      lower-cased address, so "A@x.com " and "a@x.com" are the same person).
--      RLS is on and there is NO policy and NO grant for the public key, so
--      nobody can read, change or delete signups from the browser.
--   2. Function join_waitlist(email, homes, source, consent_text) - the only
--      door in (SECURITY DEFINER, deliberate: Supabase's advisor flags public
--      SECURITY DEFINER functions, this one is meant to be public and does
--      nothing but validate and insert). It rejects a bad e-mail or a homes
--      value outside 1 / 2-5 / 6+, refuses when 30 signups already arrived in
--      the last minute (global throttle against floods), and answers the same
--      "true" for a new and a repeated e-mail so the form never reveals who is
--      on the list. A repeated e-mail keeps its first row and only fills homes
--      if it was empty.
--
--   CONSENT EVIDENCE (kept now so it can be proven later):
--     created_at    = the moment the person asked to join
--     consent_text  = the exact fine print the page showed next to the button
--     source        = which page/version sent it
--     notice_version= version of the aviso de privacidad shown (null until that
--                     page exists - the live form must not collect real e-mails
--                     before it does)
--     confirmed_at  = reserved for double opt-in (confirmation e-mail), null
--                     until there is a sender domain and an e-mail provider
--
-- REVERSIBILITY
--   Purely additive: drop function join_waitlist(text,text,text,text); drop table waitlist_signups;


-- -- DDL ----------------------------------------------------------------------

create table if not exists public.waitlist_signups (
  id             uuid primary key default gen_random_uuid(),
  email          text not null,
  homes          text,
  source         text,
  consent_text   text,
  notice_version text,
  confirmed_at   timestamptz,
  created_at     timestamptz not null default now(),
  constraint waitlist_signups_email_shape
    check (length(email) <= 254 and email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]{2,}$'),
  constraint waitlist_signups_email_normalized
    check (email = lower(btrim(email))),
  constraint waitlist_signups_homes_values
    check (homes is null or homes in ('1', '2-5', '6+'))
);

create unique index if not exists waitlist_signups_email_key
  on public.waitlist_signups (email);

alter table public.waitlist_signups enable row level security;
revoke all on public.waitlist_signups from anon, authenticated;

create or replace function public.join_waitlist(
  p_email        text,
  p_homes        text default null,
  p_source       text default null,
  p_consent_text text default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_homes text := nullif(btrim(coalesce(p_homes, '')), '');
begin
  if length(v_email) = 0
     or length(v_email) > 254
     or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]{2,}$' then
    raise exception 'invalid_email' using errcode = 'P0001';
  end if;

  if v_homes is not null and v_homes not in ('1', '2-5', '6+') then
    raise exception 'invalid_homes' using errcode = 'P0001';
  end if;

  if (select count(*) from public.waitlist_signups
       where created_at > now() - interval '1 minute') >= 30 then
    raise exception 'rate_limited' using errcode = 'P0001';
  end if;

  insert into public.waitlist_signups (email, homes, source, consent_text)
  values (v_email, v_homes, left(p_source, 60), left(p_consent_text, 400))
  on conflict (email) do update
    set homes = coalesce(public.waitlist_signups.homes, excluded.homes);

  return true;
end;
$$;

-- only the public (anon) key calls it; signed-in app users have no business here
revoke all on function public.join_waitlist(text, text, text, text) from public;
revoke all on function public.join_waitlist(text, text, text, text) from authenticated;
grant execute on function public.join_waitlist(text, text, text, text) to anon;
