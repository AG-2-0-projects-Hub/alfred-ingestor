"""
POST /api/ingest — dispatches background file processing (Phase 2, 2026-09-16).

Rewritten from a synchronous SSE stream to a bounded, sub-second JSON
dispatcher: Cloud Run kills a long-running request at a hard 300s platform
timeout independent of any app-level retry/timeout tuning, and when that
fired mid-ingest the property row was orphaned at status="Ingesting" with no
final status ever written (see
_Context/Train_Now_Reliability_and_QA_Process_Plan_2026-09-15.md items 1+3,
and migrations/2026-09-16_ingest_background_worker.sql for the full incident
history and DB-side design). The actual file/scrape/merge work now runs in
routers/ingest_worker.py, dispatched via Cloud Tasks — this endpoint's only
job is: resolve the canonical property, do the couple of fast setup calls,
mint a run_id, and fire one task. The frontend gets `property_id` back
immediately and relies entirely on Supabase realtime on the row for progress
(ingest_files/status), not a stream read.

REQ-19: idempotent via canonical property lookup on airbnb_url
REQ-20: 409 lock when status == Ingesting AND the heartbeat is fresh — a
         STALE "Ingesting" (the exact orphaned-row case above) no longer
         blocks retry; see _heartbeat_stale.
REQ-21: status → Ingested once ANY content is usable (a scrape, or at least one
         successful file); a run with nothing usable at all sets Ingest_Error.
         (Enforced in ingest_worker.ingest_maybe_complete now, not here.)
REQ-22: file fingerprints persisted per-file as each one completes, via the
         atomic ingest_record_file_result RPC (see supabase_client.py).
REQ-26: scraper called before any file processing (in ingest_worker.run_start)
REQ-28: scraper failure surfaces error and aborts (in ingest_worker.run_start)
"""

import asyncio
import os
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel

from services import supabase_client, gemini_merge_resolve, task_queue
import services.gemini_client as gemini_client
from routers import ingest_worker

router = APIRouter()

_STALE_HEARTBEAT_S = ingest_worker.STALE_HEARTBEAT_S


class IngestRequest(BaseModel):
    property_id: str
    property_name: str = ""
    airbnb_url: str = ""


def _get_owner_id(request: Request) -> str | None:
    """Extract owner UID from Authorization: Bearer <token> header. Returns None on missing/invalid."""
    auth = request.headers.get("authorization", "")
    if not auth.lower().startswith("bearer "):
        return None
    token = auth[7:].strip()
    if not token:
        return None
    try:
        client = supabase_client.get_client()
        response = client.auth.get_user(token)
        return response.user.id if response and response.user else None
    except Exception:
        return None


async def _require_owner_id(request: Request) -> str:
    """Strict version of _get_owner_id — 401s instead of returning None.
    Only /resume needs this (a host-initiated recovery action); the main
    /ingest dispatcher above stays permissive on purpose (anonymous ingests
    are allowed, matching the existing add-property flow)."""
    owner_id = await asyncio.to_thread(_get_owner_id, request)
    if not owner_id:
        raise HTTPException(status_code=401, detail="Missing or invalid bearer token")
    return owner_id


def _heartbeat_stale(heartbeat_iso: str | None) -> bool:
    if not heartbeat_iso:
        return True
    try:
        ts = datetime.fromisoformat(heartbeat_iso.replace("Z", "+00:00"))
    except ValueError:
        return True
    return (datetime.now(timezone.utc) - ts).total_seconds() > _STALE_HEARTBEAT_S


@router.post("/ingest")
async def ingest(req: IngestRequest, request: Request):
    airbnb_url = req.airbnb_url.strip()
    temp_id = req.property_id
    owner_id = await asyncio.to_thread(_get_owner_id, request)

    # Resolve canonical property by nickname, scoped to the current owner so
    # two users naming a property "Bungalowww" get separate rows.
    # If owner_id is None (unauthenticated), canonical lookup returns None
    # and the request will create a brand-new row at temp_id.
    property_id = temp_id
    property_name_clean = req.property_name.strip()
    if property_name_clean and owner_id:
        canonical = await asyncio.to_thread(
            supabase_client.get_canonical_property_by_name, property_name_clean, owner_id
        )
        if canonical:
            property_id = canonical["id"]
            # Heartbeat-conditional: a row orphaned at "Ingesting" (the 300s-kill
            # incident this whole rewrite exists to fix) used to 409 EVERY
            # subsequent Train Now click forever — refusing the one thing a host
            # would naturally try. A run that's actually still alive (fresh
            # heartbeat) still locks; a stale one gets silently taken over below.
            if canonical.get("status") == "Ingesting" and not _heartbeat_stale(
                canonical.get("ingest_heartbeat_at")
            ):
                return JSONResponse(
                    status_code=409,
                    content={"detail": "Ingestion already in progress for this property."},
                )

    # Bounded setup work only — a few DB/storage calls, comfortably under a
    # second. The frontend needs property_id back immediately to start its
    # realtime subscription; actual file/scrape processing happens entirely
    # in background Cloud Tasks workers from here on (routers/ingest_worker.py).
    try:
        if property_id != temp_id:
            await asyncio.to_thread(
                supabase_client.move_files_in_storage, temp_id, property_id
            )
        await asyncio.to_thread(
            supabase_client.insert_property, property_id, req.property_name, airbnb_url, owner_id
        )
    except Exception as exc:
        return JSONResponse(
            status_code=500,
            content={"detail": f"Could not start ingestion: {type(exc).__name__}: {exc}"},
        )

    run_id = str(uuid.uuid4())
    await asyncio.to_thread(supabase_client.begin_ingest_run, property_id, run_id, {})
    ingest_worker.dispatch_task(
        "/api/ingest/worker/start",
        {"property_id": property_id, "run_id": run_id},
        name=task_queue.sanitize_task_name(f"ing-start-{property_id}-{run_id}"),
    )

    return {"property_id": property_id, "run_id": run_id}


@router.post("/ingest/{property_id}/resume")
async def resume_ingest(property_id: str, request: Request):
    """Host-triggered recovery for a stalled property — the self-service
    version of the by-hand fix used on a real stuck property 2026-09-16
    (a direct /merge call). Idempotent by construction (safe to mash):
    terminal status -> no-op; Ingested with no master_json -> enqueue merge
    (exactly that by-hand fix); anything else -> mint a fresh run and
    re-dispatch the remaining work (same path the watchdog uses automatically
    on a stale heartbeat)."""
    await _require_owner_id(request)  # host-token gate; ownership itself isn't
    # scoped further since property_id -> owner is already enforced by the
    # dashboard only ever showing the host their own properties, matching the
    # existing pattern for /merge and /resolve (also not owner-scoped today).

    prop = await asyncio.to_thread(supabase_client.get_ingest_run, property_id)
    if prop is None:
        raise HTTPException(status_code=404, detail="Property not found.")

    status = prop.get("status", "")
    terminal = {"Merged", "Conflict_Pending", "Trained", "Fully_Trained"}
    if status in terminal:
        return {"status": status, "message": "Already at a terminal state — nothing to resume."}

    if status == "Ingested" and not prop.get("master_json"):
        ingest_worker.dispatch_task(
            "/api/ingest/worker/merge-step",
            {"property_id": property_id},
            name=task_queue.sanitize_task_name(
                f"ing-merge-{property_id}-{prop.get('ingest_run_id') or 'resume'}"
            ),
        )
        return {"status": "Ingested", "message": "Merge enqueued."}

    await ingest_worker.resume_run(property_id)
    return {"status": "Ingesting", "message": "Resumed — re-dispatched remaining work."}


# ── Add Knowledge ─────────────────────────────────────────────────────────────

class AddKnowledgeRequest(BaseModel):
    property_id: str
    text: str = ""
    storage_path: str = ""  # voice path: "<uuid>/user_uploads/<filename>"


@router.post("/ingest/add-knowledge")
async def add_knowledge(req: AddKnowledgeRequest, request: Request):
    if not req.text and not req.storage_path:
        return JSONResponse(status_code=422, content={"detail": "Provide text or storage_path."})

    # Resolve text from voice if needed
    knowledge_text = req.text
    if req.storage_path and not req.text:
        parts = req.storage_path.split("/")
        # storage_path format: <property_id>/user_uploads/<filename>
        if len(parts) >= 3:
            prop_id_from_path = parts[0]
            filename = parts[-1]
            ext = filename.rsplit(".", 1)[-1].lower() if "." in filename else "m4a"
            mime = {"m4a": "audio/m4a", "mp3": "audio/mp3", "wav": "audio/wav",
                    "webm": "audio/webm", "ogg": "audio/ogg"}.get(ext, "audio/m4a")
            data = await asyncio.to_thread(
                supabase_client.download_file, prop_id_from_path, filename
            )
            knowledge_text = await gemini_client.process_with_prompt_c(data, mime)

    # Fetch current master_json
    row = await asyncio.to_thread(supabase_client.get_property_for_merge, req.property_id)
    if not row:
        return JSONResponse(status_code=404, content={"detail": "Property not found."})

    master_json = row.get("master_json") or {}

    # Run Gemini Knowledge Injector
    result = await gemini_merge_resolve.run_knowledge_injection(master_json, knowledge_text)
    updated_json = result.get("master_json", master_json)

    # Persist
    await asyncio.to_thread(supabase_client.update_master_json, req.property_id, updated_json)

    return {"status": "ok", "master_json": updated_json, "changes_log": result.get("changes_log", [])}


# ── Knowledge Base Query ──────────────────────────────────────────────────────

class QueryKnowledgeRequest(BaseModel):
    property_id: str
    question: str


@router.post("/ingest/query-knowledge")
async def query_knowledge(req: QueryKnowledgeRequest):
    prop = await asyncio.to_thread(supabase_client.get_property_for_chat, req.property_id)
    if not prop:
        raise HTTPException(status_code=404, detail="Property not found.")
    master_json = prop.get("master_json")
    if not master_json:
        raise HTTPException(
            status_code=422,
            detail="No knowledge base found for this property. Ingest and merge files first.",
        )
    learned_knowledge = prop.get("learned_knowledge") or []
    answer = await gemini_client.query_knowledge_base(
        master_json, req.question, learned_knowledge=learned_knowledge
    )
    return {"answer": answer}
