import asyncio

from fastapi import APIRouter, File, Header, HTTPException, UploadFile
from services import supabase_client

router = APIRouter()

_AVATAR_EXT_MIME = {
    "png": "image/png",
    "jpg": "image/jpeg",
    "jpeg": "image/jpeg",
    "webp": "image/webp",
}


async def _require_host_id(authorization: str | None) -> str:
    """Validate the host bearer token and return the host uid (401 otherwise).
    Mirrors the soft-delete auth so host-only endpoints share one pattern."""
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="Missing bearer token")
    token = authorization.split(" ", 1)[1].strip()
    owner_id = await asyncio.to_thread(supabase_client.get_user_id_from_token, token)
    if not owner_id:
        raise HTTPException(status_code=401, detail="Invalid or expired token")
    return owner_id


@router.post("/host/avatar")
async def upload_host_avatar(
    file: UploadFile = File(...),
    authorization: str | None = Header(default=None),
):
    """Upload the authenticated host's profile photo. The Flutter web client
    couldn't write to the host_avatars bucket directly (storage RLS rejected it),
    so the upload is brokered here: validate the host token, then write under the
    host's own uid folder with the service role. Returns the public URL."""
    uid = await _require_host_id(authorization)
    fname = (file.filename or "avatar.jpg").lower()
    ext = fname.rsplit(".", 1)[-1] if "." in fname else "jpg"
    content_type = _AVATAR_EXT_MIME.get(ext)
    if content_type is None:
        raise HTTPException(status_code=400, detail="Unsupported image type")
    if ext == "jpeg":
        ext = "jpg"
    data = await file.read()
    if not data:
        raise HTTPException(status_code=400, detail="Empty file")
    if len(data) > 5 * 1024 * 1024:
        raise HTTPException(status_code=413, detail="Image too large (max 5 MB)")
    url = await asyncio.to_thread(
        supabase_client.upload_host_avatar, uid, data, content_type, ext
    )
    return {"url": url}


@router.post("/property/{property_id}/soft-delete")
async def soft_delete_property(
    property_id: str, authorization: str | None = Header(default=None)
):
    """Soft-delete a property the caller owns: blank its data, drop its storage,
    anonymize its guests, and keep its conversations/messages for training.

    Ownership is enforced from the host's access token, which is validated via
    Supabase Auth (GoTrue) — algorithm-agnostic, so it works regardless of
    whether the project signs sessions with the legacy HS256 secret or the new
    asymmetric JWT signing keys. The work itself runs under the service role.
    """
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="Missing bearer token")
    token = authorization.split(" ", 1)[1].strip()

    owner_id = await asyncio.to_thread(supabase_client.get_user_id_from_token, token)
    if not owner_id:
        raise HTTPException(status_code=401, detail="Invalid or expired token")

    result = await asyncio.to_thread(
        supabase_client.soft_delete_property, property_id, owner_id
    )
    if result == "not_found":
        raise HTTPException(status_code=404, detail="Property not found")
    if result == "forbidden":
        raise HTTPException(status_code=403, detail="Not your property")
    return {"status": "deleted"}
