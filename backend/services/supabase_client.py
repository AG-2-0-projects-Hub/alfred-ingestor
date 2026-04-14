import os
from supabase import create_client, Client

_client: Client | None = None


def get_client() -> Client:
    global _client
    if _client is None:
        url = os.environ["SUPABASE_URL"]
        key = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
        _client = create_client(url, key)
    return _client


BUCKET = "Property_assets"


def insert_property(property_id: str, name: str = "", airbnb_url: str = "") -> None:
    """Upsert a row in the properties table, preserving existing fields."""
    client = get_client()
    row: dict = {"id": property_id}
    if name:
        row["name"] = name
    if airbnb_url:
        row["airbnb_url"] = airbnb_url
    client.table("properties").upsert(row).execute()


def list_upload_files(property_id: str) -> list[dict]:
    """List files at Property_assets/{property_id}/user_uploads/."""
    client = get_client()
    resp = client.storage.from_(BUCKET).list(
        f"{property_id}/user_uploads",
        {"limit": 100, "offset": 0, "sortBy": {"column": "name", "order": "asc"}},
    )
    return resp or []


def download_file(property_id: str, filename: str) -> bytes:
    """Download a file from Supabase Storage. Returns raw bytes."""
    client = get_client()
    path = f"{property_id}/user_uploads/{filename}"
    return client.storage.from_(BUCKET).download(path)


def update_status(property_id: str, status: str) -> None:
    """PATCH properties SET status = <status> WHERE id = property_id."""
    client = get_client()
    client.table("properties").update({"status": status}).eq("id", property_id).execute()


def append_ingested_markdown(property_id: str, new_markdown: str) -> None:
    """Fetch existing ingested_markdown, append new_markdown, and save back.
    Never wipes existing data — exact Make.com append mechanism."""
    client = get_client()
    result = (
        client.table("properties")
        .select("ingested_markdown")
        .eq("id", property_id)
        .single()
        .execute()
    )
    existing = (result.data or {}).get("ingested_markdown") or ""
    combined = existing + "\n\n---\n\n" + new_markdown if existing else new_markdown
    client.table("properties").update({"ingested_markdown": combined}).eq("id", property_id).execute()
