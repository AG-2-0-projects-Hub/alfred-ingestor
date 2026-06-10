import asyncio
import os
import time

import jwt
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from services import supabase_client

router = APIRouter()

_PROJECT_REF = "gcxxilzfhwlsjcvtpsvj"
_TOKEN_TTL = 86_400  # 24 hours


class GuestTokenRequest(BaseModel):
    booking_id: str


@router.post("/guest-token")
async def guest_token(req: GuestTokenRequest):
    """
    Exchanges a valid booking_id for a short-lived JWT the guest Flutter
    client uses as its Supabase access token.

    The JWT carries role="anon" and booking_id as a top-level claim.
    Supabase RLS policies scope all guest reads/writes to that booking.

    The bare anon key (no booking_id claim) is now locked out by RLS, so
    this endpoint is the only way a guest can interact with the DB directly.
    """
    jwt_secret = os.environ.get("SUPABASE_JWT_SECRET")
    if not jwt_secret:
        raise HTTPException(status_code=500, detail="JWT secret not configured on server")

    # Verify the booking actually exists before handing out a token.
    guest = await asyncio.to_thread(
        supabase_client.get_guest_by_booking_id, req.booking_id
    )
    if not guest:
        raise HTTPException(status_code=404, detail="Booking not found")

    now = int(time.time())
    payload = {
        "iss": "supabase",
        "ref": _PROJECT_REF,
        "role": "anon",
        "booking_id": req.booking_id,
        "iat": now,
        "exp": now + _TOKEN_TTL,
    }
    token = jwt.encode(payload, jwt_secret, algorithm="HS256")

    return {"access_token": token, "expires_in": _TOKEN_TTL}
