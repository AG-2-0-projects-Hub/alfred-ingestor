import asyncio

from fastapi import APIRouter, Header, HTTPException
from services import supabase_client

router = APIRouter()


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
