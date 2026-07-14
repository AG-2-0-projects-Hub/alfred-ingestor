-- Environment parity — the SWITCHES, not just the objects.
--
-- Run this in the SQL editor of BOTH projects (staging `gcxxilzfhwlsjcvtpsvj`
-- and prod `ylaooctefesedrecshic`), save each result as JSON, then:
--
--     python3 _tests/env_parity.py --diff staging.json prod.json
--
-- The original "zero-delta" schema check compared tables/policies/indexes and
-- reported clean while three things that reached production were different:
-- the `supabase_realtime` publication was missing (dashboard never live-updated),
-- nobody had checked whether RLS was actually switched ON (`relrowsecurity` —
-- a policy on a table with RLS off is inert), and nobody had checked which API
-- key each frontend shipped (prod served `service_role` publicly for a day).

select json_build_object(
  -- RLS is a SWITCH. Policies without it are decoration.
  'rls', (
    select json_object_agg(c.relname, json_build_object(
             'rls_enabled', c.relrowsecurity,
             'policies',    (select count(*) from pg_policy p where p.polrelid = c.oid)))
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r'
  ),

  -- Realtime streams ONLY tables in this publication. Not part of table DDL,
  -- which is exactly why the schema copy silently dropped it.
  'realtime_publication', (
    select coalesce(json_agg(tablename order by tablename), '[]'::json)
    from pg_publication_tables where pubname = 'supabase_realtime'
  ),

  'buckets', (
    select coalesce(json_agg(json_build_object(
             'id', id, 'public', public, 'size_limit', file_size_limit)
             order by id), '[]'::json)
    from storage.buckets
  ),

  'storage_policies', (
    select count(*) from pg_policy p
    join pg_class c on c.oid = p.polrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'storage'
  ),

  'functions', (
    select coalesce(json_agg(p.proname order by p.proname), '[]'::json)
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
  ),

  'triggers', (
    select coalesce(json_agg(t.tgname order by t.tgname), '[]'::json)
    from pg_trigger t join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and not t.tgisinternal
  ),

  'cron_jobs', (
    select coalesce(json_agg(jobname order by jobname), '[]'::json)
    from cron.job
  ),

  'extensions', (
    select coalesce(json_agg(extname order by extname), '[]'::json)
    from pg_extension
  )
) as parity;
