-- 2026-09-16 — Background ingest worker (Cloud Tasks, per-file), recovery + partial-failure UX
--
-- STATUS
--   staging (gcxxilzfhwlsjcvtpsvj) : APPLIED via MCP 2026-09-16
--   prod    (ylaooctefesedrecshic) : NOT YET APPLIED — run alongside the eventual staging→main merge
--
-- Every migration must be applied to BOTH projects (post-split rule, CONTEXT.md).
--
-- WHY
--   Train Now / Add Property run file processing inside a single synchronous
--   /api/ingest request. Cloud Run kills that request at a hard 300s platform
--   timeout independent of any app-level retry logic; when it fires, the
--   property row is orphaned at status='Ingesting' with no final status ever
--   written (confirmed live 2026-09-15/16 — see
--   _Context/Train_Now_Reliability_and_QA_Process_Plan_2026-09-15.md items 1+3,
--   and a real stuck property fixed by hand mid-session 2026-09-16). This
--   migration adds the DB-side state needed to move file-processing to a
--   Cloud-Tasks-dispatched per-file worker (see plan
--   C:\Users\San_8\.claude\plans\clever-seeking-horizon.md, "Phase 2").
--
--   New columns on `properties`:
--     ingest_run_id       — fencing token. Every worker task no-ops if the
--                           run_id it was dispatched for no longer matches the
--                           row's current run_id (e.g. a zombie task from a run
--                           that was superseded by a Resume-triggered restart).
--     ingest_files         — per-file authoritative state, jsonb map:
--                           { "<filename>": {state, attempts, error, updated_at} }
--                           state in pending|running|done|skipped|failed.
--                           Superset of file_fingerprints (which stays as-is —
--                           it's the cross-run dedupe key hash_guard reads);
--                           this also records failures, which are recorded
--                           NOWHERE today (SSE events are ephemeral).
--     ingest_heartbeat_at — touched on claim/progress/completion. Staleness of
--                           this timestamp (not the status string alone) is
--                           what the frontend/watchdog use to detect a
--                           genuinely stalled run vs. one still working.
--     ingest_stage        — coarse stage label ('scraping'|'processing'|
--                           'merging') for UI copy; not load-bearing for logic.
--
--   Three RPC functions, because a plain UPDATE cannot atomically
--   read-modify-write a jsonb column under concurrent per-file workers
--   (confirmed by reading supabase_client.append_ingested_markdown and
--   update_file_fingerprints — both are non-atomic read-then-write today,
--   which is only safe because file processing is currently sequential):
--
--     ingest_claim_file    — worker calls this before processing a file.
--                           Marks it 'running', bumps attempts, touches
--                           heartbeat. No-ops (returns false) on a run_id
--                           mismatch, so a zombie task from a superseded run
--                           can never claim work.
--     ingest_record_file_result — worker calls this after processing. Atomic:
--                           markdown concat (only on success) + fingerprint
--                           jsonb_set (only on success) + per-file state
--                           update + heartbeat touch, one statement. No-ops on
--                           a run_id mismatch, same fencing as above.
--     ingest_maybe_complete — worker calls this after every file reaches a
--                           terminal state. Atomically flips status
--                           'Ingesting' -> 'Ingested'/'Ingest_Error' ONLY if
--                           every entry in ingest_files is terminal, guarded by
--                           `WHERE status = 'Ingesting'` so N racing finishers
--                           produce exactly one winner. Returns the new status
--                           text if THIS call performed the transition (so the
--                           caller knows to enqueue the merge task), else NULL.
--
--   Existing columns/functions untouched. `file_fingerprints`, `master_json`,
--   `scraped_markdown`, `ingested_markdown` keep their current meaning and
--   current non-worker callers (add-knowledge, query-knowledge) unaffected.
--
-- REVERSIBILITY
--   Fully additive — new nullable columns (ingest_files defaults to '{}'),
--   three new functions. Nothing existing is altered or dropped. Safe to
--   apply without a data backfill; existing rows simply have ingest_files='{}'
--   until their next Train Now run populates it.


-- ── DDL — columns ───────────────────────────────────────────────────────────

alter table public.properties
  add column if not exists ingest_run_id uuid,
  add column if not exists ingest_files jsonb not null default '{}'::jsonb,
  add column if not exists ingest_heartbeat_at timestamptz,
  add column if not exists ingest_stage text;


-- ── DDL — functions ─────────────────────────────────────────────────────────

create or replace function public.ingest_claim_file(
  p_property_id uuid,
  p_run_id uuid,
  p_filename text
) returns boolean
language plpgsql
as $$
declare
  v_prev jsonb;
  v_attempts int;
begin
  select ingest_files -> p_filename into v_prev
    from public.properties
   where id = p_property_id and ingest_run_id = p_run_id
   for update;

  if not found then
    return false;  -- run_id mismatch (or property gone) — fencing
  end if;

  v_attempts := coalesce((v_prev ->> 'attempts')::int, 0) + 1;

  update public.properties
     set ingest_files = jsonb_set(
           ingest_files, array[p_filename],
           jsonb_build_object(
             'state', 'running',
             'attempts', v_attempts,
             'error', null,
             'updated_at', now()
           ),
           true
         ),
         ingest_heartbeat_at = now()
   where id = p_property_id and ingest_run_id = p_run_id;

  return true;
end;
$$;

create or replace function public.ingest_record_file_result(
  p_property_id uuid,
  p_run_id uuid,
  p_filename text,
  p_state text,               -- 'done' | 'failed'
  p_markdown text default null,
  p_fingerprint_size bigint default null,
  p_error text default null
) returns boolean
language plpgsql
as $$
declare
  v_attempts int;
begin
  if p_state not in ('done', 'failed') then
    raise exception 'ingest_record_file_result: invalid state %', p_state;
  end if;

  select coalesce((ingest_files -> p_filename ->> 'attempts')::int, 1) into v_attempts
    from public.properties
   where id = p_property_id and ingest_run_id = p_run_id
   for update;

  if not found then
    return false;  -- run_id mismatch — fencing
  end if;

  update public.properties
     set ingested_markdown = case
           when p_state = 'done' and p_markdown is not null
           then coalesce(ingested_markdown, '') || p_markdown
           else ingested_markdown
         end,
         file_fingerprints = case
           when p_state = 'done' and p_fingerprint_size is not null
           then jsonb_set(coalesce(file_fingerprints, '{}'::jsonb), array[p_filename], to_jsonb(p_fingerprint_size))
           else file_fingerprints
         end,
         ingest_files = jsonb_set(
           ingest_files, array[p_filename],
           jsonb_build_object(
             'state', p_state,
             'attempts', v_attempts,
             'error', p_error,
             'updated_at', now()
           ),
           true
         ),
         ingest_heartbeat_at = now()
   where id = p_property_id and ingest_run_id = p_run_id;

  return true;
end;
$$;

create or replace function public.ingest_maybe_complete(
  p_property_id uuid,
  p_run_id uuid
) returns text
language plpgsql
as $$
declare
  v_files jsonb;
  v_scraped text;
  v_pending_or_running boolean;
  v_any_done boolean;
  v_new_status text;
begin
  select ingest_files, scraped_markdown into v_files, v_scraped
    from public.properties
   where id = p_property_id and ingest_run_id = p_run_id
   for update;

  if not found then
    return null;  -- run_id mismatch
  end if;

  select bool_or(f.value ->> 'state' in ('pending', 'running')) into v_pending_or_running
    from jsonb_each(coalesce(v_files, '{}'::jsonb)) f;

  if coalesce(v_pending_or_running, false) then
    return null;  -- still work outstanding — not done yet
  end if;

  select bool_or(f.value ->> 'state' in ('done', 'skipped')) into v_any_done
    from jsonb_each(coalesce(v_files, '{}'::jsonb)) f;

  v_new_status := case
    when coalesce(v_any_done, false) or (v_scraped is not null and v_scraped <> '')
    then 'Ingested'
    else 'Ingest_Error'
  end;

  update public.properties
     set status = v_new_status,
         ingest_heartbeat_at = now()
   where id = p_property_id and ingest_run_id = p_run_id and status = 'Ingesting';

  if found then
    return v_new_status;  -- this call performed the transition — caller enqueues merge
  end if;

  return null;  -- someone else already completed it
end;
$$;


-- ── VERIFY — run this SEPARATELY, after the DDL above has been executed ──────
-- Read-only: no transaction, nothing to roll back.
--
-- select 'columns' as check,
--        case when count(*) = 4 then 'PASS' else 'FAIL' end as result
--   from information_schema.columns
--  where table_schema = 'public' and table_name = 'properties'
--    and column_name in ('ingest_run_id', 'ingest_files', 'ingest_heartbeat_at', 'ingest_stage');
--
-- select 'functions' as check,
--        case when count(*) = 3 then 'PASS' else 'FAIL' end as result
--   from pg_proc
--  where pronamespace = 'public'::regnamespace
--    and proname in ('ingest_claim_file', 'ingest_record_file_result', 'ingest_maybe_complete');
