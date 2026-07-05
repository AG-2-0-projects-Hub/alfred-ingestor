import asyncio
import os
import time

import jwt
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from services import supabase_client, welcome

router = APIRouter()

_PROJECT_REF = "gcxxilzfhwlsjcvtpsvj"
_TOKEN_TTL = 86_400  # 24 hours

_SENTENCE_PUNCT = (",", ";", ":", ".", "!", "?")


class GuestTokenRequest(BaseModel):
    booking_id: str


def _sanitize_host_name(raw) -> str | None:
    """Reject extraction noise (whole instruction sentences stuffed into
    host_profile.name) so the guest header never shows a paragraph. A real
    display name is short and not sentence-like."""
    if not isinstance(raw, str):
        return None
    name = raw.strip()
    if not name or len(name) > 40:
        return None
    words = name.split()
    if len(words) > 3:
        return None
    if any(p in name for p in _SENTENCE_PUNCT) and len(words) > 1:
        return None
    return name


def _resolve_identity(prop: dict | None) -> tuple[str | None, str | None]:
    """Compute (property_name, host_name) from the property's Master JSON,
    using the same fallback chain the guest chat header expects. Done here on
    the server because RLS blocks the anon guest from reading the properties
    table directly."""
    if not prop:
        return None, None
    master_json = prop.get("master_json") or {}
    identity = master_json.get("property_identity") or {}
    candidates = [
        identity.get("listing_name"),
        identity.get("property_name"),
        identity.get("name"),
        identity.get("property_complex_name"),
        prop.get("name"),
    ]
    property_name = next(
        (c.strip() for c in candidates if isinstance(c, str) and c.strip()), None
    )
    host_profile = master_json.get("host_profile") or {}
    host_name = _sanitize_host_name(host_profile.get("name"))
    return property_name, host_name


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

    # Resolve the property name + host name server-side. RLS blocks the anon
    # guest from reading the properties table, so the header is fed from here.
    prop = await asyncio.to_thread(
        supabase_client.get_property_for_chat, guest["property_id"]
    )
    # B4: a guest holding an old link to a soft-deleted property must not be able
    # to keep chatting (Alfred would run with wiped knowledge and write new
    # messages onto a tombstone). Refuse the token once the property is deleted.
    if prop and prop.get("deleted_at"):
        raise HTTPException(
            status_code=410, detail="This conversation is no longer available."
        )
    property_name, host_name = _resolve_identity(prop)

    # Post the welcome once (creating the conversation) so it renders on the web
    # and the conversation shows on the dashboard immediately — same behaviour as
    # Telegram /start. Idempotent: only inserts when the thread is empty.
    welcome_text = welcome.build_welcome(
        property_name or (prop or {}).get("name"),
        (prop or {}).get("master_json"),
        also_english=bool((prop or {}).get("welcome_also_english")),
    )
    await asyncio.to_thread(
        supabase_client.ensure_conversation_with_welcome,
        req.booking_id, guest["property_id"], welcome_text,
    )

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

    return {
        "access_token": token,
        "expires_in": _TOKEN_TTL,
        "property_name": property_name,
        "host_name": host_name,
    }
