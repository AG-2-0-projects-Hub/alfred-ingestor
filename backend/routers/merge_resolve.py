"""
POST /api/merge/{property_id}  — Gemini Merger: scraped + ingested → master_json
POST /api/resolve/{property_id} — Gemini Resolver: apply host conflict resolutions

Both endpoints are idempotent:
  /merge   returns 200 with current state if status is already past "Ingested"
  /resolve returns 200 with current state if status is already past "Conflict_Pending"

Status transitions:
  Ingested → Merged           (no conflicts)
  Ingested → Conflict_Pending (conflicts detected)
  Conflict_Pending → Trained           (all conflicts resolved)
  Conflict_Pending → Conflict_Pending  (partial resolution)
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

    if status != "Ingested":
        raise HTTPException(
            status_code=422,
            detail=f"Cannot merge property with status '{status}'. Expected 'Ingested'.",
        )

    scraped = prop.get("scraped_markdown") or ""
    ingested = prop.get("ingested_markdown") or ""
    if not scraped and not ingested:
        raise HTTPException(
            status_code=422,
            detail="Both scraped_markdown and ingested_markdown are empty.",
        )

    try:
        result = await gemini_merge_resolve.run_merger(scraped, ingested)
    except ValueError as exc:
        raise HTTPException(status_code=502, detail=str(exc))

    has_conflicts = result.get("_conflicts_summary", {}).get("_has_conflicts", False)
    new_status = "Conflict_Pending" if has_conflicts else "Merged"
    new_conflict_status = "pending" if has_conflicts else "none"

    await asyncio.to_thread(
        supabase_client.save_merge_result,
        property_id, result, new_status, new_conflict_status,
    )

    return {
        "status": new_status,
        "has_conflicts": has_conflicts,
        "master_json": result,
    }


@router.post("/resolve/{property_id}")
async def resolve_conflicts(property_id: str, req: ResolveRequest):
    prop = await asyncio.to_thread(supabase_client.get_property_for_resolve, property_id)
    if prop is None:
        raise HTTPException(status_code=404, detail="Property not found.")

    status = prop.get("status", "")

    if status in _POST_RESOLVE_STATUSES:
        return {"status": status, "message": "Already resolved — returning current state."}

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
