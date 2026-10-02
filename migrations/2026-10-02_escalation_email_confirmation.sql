-- 2026-10-02 - Escalation email: confirmation gate (double opt-in)
--
-- STATUS
--   staging (gcxxilzfhwlsjcvtpsvj) : pending
--   prod    (ylaooctefesedrecshic) : pending - apply BEFORE the staging->main merge
--
-- Every migration must be applied to BOTH projects (post-split rule, CONTEXT.md),
-- and a git merge does NOT carry it (MERGE_TO_MAIN_PROTOCOL.md).
--
-- WHY
--   Until now a host could type ANY address into the Profile dialog and tick a
--   box; alerts then went to that address with no approval from its owner
--   (found live on prod 2026-10-02). FIX_VERIFY Step 0 also reproduced that a
--   logged-in host can write notification_email / escalation_email_enabled /
--   escalation_email_unsub_token straight through the REST API (RLS is
--   row-level only, and authenticated holds UPDATE on every column) - so a
--   backend-only confirmation step would be bypassable.
--
--   1. host_profiles.escalation_email_confirm_hash
--      SHA-256 of the one-time confirmation token e-mailed to the address.
--      Only the HASH is stored: hosts can read their own row, so a raw token
--      here would let them confirm any address themselves.
--   2. host_profiles.escalation_email_confirm_expires_at
--      Non-null = a confirmation is pending (backend mints now + 48 h). The
--      Profile dialog reads this to show "Waiting for confirmation".
--   3. Trigger host_profiles_lock_alert_email_cols
--      A host's own session (role authenticated/anon) can no longer change any
--      of the five alert-email columns - the old values are kept. Only the
--      backend (service_role) and the postgres role (migrations, SQL editor)
--      can. Preferred over column-level grants: no need to enumerate every
--      column the app legitimately writes (name, bio, telegram_chat_id, ...).
--   4. One-time reset: every already-enabled address is switched off so its
--      owner must confirm it (fail-safe; staging 0 hosts affected is fine,
--      prod 1 host as of 2026-10-02). The address stays stored, so the
--      Profile field is pre-filled and one click re-sends the confirmation.
--
-- REVERSIBILITY
--   Columns are additive; the trigger can be dropped. The reset in step 4
--   only turns alerts OFF (re-enabling = the host confirms again).


-- -- DDL ----------------------------------------------------------------------

alter table public.host_profiles
  add column if not exists escalation_email_confirm_hash text,
  add column if not exists escalation_email_confirm_expires_at timestamptz;

create or replace function public.host_profiles_lock_alert_email_cols()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user in ('authenticated', 'anon') then
    if tg_op = 'INSERT' then
      new.notification_email := null;
      new.escalation_email_enabled := false;
      new.escalation_email_unsub_token := null;
      new.escalation_email_confirm_hash := null;
      new.escalation_email_confirm_expires_at := null;
    else
      new.notification_email := old.notification_email;
      new.escalation_email_enabled := old.escalation_email_enabled;
      new.escalation_email_unsub_token := old.escalation_email_unsub_token;
      new.escalation_email_confirm_hash := old.escalation_email_confirm_hash;
      new.escalation_email_confirm_expires_at := old.escalation_email_confirm_expires_at;
    end if;
  end if;
  return new;
end;
$$;

-- Trigger functions are not meant to be called directly; creating the trigger
-- is the only place EXECUTE is checked, so this does not affect firing.
revoke execute on function public.host_profiles_lock_alert_email_cols()
  from public, anon, authenticated;

drop trigger if exists host_profiles_lock_alert_email_cols on public.host_profiles;
create trigger host_profiles_lock_alert_email_cols
  before insert or update on public.host_profiles
  for each row execute function public.host_profiles_lock_alert_email_cols();

-- Step 4: require re-confirmation of anything enabled before this gate existed.
update public.host_profiles
   set escalation_email_enabled = false
 where escalation_email_enabled;


-- -- VERIFY - run SEPARATELY after the DDL above. Read-only. Expect all PASS. ---
--
-- select 'columns' as check,
--        case when count(*) = 2 then 'PASS' else 'FAIL' end as result
--   from information_schema.columns
--  where table_schema = 'public' and table_name = 'host_profiles'
--    and column_name in ('escalation_email_confirm_hash', 'escalation_email_confirm_expires_at')
-- union all
-- select 'trigger', case when count(*) = 1 then 'PASS' else 'FAIL' end
--   from pg_trigger t join pg_class c on c.oid = t.tgrelid
--  where c.relname = 'host_profiles' and t.tgname = 'host_profiles_lock_alert_email_cols'
-- union all
-- select 'no enabled address left', case when count(*) = 0 then 'PASS' else 'FAIL' end
--   from public.host_profiles where escalation_email_enabled;
