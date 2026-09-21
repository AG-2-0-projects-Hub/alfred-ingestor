"""
POST /api/merge/{property_id}  — Gemini Merger: scraped + ingested → master_json
POST /api/resolve/{property_id} — Gemini Resolver: apply host conflict resolutions

Both endpoints are idempotent:
  /merge   returns 200 with current state if status is already past "Ingested"
  /resolve returns 200 with current state if status is already past "Conflict_Pending"

Status transitions:
  Ingested → Merging → Merged           (no conflicts)
  Ingested → Merging → Conflict_Pending (conflicts detected)
  Conflict_Pending → Trained           (all conflicts resolved)
  Conflict_Pending → Conflict_Pending  (partial resolution)

"Merging" added 2026-09-16 (Phase 2, background ingest worker): a transient
in-flight state entered via supabase_client.claim_merge's atomic
Ingested->Merging transition, so a retried/duplicate merge task (Cloud Tasks
retry, or a host mashing the /resume button) can never run two Gemini merges
concurrently for the same property. _run_merge_and_save below is the actual
merge logic, shared between this HTTP endpoint (host-triggered, still
guarded by the Ingested-only check) and routers/ingest_worker.py's
merge-step task (background-triggered, already past claim_merge when it
calls this).
"""

import asyncio
import json
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from services import supabase_client
from services import gemini_merge_resolve

router = APIRouter()

_POST_MERGE_STATUSES = {"Merged", "Conflict_Pending", "Trained", "Fully_Trained"}
_POST_RESOLVE_STATUSES = {"Trained", "Fully_Trained"}


class Resolution(BaseModel):
    field: str
    value: str
    input_method: str = "selected"


class ResolveRequest(BaseModel):
    resolutions: list[Resolution]


def has_mergeable_content(prop: dict) -> bool:
    """True if there's anything for the merger to work with. Callers check
    this BEFORE calling run_merge_and_save — kept separate (rather than
    folded into that function) so each caller can report the empty-content
    case in its own terms: the HTTP endpoint as a 422, the background
    merge-step task as a terminal 'failed' state on the run."""
    return bool((prop.get("scraped_markdown") or "").strip()) or bool(
        (prop.get("ingested_markdown") or "").strip()
    )


async def run_merge_and_save(
    property_id: str, prop: dict, expected_run_id: str | None = None
) -> dict:
    """Core merge logic: run the Gemini merger and persist the result. Callers
    own the status guard/transition (merge_property below checks 'Ingested';
    ingest_worker's merge-step task already won claim_merge's Ingested->Merging
    race before calling this) AND the has_mergeable_content check above — this
    function assumes both are already satisfied and does the work
    unconditionally. May raise ValueError if the Gemini call itself fails
    (e.g. malformed response) — a genuine upstream failure, distinct from the
    empty-content case above.

    expected_run_id (2026-09-19): passed through to save_merge_result so the
    final write is fenced against a Stop landing during the Gemini call
    itself, not just at claim_merge's entry — see that function's docstring.
    None for the host-triggered /merge endpoint below, which has no run_id.
    """
    scraped = prop.get("scraped_markdown") or ""
    ingested = prop.get("ingested_markdown") or ""

    result = await gemini_merge_resolve.run_merger(
        scraped, ingested, prop.get("name") or "", prop.get("curated_photos")
    )

    has_conflicts = result.get("_conflicts_summary", {}).get("_has_conflicts", False)
    new_status = "Conflict_Pending" if has_conflicts else "Merged"
    new_conflict_status = "pending" if has_conflicts else "none"

    saved = await asyncio.to_thread(
        supabase_client.save_merge_result,
        property_id, result, new_status, new_conflict_status, expected_run_id,
    )
    if not saved:
        # Fenced out — the host clicked Stop while this merge was running.
        # Discard the result; cancel_initial_ingest_run already reset the row.
        return {"status": None, "has_conflicts": False, "master_json": None}

    return {
        "status": new_status,
        "has_conflicts": has_conflicts,
        "master_json": result,
    }


@router.post("/merge/{property_id}")
async def merge_property(property_id: str):
    prop = await asyncio.to_thread(supabase_client.get_property_for_merge, property_id)
    if prop is None:
        raise HTTPException(status_code=404, detail="Property not found.")

    status = prop.get("status", "")

    if status in _POST_MERGE_STATUSES:
        return {
            "status": status,
            "has_conflicts": status == "Conflict_Pending",
            "master_json": prop.get("master_json"),
            "message": "Already merged — returning current state.",
        }

    if status == "Merging":
        # A background merge-step task already won the claim and is running
        # right now (or a retry of it is) — do not start a second Gemini
        # merge call for the same property. The host will see this flip to
        # Merged/Conflict_Pending via realtime once it finishes.
        return {
            "status": status,
            "has_conflicts": False,
            "master_json": prop.get("master_json"),
            "message": "Merge already in progress.",
        }

    if status != "Ingested":
        raise HTTPException(
            status_code=422,
            detail=f"Cannot merge property with status '{status}'. Expected 'Ingested'.",
        )

    if not has_mergeable_content(prop):
        raise HTTPException(
            status_code=422,
            detail="Both scraped_markdown and ingested_markdown are empty.",
        )

    try:
        return await run_merge_and_save(property_id, prop)
    except ValueError as exc:
        raise HTTPException(status_code=502, detail=str(exc))


@router.post("/resolve/{property_id}")
async def resolve_conflicts(property_id: str, req: ResolveRequest):
    prop = await asyncio.to_thread(supabase_client.get_property_for_resolve, property_id)
    if prop is None:
        raise HTTPException(status_code=404, detail="Property not found.")

    status = prop.get("status", "")

    if status in _POST_RESOLVE_STATUSES:
        # Same response shape as every other branch below — a duplicate/
        # retried call (e.g. a client-side timeout retry racing a request
        # that actually succeeded) used to come back missing `master_json`
        # entirely, which crashed the frontend's unconditional cast.
        return {
            "status": status,
            "message": "Already resolved — returning current state.",
            "master_json": prop.get("master_json"),
        }

    if status != "Conflict_Pending":
        raise HTTPException(
            status_code=422,
            detail=f"Cannot resolve property with status '{status}'. Expected 'Conflict_Pending'.",
        )

    master_json = prop.get("master_json")
    if not master_json:
        raise HTTPException(
            status_code=422,
            detail="master_json is missing — run /merge first.",
        )

    resolutions_payload = [r.model_dump() for r in req.resolutions]

    try:
        result = await gemini_merge_resolve.run_resolver(master_json, resolutions_payload)
    except ValueError as exc:
        raise HTTPException(status_code=502, detail=str(exc))

    updated_master = result.get("master_json", {})
    history_entry = result.get("resolution_history")

    remaining = updated_master.get("_conflicts_summary", {}).get("_conflict_count", 0)
    new_status = "Trained" if remaining == 0 else "Conflict_Pending"
    new_conflict_status = "resolved" if remaining == 0 else "pending"

    history_text = json.dumps(history_entry, ensure_ascii=False) if history_entry else ""

    await asyncio.to_thread(
        supabase_client.save_resolve_result,
        property_id, updated_master, history_text, history_entry,
        new_status, new_conflict_status,
    )

    return {
        "status": new_status,
        "remaining_conflicts": remaining,
        "master_json": updated_master,
    }
