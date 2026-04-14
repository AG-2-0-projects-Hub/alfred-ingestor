"""
POST /api/ingest — triggers sequential file processing over SSE.

Payload: { "property_id": "<ID>" }

SSE event format:
  data: {"file": "<name>", "status": "queued"|"processing"|"done"|"skipped"|"error", "message": "..."}

"""

import json
from fastapi import APIRouter
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

from services import supabase_client, hash_guard, file_processor

router = APIRouter()


class IngestRequest(BaseModel):
    property_id: str
    property_name: str = ""
    airbnb_url: str = ""


def _event(file: str, status: str, message: str = "") -> str:
    payload = json.dumps({"file": file, "status": status, "message": message})
    return f"data: {payload}\n\n"


@router.post("/ingest")
async def ingest(req: IngestRequest):
    property_id = req.property_id

    async def stream():
        # 1. Upsert property row (belt-and-suspenders; frontend may have done this already)
        supabase_client.insert_property(property_id, req.property_name, req.airbnb_url)
        supabase_client.update_status(property_id, "Ingesting")

        # 2. List files
        files = supabase_client.list_upload_files(property_id)
        if not files:
            yield _event("(none)", "done", "No files found in storage.")
            supabase_client.update_status(property_id, "Ingested")
            return

        # Emit queued for all files upfront
        for f in files:
            yield _event(f["name"], "queued")

        # 3. Process sequentially
        try:
            for f in files:
                name = f["name"]
                yield _event(name, "processing")
                try:
                    data = supabase_client.download_file(property_id, name)
                    sha = hash_guard.sha256_of(data)

                    if hash_guard.already_processed(sha):
                        yield _event(name, "skipped", "Duplicate — already ingested.")
                        continue

                    markdown = file_processor.process_file(name, data)
                    supabase_client.append_ingested_markdown(property_id, markdown)
                    hash_guard.mark_processed(sha)
                    yield _event(name, "done")

                except Exception as exc:
                    yield _event(name, "error", str(exc))

            # 4. Final status → Ingested
            supabase_client.update_status(property_id, "Ingested")

        except Exception as fatal:
            supabase_client.update_status(property_id, "Ingest_Error")
            yield _event("(fatal)", "error", str(fatal))

    return StreamingResponse(
        stream(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
        },
    )
