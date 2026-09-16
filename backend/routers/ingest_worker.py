"""
Cloud Tasks worker endpoints for background ingest processing (Phase 2,
2026-09-16). Cloud Run kills the synchronous /api/ingest request at a hard
300s platform timeout, independent of any app-level retry/timeout tuning —
see migrations/2026-09-16_ingest_background_worker.sql for the full incident
history. These endpoints move file-processing off that request entirely:
POST /api/ingest fires ONE Cloud Task ('start'), which fans out one task per
file, each running as its own fresh HTTP request with its own fresh 300s
budget. All state lives on the properties row (ingest_run_id/ingest_files/
ingest_heartbeat_at, via supabase_client's ingest_* helpers) — never in
memory here, since each task is a separate process/request.

Auth: same shared-secret pattern as telegram.py/whatsapp.py's worker
endpoints (_check_secret below) — the service is publicly reachable, so a
header secret guards these instead of IAM. Reuses TELEGRAM_WEBHOOK_SECRET —
task_queue.enqueue's header is hardcoded to that name already, and it's
already just an internal shared token (not Telegram's own credential), so
extending task_queue.py for a second, functionally-identical secret would
add surface area for no real security benefit.

Task fencing: every task carries the run_id it was dispatched for. A
property has at most one LIVE run_id at a time (properties.ingest_run_id).
Resume or the watchdog minting a new one immediately fences out any
in-flight task from the old run, because every RPC call below is scoped
`WHERE ingest_run_id = p_run_id` and silently no-ops otherwise — this is what
makes a duplicate/zombie task safe rather than something to deduplicate.
"""

import asyncio
import os
import re
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel

from services import supabase_client, hash_guard, file_processor, task_queue
from routers.merge_resolve import run_merge_and_save, has_mergeable_content

router = APIRouter()

# Same per-file ceiling Phase 1 established for the old synchronous loop.
# Unrelated to Cloud Run's 300s request limit now (each file gets its own
# fresh request) — this is about not letting one hung Gemini call block a
# worker forever. Inner retry (genai_factory) already caps at ~70.5s
# (35s x 2 attempts), so 90s is a comfortable outer backstop.
_PER_FILE_TIMEOUT_S = 90

# Must match the ingest Cloud Tasks queue's --max-attempts at creation time.
# Used to detect "this is the last attempt Cloud Tasks will make" so a
# genuinely-exhausted file gets marked 'failed' instead of silently vanishing
# once Cloud Tasks gives up retrying it with nothing ever recording why.
_INGEST_MAX_TASK_ATTEMPTS = 5

# How long a heartbeat can go stale before a run is genuinely stuck, not just
# slow. Shared definition between the watchdog below and the frontend's own
# "show a Resume affordance" check, so both agree on the same threshold.
STALE_HEARTBEAT_S = 90
_WATCHDOG_INTERVAL_S = 120
_WATCHDOG_MAX_AUTO_RECOVERIES = 2


class _StartBody(BaseModel):
    property_id: str
    run_id: str


class _FileBody(BaseModel):
    property_id: str
    run_id: str
    filename: str


class _MergeBody(BaseModel):
    property_id: str


class _WatchdogBody(BaseModel):
    property_id: str
    run_id: str
    seq: int = 0


def _check_secret(request: Request) -> None:
    expected = os.environ.get("TELEGRAM_WEBHOOK_SECRET")
    provided = request.headers.get("X-Telegram-Bot-Api-Secret-Token")
    if not expected or provided != expected:
        raise HTTPException(status_code=403, detail="forbidden")


def _queue_name() -> str | None:
    return os.environ.get("INGEST_TASKS_QUEUE") or None


# Keeps references to local-dev fallback tasks alive — asyncio only holds a
# weak reference to a bare create_task() result, so without this the task
# can be garbage-collected mid-flight (a well-known asyncio gotcha).
_local_dev_tasks: set = set()


def dispatch_task(path: str, payload: dict, *, name: str | None = None, delay_seconds: int = 0) -> None:
    """Cloud Tasks where configured; a fire-and-forget local asyncio task
    otherwise. The local branch is dev-only convenience — CLOUD_TASKS_QUEUE is
    always set on both deployed Cloud Run services, so it never runs there,
    and it must not: silently running in-process on Cloud Run would quietly
    reintroduce the exact 300s-request bug this worker exists to fix, one
    layer deeper and harder to notice."""
    if task_queue.enabled():
        task_queue.enqueue(path, payload, name=name, delay_seconds=delay_seconds, queue=_queue_name())
        return
    handlers = {
        "/api/ingest/worker/start": run_start,
        "/api/ingest/worker/process-file": run_process_file,
        "/api/ingest/worker/merge-step": run_merge_step,
        "/api/ingest/worker/watchdog": run_watchdog,
    }
    task = asyncio.create_task(handlers[path](**payload))
    _local_dev_tasks.add(task)
    task.add_done_callback(_local_dev_tasks.discard)


def _is_stale(heartbeat_iso: str | None) -> bool:
    if not heartbeat_iso:
        return True
    try:
        ts = datetime.fromisoformat(heartbeat_iso.replace("Z", "+00:00"))
    except ValueError:
        return True
    return (datetime.now(timezone.utc) - ts).total_seconds() > STALE_HEARTBEAT_S


def _parse_thumbnail_url(scraped_markdown: str) -> str | None:
    match = re.search(r'\*\*Thumbnail:\*\*\s*(\S+)', scraped_markdown)
    return match.group(1).strip() if match else None


# ── start: scrape (if needed) + seed the run + fan out per-file tasks ───────

async def run_start(property_id: str, run_id: str) -> None:
    prop = await asyncio.to_thread(supabase_client.get_ingest_run, property_id)
    if prop is None or prop.get("ingest_run_id") != run_id:
        return  # fenced — a newer run superseded this one before it even started

    airbnb_url = (prop.get("airbnb_url") or "").strip()
    scraped_markdown = prop.get("scraped_markdown") or ""
    curated_photos: list[dict] = []
    rejected_photos: list[dict] = []

    if airbnb_url and not scraped_markdown:
        await asyncio.to_thread(supabase_client.touch_ingest_heartbeat, property_id, run_id, "scraping")
        scraper_url = os.environ.get("SCRAPER_URL", "").rstrip("/")
        if not scraper_url:
            print(f"ingest_worker.run_start: SCRAPER_URL not configured, aborting {property_id}")
            await asyncio.to_thread(supabase_client.update_status, property_id, "Ingest_Error")
            return
        try:
            import httpx
            async with httpx.AsyncClient(timeout=120.0) as http:
                resp = await http.post(f"{scraper_url}/scrape", json={"url": airbnb_url})
                resp.raise_for_status()
                scrape_data = resp.json()
                scraped_markdown = scrape_data.get("data", "")
                curated_photos = scrape_data.get("curated_photos") or []
                rejected_photos = scrape_data.get("rejected_photos") or []
        except Exception as exc:
            print(f"ingest_worker.run_start: scrape failed for {property_id}: {exc}")
            await asyncio.to_thread(supabase_client.update_status, property_id, "Ingest_Error")
            return  # REQ-28: abort — do not process files

        if scraped_markdown:
            try:
                await asyncio.to_thread(supabase_client.save_scraped_markdown, property_id, scraped_markdown)
            except Exception as exc:
                print(f"save_scraped_markdown failed (non-fatal): {exc}")
        if curated_photos or rejected_photos:
            try:
                await asyncio.to_thread(
                    supabase_client.save_photo_triage, property_id, curated_photos, rejected_photos
                )
            except Exception as exc:
                print(f"save_photo_triage failed (non-fatal): {exc}")
        thumbnail_url = _parse_thumbnail_url(scraped_markdown)
        if thumbnail_url:
            try:
                await asyncio.to_thread(supabase_client.upload_hero_image, property_id, thumbnail_url)
            except Exception as exc:
                print(f"Hero image upload failed (non-fatal): {exc}")

    await asyncio.to_thread(supabase_client.touch_ingest_heartbeat, property_id, run_id, "processing")

    files = await asyncio.to_thread(supabase_client.list_upload_files, property_id)
    fingerprints = prop.get("file_fingerprints") or {}

    file_states: dict[str, str] = {}
    to_process: list[str] = []
    for f in files:
        name = f["name"]
        size = (f.get("metadata") or {}).get("size") or 0
        fp_status = hash_guard.file_status(fingerprints, name, size)
        if fp_status == "skip":
            file_states[name] = "skipped"
        else:
            file_states[name] = "pending"
            to_process.append(name)

    # Re-seeds ingest_files with the real per-file plan — overwrites the '{}'
    # placeholder that begin_ingest_run (dispatcher) or resume_run wrote
    # before this task even knew the actual file list.
    await asyncio.to_thread(supabase_client.begin_ingest_run, property_id, run_id, file_states)

    if not to_process:
        # No files at all, or every file already fingerprinted identical —
        # go straight to the completion check; no file-worker task will ever
        # run to trigger it otherwise.
        await _finish_ordispatch_task_merge(property_id, run_id)
        return

    for name in to_process:
        dispatch_task(
            "/api/ingest/worker/process-file",
            {"property_id": property_id, "run_id": run_id, "filename": name},
            name=task_queue.sanitize_task_name(f"ing-{property_id}-{run_id}-{name}"),
        )

    dispatch_task(
        "/api/ingest/worker/watchdog",
        {"property_id": property_id, "run_id": run_id, "seq": 0},
        name=task_queue.sanitize_task_name(f"ing-wd-{property_id}-{run_id}-0"),
        delay_seconds=_WATCHDOG_INTERVAL_S,
    )


# ── process-file: claim, run, record; retry-or-terminal decided here ───────

async def run_process_file(property_id: str, run_id: str, filename: str, retry_count: int = 0) -> bool:
    """Returns False to signal the HTTP wrapper should respond 5xx (so Cloud
    Tasks retries with backoff); True means either it succeeded, terminally
    failed (exhausted retries), or was fenced — nothing further to do."""
    claimed = await asyncio.to_thread(supabase_client.claim_ingest_file, property_id, run_id, filename)
    if not claimed:
        return True  # fenced — a superseded run, nothing to do

    is_final_attempt = retry_count >= _INGEST_MAX_TASK_ATTEMPTS - 1
    succeeded = False

    try:
        data = await asyncio.to_thread(supabase_client.download_file, property_id, filename)
        size = len(data)

        current_task = asyncio.create_task(file_processor.process_file(filename, data))
        elapsed = 0
        while not current_task.done():
            if elapsed >= _PER_FILE_TIMEOUT_S:
                current_task.cancel()
                raise TimeoutError(f"No response after {_PER_FILE_TIMEOUT_S}s")
            try:
                await asyncio.wait_for(asyncio.shield(current_task), timeout=10)
            except asyncio.TimeoutError:
                elapsed += 10
                await asyncio.to_thread(supabase_client.touch_ingest_heartbeat, property_id, run_id)
        markdown = await current_task

        await asyncio.to_thread(
            supabase_client.record_ingest_file_result,
            property_id, run_id, filename, "done", markdown=markdown, fingerprint_size=size,
        )
        succeeded = True
    except Exception as exc:
        if is_final_attempt:
            await asyncio.to_thread(
                supabase_client.record_ingest_file_result,
                property_id, run_id, filename, "failed", error=str(exc),
            )
        else:
            print(f"ingest_worker.run_process_file: {filename} attempt {retry_count + 1} failed, will retry: {exc}")
            return False  # let Cloud Tasks retry — do NOT write a terminal state yet

    await _finish_ordispatch_task_merge(property_id, run_id)
    return True


async def _finish_ordispatch_task_merge(property_id: str, run_id: str) -> None:
    new_status = await asyncio.to_thread(supabase_client.maybe_complete_ingest, property_id, run_id)
    if new_status == "Ingested":
        dispatch_task(
            "/api/ingest/worker/merge-step",
            {"property_id": property_id},
            name=task_queue.sanitize_task_name(f"ing-merge-{property_id}-{run_id}"),
        )
    # new_status == "Ingest_Error": nothing usable, nothing to enqueue.
    # new_status is None: either work is still outstanding, or another worker
    # already won the transition (and, if applicable, already enqueued the
    # merge task) — this call has nothing further to do either way.


# ── merge-step: claim Ingested->Merging, then run the shared merge logic ───

async def run_merge_step(property_id: str) -> None:
    won = await asyncio.to_thread(supabase_client.claim_merge, property_id)
    if not won:
        return  # already Merging/past it — another task or host call got there first

    prop = await asyncio.to_thread(supabase_client.get_property_for_merge, property_id)
    if prop is None:
        return
    if not has_mergeable_content(prop):
        await asyncio.to_thread(supabase_client.update_status, property_id, "Ingest_Error")
        return
    try:
        await run_merge_and_save(property_id, prop)
    except ValueError as exc:
        print(f"ingest_worker.run_merge_step: merge failed for {property_id}: {exc}")
        await asyncio.to_thread(supabase_client.update_status, property_id, "Ingest_Error")


# ── watchdog: self-reschedules; auto-recovers a stale run, bounded ─────────

async def run_watchdog(property_id: str, run_id: str, seq: int = 0) -> None:
    prop = await asyncio.to_thread(supabase_client.get_ingest_run, property_id)
    if prop is None or prop.get("ingest_run_id") != run_id:
        return  # fenced — this run was superseded, its watchdog retires

    if prop.get("status") != "Ingesting":
        return  # run reached a terminal-for-this-watchdog state, stop rescheduling

    if not _is_stale(prop.get("ingest_heartbeat_at")):
        dispatch_task(
            "/api/ingest/worker/watchdog",
            {"property_id": property_id, "run_id": run_id, "seq": seq},
            name=task_queue.sanitize_task_name(f"ing-wd-{property_id}-{run_id}-{seq + 1}"),
            delay_seconds=_WATCHDOG_INTERVAL_S,
        )
        return

    if seq >= _WATCHDOG_MAX_AUTO_RECOVERIES:
        print(f"ingest_worker.run_watchdog: {property_id} stale past auto-recovery limit, leaving for manual Resume")
        return

    print(f"ingest_worker.run_watchdog: {property_id} run {run_id} stale, auto-recovering (attempt {seq + 1})")
    await resume_run(property_id)


async def resume_run(property_id: str) -> None:
    """Shared recovery: mint a fresh run_id (fences out the old run's zombie
    tasks) and dispatch a 'start' task, which recomputes the remaining file
    set from file_fingerprints via hash_guard — already-done files are
    skipped, not reprocessed. Used by both the watchdog above and the
    host-triggered /resume endpoint in routers/ingest.py."""
    new_run_id = str(uuid.uuid4())
    await asyncio.to_thread(supabase_client.update_status, property_id, "Ingesting")
    await asyncio.to_thread(supabase_client.begin_ingest_run, property_id, new_run_id, {})
    dispatch_task(
        "/api/ingest/worker/start",
        {"property_id": property_id, "run_id": new_run_id},
        name=task_queue.sanitize_task_name(f"ing-start-{property_id}-{new_run_id}"),
    )


# ── HTTP wrappers — Cloud Tasks calls these ─────────────────────────────────

@router.post("/ingest/worker/start")
async def worker_start(body: _StartBody, request: Request):
    _check_secret(request)
    await run_start(body.property_id, body.run_id)
    return {"ok": True}


@router.post("/ingest/worker/process-file")
async def worker_process_file(body: _FileBody, request: Request):
    _check_secret(request)
    retry_count = int(request.headers.get("X-CloudTasks-TaskRetryCount", "0") or "0")
    ok = await run_process_file(body.property_id, body.run_id, body.filename, retry_count=retry_count)
    if not ok:
        raise HTTPException(status_code=503, detail="transient failure, retry")
    return {"ok": True}


@router.post("/ingest/worker/merge-step")
async def worker_merge_step(body: _MergeBody, request: Request):
    _check_secret(request)
    await run_merge_step(body.property_id)
    return {"ok": True}


@router.post("/ingest/worker/watchdog")
async def worker_watchdog(body: _WatchdogBody, request: Request):
    _check_secret(request)
    await run_watchdog(body.property_id, body.run_id, body.seq)
    return {"ok": True}
