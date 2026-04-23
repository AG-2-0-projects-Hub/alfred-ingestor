import os
from datetime import datetime, timezone
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


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


# ── Property row ──────────────────────────────────────────────────────────────

def insert_property(property_id: str, name: str = "", airbnb_url: str = "") -> None:
    """Upsert a row in the properties table, preserving existing fields."""
    client = get_client()
    row: dict = {"id": property_id, "updated_at": _now()}
    if name:
        row["name"] = name
    if airbnb_url:
        row["airbnb_url"] = airbnb_url
    client.table("properties").upsert(row).execute()


def get_canonical_property(airbnb_url: str) -> dict | None:
    """Find an existing property by airbnb_url. Returns the row or None. (REQ-01, REQ-19)"""
    client = get_client()
    result = (
        client.table("properties")
        .select("id, status, name")
        .eq("airbnb_url", airbnb_url)
        .maybeSingle()
        .execute()
    )
    return result.data or None


def update_status(property_id: str, status: str) -> None:
    """PATCH properties SET status = <status>, updated_at = NOW() WHERE id = property_id."""
    client = get_client()
    client.table("properties").update(
        {"status": status, "updated_at": _now()}
    ).eq("id", property_id).execute()


def append_ingested_markdown(property_id: str, new_markdown: str) -> None:
    """Fetch existing ingested_markdown, append new_markdown, and save back."""
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
    client.table("properties").update(
        {"ingested_markdown": combined, "updated_at": _now()}
    ).eq("id", property_id).execute()


# ── File fingerprints ─────────────────────────────────────────────────────────

def get_file_fingerprints(property_id: str) -> dict:
    """Fetch file_fingerprints JSONB for a property. Returns {} if row not found. (REQ-22)"""
    client = get_client()
    result = (
        client.table("properties")
        .select("file_fingerprints")
        .eq("id", property_id)
        .maybeSingle()
        .execute()
    )
    return (result.data or {}).get("file_fingerprints") or {}


def update_file_fingerprints(property_id: str, fingerprints: dict) -> None:
    """Write updated file_fingerprints JSONB back to the property row. (REQ-22)"""
    client = get_client()
    client.table("properties").update(
        {"file_fingerprints": fingerprints, "updated_at": _now()}
    ).eq("id", property_id).execute()


# ── Storage ───────────────────────────────────────────────────────────────────

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


def move_files_in_storage(src_id: str, dest_id: str) -> None:
    """Move all user_uploads from src_id folder to dest_id folder. (REQ-01, REQ-19)"""
    client = get_client()
    files = list_upload_files(src_id)
    for f in files:
        src_path = f"{src_id}/user_uploads/{f['name']}"
        dest_path = f"{dest_id}/user_uploads/{f['name']}"
        try:
            client.storage.from_(BUCKET).move(src_path, dest_path)
        except Exception as exc:
            print(f"move_files_in_storage: failed to move {src_path} → {dest_path}: {exc}")


def upload_hero_image(property_id: str, image_url: str) -> None:
    """Download thumbnail from Airbnb URL and store under {property_id}/hero_image/main.jpg. (REQ-18)"""
    import httpx

    client = get_client()
    resp = httpx.get(image_url, timeout=30, follow_redirects=True)
    resp.raise_for_status()
    content_type = resp.headers.get("content-type", "image/jpeg").split(";")[0].strip()
    path = f"{property_id}/hero_image/main.jpg"
    client.storage.from_(BUCKET).upload(
        path,
        resp.content,
        file_options={"content-type": content_type, "upsert": "true"},
    )
