-- 2026-07-14 — Guests cannot write to a deleted listing's conversation
--
-- STATUS
--   staging (gcxxilzfhwlsjcvtpsvj) : APPLIED via MCP 2026-07-14
--   prod    (ylaooctefesedrecshic) : RUN THIS IN THE SQL EDITOR (no MCP on prod)
--
-- Every migration must be applied to BOTH projects (post-split rule, CONTEXT.md).
-- `_tests/env_parity.py` compares function names, so leaving prod behind will
-- make the parity probe fail — which is exactly what should happen.
--
--
-- WHY
--   The web guest chat writes its `messages` rows DIRECTLY from Flutter under
--   the booking JWT (chat_screen.dart), not through the backend. The backend now
--   refuses a deleted listing on both channels (410, commit 02e728f) and
--   /api/guest-token refuses to mint a NEW token once properties.deleted_at is
--   set — but a token already in the guest's hands stays valid for up to 24h and
--   still satisfied the old INSERT policy.
--
--   So a guest could keep appending rows to a conversation we are deliberately
--   RETAINING as an archived record — including after their host deleted their
--   entire account. Nothing should be writable onto a retained transcript.
--
--   (It could NOT resurrect the conversation: the un-archive lives in the
--   backend's Python insert_message, not in a DB trigger, and the backend path
--   is already closed. The damage was limited to stray rows.)
--
--
-- THE TRAP — do not "simplify" this back to a plain join
--   The obvious fix is to add `join properties p ... and p.deleted_at is null`
--   straight into the policy. That is WRONG and was caught only by testing it as
--   a real `anon`:
--
--     RLS is enforced INSIDE policy expressions, and `anon` has no SELECT policy
--     on `properties` (owner_only). The join therefore evaluates to ZERO rows for
--     every guest, and the policy denies ALL guest inserts — silently breaking
--     guest chat completely.
--
--   Measured as anon: conversations visible = 1, properties visible = 0.
--
--   Hence the SECURITY DEFINER function: it can see the properties row the guest
--   is not allowed to read, and returns only a boolean about a single
--   conversation id — no property data is exposed.

create or replace function public.conversation_property_is_live(conv_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1
    from public.conversations c
    join public.properties p on p.id = c.property_id
    where c.id = conv_id
      and p.deleted_at is null
  );
$$;

revoke all on function public.conversation_property_is_live(uuid) from public;
grant execute on function public.conversation_property_is_live(uuid) to anon, authenticated;

drop policy if exists "guest inserts own messages" on public.messages;

create policy "guest inserts own messages"
  on public.messages
  for insert
  to anon
  with check (
    -- unchanged: the guest may only write into their OWN booking's conversation
    sender_type = 'guest'
    and conversation_id in (
      select c.id
      from public.conversations c
      where c.booking_id = (auth.jwt() ->> 'booking_id')
    )
    -- new: ...and only while that conversation's listing still exists
    and public.conversation_property_is_live(conversation_id)
  );

-- The service role bypasses RLS, so every backend write is unaffected.


-- ─────────────────────────────────────────────────────────────────────────────
-- VERIFY (safe: creates two throwaway rows, asserts, and ROLLS BACK)
-- Both rows must read PASS. If the first says FAIL, guest chat is broken —
-- restore the previous policy immediately (see BACKOUT below).
-- ─────────────────────────────────────────────────────────────────────────────
begin;

insert into properties (id, name, owner_id, status, learned_knowledge, deleted_at)
values
  ('11111111-1111-1111-1111-111111111111','RLS probe LIVE',   null,'Trained','[]', null),
  ('22222222-2222-2222-2222-222222222222','RLS probe DELETED',null,'deleted','[]', now());
insert into guests (booking_id, property_id, name)
values
  ('probe-live','11111111-1111-1111-1111-111111111111','Probe Live'),
  ('probe-dead','22222222-2222-2222-2222-222222222222','Probe Dead');
insert into conversations (id, booking_id, property_id)
values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','probe-live','11111111-1111-1111-1111-111111111111'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','probe-dead','22222222-2222-2222-2222-222222222222');

create temp table probe_result(scenario text, allowed boolean, expected boolean) on commit drop;

do $$
declare ok boolean;
begin
  begin
    perform set_config('request.jwt.claims','{"role":"anon","booking_id":"probe-live"}', true);
    set local role anon;
    insert into messages (conversation_id, sender_type, content)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','guest','hello from a live booking');
    ok := true;
  exception when insufficient_privilege then ok := false;
  end;
  reset role;
  insert into probe_result values ('LIVE property: guest can send (guest chat works)', ok, true);

  begin
    perform set_config('request.jwt.claims','{"role":"anon","booking_id":"probe-dead"}', true);
    set local role anon;
    insert into messages (conversation_id, sender_type, content)
    values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','guest','message onto a tombstone');
    ok := true;
  exception when insufficient_privilege then ok := false;
  end;
  reset role;
  insert into probe_result values ('DELETED property: guest can send (must be false)', ok, false);
end $$;

select scenario, allowed, expected,
       case when allowed = expected then 'PASS' else 'FAIL' end as verdict
from probe_result;

rollback;


-- ─────────────────────────────────────────────────────────────────────────────
-- BACKOUT (restores the pre-2026-07-14 policy)
-- ─────────────────────────────────────────────────────────────────────────────
-- drop policy if exists "guest inserts own messages" on public.messages;
-- create policy "guest inserts own messages"
--   on public.messages for insert to anon
--   with check (
--     sender_type = 'guest'
--     and conversation_id in (
--       select c.id from public.conversations c
--       where c.booking_id = (auth.jwt() ->> 'booking_id')
--     )
--   );
-- drop function if exists public.conversation_property_is_live(uuid);
