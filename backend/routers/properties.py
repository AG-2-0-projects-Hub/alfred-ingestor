import asyncio
import os

import jwt
from fastapi import APIRouter, Header, HTTPException
from services import supabase_client

router = APIRouter()


def _require_owner_id(authorization: str | None) -> str:
    """Verify the host's Supabase access token and return their user id (sub).

    The host's JWT is signed with the same legacy Supabase JWT secret (HS256),
    so we can verify it server-side and trust the `sub` claim as the owner id.
    """
    secret = os.environ.get("SUPABASE_JWT_SECRET")
    if not secret:
        raise HTTPException(status_code=500, detail="JWT secret not configured on server")
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="Missing bearer token")
    token = authorization.split(" ", 1)[1].strip()
    try:
        claims = jwt.decode(
            token, secret, algorithms=["HS256"], audience="authenticated"
        )
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid or expired token")
    user_id = claims.get("sub")
    if not user_id:
        raise HTTPException(status_code=401, detail="Token missing subject")
    return user_id


@router.post("/property/{property_id}/soft-delete")
async def soft_delete_property(
    property_id: str, authorization: str | None = Header(default=None)
):
    """Soft-delete a property the caller owns: blank its data, drop its storage,
    anonymize its guests, and keep its conversations/messages for training.

    Ownership is enforced from the verified host JWT, so a caller can only
    delete their own property even though the work runs under the service role.
    """
    owner_id = _require_owner_id(authorization)
    result = await asyncio.to_thread(
        supabase_client.soft_delete_property, property_id, owner_id
    )
    if result == "not_found":
        raise HTTPException(status_code=404, detail="Property not found")
    if result == "forbidden":
        raise HTTPException(status_code=403, detail="Not your property")
    return {"status": "deleted"}
