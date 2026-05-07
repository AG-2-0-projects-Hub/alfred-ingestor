"""
POST /api/ingest — triggers sequential file processing over SSE.

REQ-19: idempotent via canonical property lookup on airbnb_url
REQ-20: 409 lock when status == Ingesting
REQ-21: atomic status — only sets Ingested when ALL files succeed
REQ-22: file fingerprints stored in JSONB column
REQ-26: scraper called before any file processing
REQ-28: scraper failure surfaces error and aborts

SSE event format:
  data: {"file": "<name>", "status": "queued|processing|heartbeat|done|already_in_db|file_updated|error", "message": "..."}

System events:
  data: {"file": "(system)", "status": "property_id", "message": "<canonical_id>"}
"""

import asyncio
import json
import os
import re
from fastapi import APIRouter, Request
from fastapi.responses import StreamingResponse, JSONResponse
from pydantic import BaseModel
import httpx

from services import supabase_client, hash_guard, file_processor, gemini_merge_resolve
import services.gemini_client as gemini_client

router = APIRouter()


class IngestRequest(BaseModel):
    property_id: str
    property_name: str = ""
    airbnb_url: str = ""


def _event(file: str, status: str, message: str = "") -> str:
    payload = json.dumps({"file": file, "status": status, "message": message})
    return f"data: {payload}\n\n"


def _parse_thumbnail_url(scraped_markdown: str) -> str | None:
    match = re.search(r'\*\*Thumbnail:\*\*\s*(\S+)', scraped_markdown)
    return match.group(1).strip() if match else None


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


@router.post("/ingest")
async def ingest(req: IngestRequest, request: Request):
    airbnb_url = req.airbnb_url.strip()
    temp_id = req.property_id
    owner_id = await asyncio.to_thread(_get_owner_id, request)

    # Resolve canonical property and enforce 409 lock BEFORE opening SSE stream (REQ-20)
    property_id = temp_id
    if airbnb_url:
        canonical = await asyncio.to_thread(supabase_client.get_canonical_property, airbnb_url)
        if canonical:
            property_id = canonical["id"]
            if canonical.get("status") == "Ingesting":
                return JSONResponse(
                    status_code=409,
                    content={"detail": "Ingestion already in progress for this property."},
                )

    async def stream():
        current_task: asyncio.Task | None = None
        try:
            # Emit resolved canonical ID so frontend knows which row to poll (REQ-19)
            yield _event("(system)", "property_id", property_id)

            # Move uploads from temp folder to canonical folder when IDs differ (REQ-19)
            if property_id != temp_id:
                await asyncio.to_thread(
                    supabase_client.move_files_in_storage, temp_id, property_id
                )

            # Upsert property row then set Ingesting (REQ-20)
            await asyncio.to_thread(
                supabase_client.insert_property, property_id, req.property_name, airbnb_url, owner_id
            )
            await asyncio.to_thread(supabase_client.update_status, property_id, "Ingesting")

            # Call scraper before any file processing (REQ-26)
            scraped_markdown = ""
            if airbnb_url:
                scraper_url = os.environ.get("SCRAPER_URL", "").rstrip("/")
                if not scraper_url:
                    yield _event("(scrape)", "error", "SCRAPER_URL not configured.")
                    await asyncio.to_thread(supabase_client.update_status, property_id, "Ingest_Error")
                    return
                try:
                    async with httpx.AsyncClient(timeout=120.0) as http:
                        resp = await http.post(
                            f"{scraper_url}/scrape", json={"url": airbnb_url}
                        )
                        resp.raise_for_status()
                        scraped_markdown = resp.json().get("data", "")
                except Exception as exc:
                    yield _event("(scrape)", "error", f"Scraping failed: {exc}")
                    await asyncio.to_thread(supabase_client.update_status, property_id, "Ingest_Error")
                    return  # REQ-28: abort — do not process files

                # Persist scraped_markdown from ingestor side (REQ-27 reliability —
                # scraper also writes this, but its Supabase creds may be unset)
                if scraped_markdown:
                    try:
                        await asyncio.to_thread(
                            supabase_client.save_scraped_markdown, property_id, scraped_markdown
                        )
                    except Exception as exc:
                        print(f"save_scraped_markdown failed (non-fatal): {exc}")

                # Upload hero image (non-fatal on failure) (REQ-18)
                thumbnail_url = _parse_thumbnail_url(scraped_markdown)
                if thumbnail_url:
                    try:
                        await asyncio.to_thread(
                            supabase_client.upload_hero_image, property_id, thumbnail_url
                        )
                    except Exception as exc:
                        print(f"Hero image upload failed (non-fatal): {exc}")

            # List files
            files = await asyncio.to_thread(supabase_client.list_upload_files, property_id)
            if not files:
                yield _event("(none)", "done", "No files found in storage.")
                await asyncio.to_thread(supabase_client.update_status, property_id, "Ingested")
                return

            # Emit queued for all files upfront
            for f in files:
                yield _event(f["name"], "queued")

            # Load fingerprints once (REQ-10, REQ-11, REQ-22)
            fingerprints = await asyncio.to_thread(
                supabase_client.get_file_fingerprints, property_id
            )

            # Process files sequentially
            error_count = 0
            try:
                for f in files:
                    name = f["name"]
                    # Size from storage metadata; falls back to 0 (will be treated as "new")
                    size = (f.get("metadata") or {}).get("size") or 0

                    fp_status = hash_guard.file_status(fingerprints, name, size)
                    if fp_status == "skip":
                        yield _event(name, "already_in_db", "Identical file — already in database.")
                        continue

                    is_update = fp_status == "update"
                    yield _event(
                        name, "processing",
                        "Reprocessing updated file." if is_update else ""
                    )

                    try:
                        data = await asyncio.to_thread(
                            supabase_client.download_file, property_id, name
                        )

                        current_task = asyncio.create_task(
                            file_processor.process_file(name, data)
                        )
                        while not current_task.done():
                            try:
                                await asyncio.wait_for(
                                    asyncio.shield(current_task), timeout=10
                                )
                            except asyncio.TimeoutError:
                                yield _event(name, "heartbeat", "Still processing...")
                        markdown = await current_task
                        current_task = None

                        await asyncio.to_thread(
                            supabase_client.append_ingested_markdown, property_id, markdown
                        )
                        fingerprints[name] = size  # record fingerprint only on success (REQ-22)
                        yield _event(name, "file_updated" if is_update else "done")

                    except Exception as exc:
                        yield _event(name, "error", str(exc))
                        error_count += 1

                # Persist all fingerprint updates (REQ-22)
                await asyncio.to_thread(
                    supabase_client.update_file_fingerprints, property_id, fingerprints
                )

                # Atomic status transition — Ingested only if zero errors (REQ-21)
                final_status = "Ingested" if error_count == 0 else "Ingest_Error"
                await asyncio.to_thread(supabase_client.update_status, property_id, final_status)

            except Exception as fatal:
                await asyncio.to_thread(supabase_client.update_status, property_id, "Ingest_Error")
                yield _event("(fatal)", "error", str(fatal))

        except BaseException:
            if current_task and not current_task.done():
                current_task.cancel()
            raise

    origin = request.headers.get("origin", "")
    sse_headers = {
        "Cache-Control": "no-cache",
        "X-Accel-Buffering": "no",
    }
    if origin:
        sse_headers["Access-Control-Allow-Origin"] = origin
        sse_headers["Access-Control-Allow-Credentials"] = "true"

    return StreamingResponse(
        stream(),
        media_type="text/event-stream",
        headers=sse_headers,
    )


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
            uri = await gemini_client.upload_file(data, filename, mime)
            knowledge_text = await gemini_client.process_with_prompt_c(uri, mime)

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
