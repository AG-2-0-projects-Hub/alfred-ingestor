import asyncio
import logging
import os
import random
import re
import string
from datetime import datetime, timezone
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from services import supabase_client, gemini_messenger

router = APIRouter()
log = logging.getLogger(__name__)

GEMINI_TIMEOUT_S = 45


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


class WebIncomingRequest(BaseModel):
    booking_id: str
    message: str


class HostSendRequest(BaseModel):
    conversation_id: str
    message: str


@router.post("/messages/web-incoming")
async def web_incoming(req: WebIncomingRequest):
    guest = await asyncio.to_thread(supabase_client.get_guest_by_booking_id, req.booking_id)
    if not guest:
        raise HTTPException(status_code=404, detail="Guest not found")

    conversation = await asyncio.to_thread(
        supabase_client.find_or_create_conversation,
        req.booking_id,
        guest["property_id"],
    )

    # Always log the guest message so the host can see it even in intervene mode
    await asyncio.to_thread(
        supabase_client.insert_message,
        conversation["id"],
        "guest",
        req.message,
    )

    if conversation.get("mode") == "intervene":
        await asyncio.to_thread(
            supabase_client.update_conversation,
            conversation["id"],
            ai_status="paused",
        )
        return {"status": "intervene_mode", "reply": None}

    property_data = await asyncio.to_thread(
        supabase_client.get_property_for_chat,
        guest["property_id"],
    )
    if not property_data or not property_data.get("master_json"):
        raise HTTPException(status_code=404, detail="Property data not found")

    # Fetch history before the current message was inserted so Gemini sees it
    # separately in the "Current Guest Message" field (matching blueprint template)
    history = await asyncio.to_thread(
        supabase_client.get_conversation_messages,
        conversation["id"],
    )
    # Exclude the message we just inserted (last item)
    history = history[:-1] if history else []

    try:
        first_result = await asyncio.wait_for(
            gemini_messenger.first_pass(
                master_json=property_data["master_json"],
                conversation_history=history,
                preferred_language=guest.get("preferred_language") or "not_set",
                guest_message=req.message,
                learned_knowledge=property_data.get("learned_knowledge") or [],
            ),
            timeout=GEMINI_TIMEOUT_S,
        )

        if first_result.get("requires_web_search") and first_result.get("search_query"):
            reply = await asyncio.wait_for(
                gemini_messenger.second_pass_with_search(
                    master_json=property_data["master_json"],
                    conversation_history=history,
                    preferred_language=guest.get("preferred_language") or "not_set",
                    guest_message=req.message,
                    search_query=first_result["search_query"],
                ),
                timeout=GEMINI_TIMEOUT_S,
            )
        else:
            reply = first_result["reply_to_guest"]
    except asyncio.TimeoutError:
        log.warning(
            "Gemini call exceeded %ss for booking=%s; returning 504 so the client gets a CORS-friendly error",
            GEMINI_TIMEOUT_S, req.booking_id,
        )
        await asyncio.to_thread(
            supabase_client.update_conversation,
            conversation["id"],
            ai_status="error",
        )
        raise HTTPException(
            status_code=504,
            detail={"code": "gemini_timeout", "retry": True,
                    "message": f"Alfred took longer than {GEMINI_TIMEOUT_S}s to respond."},
        )

    requires_escalation = bool(first_result.get("requires_escalation"))

    await asyncio.to_thread(
        supabase_client.insert_message,
        conversation["id"],
        "ai",
        reply,
        sentiment=first_result.get("sentiment"),
        is_escalated_interaction=requires_escalation,
        used_learned_knowledge=bool(first_result.get("used_learned_knowledge")),
    )

    update_fields: dict = {"ai_status": "active"}
    if requires_escalation:
        update_fields["requires_attention"] = True
        update_fields["mode"] = "intervene"
        update_fields["escalation_reason"] = first_result.get("escalation_reason")

    await asyncio.to_thread(
        supabase_client.update_conversation,
        conversation["id"],
        **update_fields,
    )

    return {
        "reply": reply,
        "requires_escalation": requires_escalation,
        "conversation_id": conversation["id"],
    }


@router.post("/messages/host-send")
async def host_send(req: HostSendRequest):
    await asyncio.to_thread(
        supabase_client.insert_message,
        req.conversation_id,
        "host",
        req.message,
    )
    await asyncio.to_thread(
        supabase_client.update_conversation,
        req.conversation_id,
        ai_status="paused",
    )
    return {"status": "sent"}


# ── Resolve escalation + learn ────────────────────────────────────────────────

class ResolveRequest(BaseModel):
    booking_id: str


@router.post("/conversations/resolve")
async def resolve_conversation(req: ResolveRequest):
    guest = await asyncio.to_thread(supabase_client.get_guest_by_booking_id, req.booking_id)
    if not guest:
        raise HTTPException(status_code=404, detail="Guest not found")

    conv_id, thread = await asyncio.to_thread(
        supabase_client.get_conversation_thread_for_resolve,
        req.booking_id,
    )
    if not conv_id:
        raise HTTPException(status_code=404, detail="Conversation not found")

    learned_entry = None
    if thread:
        try:
            summary = await asyncio.wait_for(
                gemini_messenger.summarize_escalation(thread),
                timeout=GEMINI_TIMEOUT_S,
            )
            learned_entry = {
                "problem_summary": summary.get("problem_summary", ""),
                "solution_summary": summary.get("solution_summary", ""),
                "category": summary.get("category", "other"),
                "language": summary.get("language", "en"),
                "resolved_at": _now_iso(),
                "booking_id": req.booking_id,
            }
        except asyncio.TimeoutError:
            log.warning(
                "Gemini summarizer exceeded %ss for booking=%s; resolving without learning",
                GEMINI_TIMEOUT_S, req.booking_id,
            )
        except Exception as exc:
            log.exception("Summarizer failed for booking=%s: %s", req.booking_id, exc)

    await asyncio.to_thread(
        supabase_client.resolve_conversation,
        conv_id,
        guest["property_id"],
        learned_entry,
    )

    return {"status": "resolved", "learned": learned_entry}


# ── Guest link generation ─────────────────────────────────────────────────────

class CreateGuestRequest(BaseModel):
    property_id: str
    guest_name: str = "Guest"


def _slugify(text: str) -> str:
    text = text.lower().strip()
    text = re.sub(r"[^\w\s-]", "", text)
    text = re.sub(r"[\s_]+", "-", text)
    return re.sub(r"-+", "-", text)


def _random_suffix(n: int = 6) -> str:
    return "".join(random.choices(string.ascii_lowercase + string.digits, k=n))


@router.post("/guests")
async def create_guest(req: CreateGuestRequest):
    # Fetch property name for the slug
    prop = await asyncio.to_thread(supabase_client.get_property_for_chat, req.property_id)
    if not prop:
        raise HTTPException(status_code=404, detail="Property not found")

    slug = _slugify(prop.get("name") or "property")
    frontend_url = os.environ.get("FRONTEND_URL", "").split(",")[0].strip().rstrip("/")

    # Retry on booking_id collision (very unlikely but safe)
    for _ in range(5):
        booking_id = f"{slug}-{_random_suffix()}"
        guest_chat_url = f"{frontend_url}/chat?booking={booking_id}"
        host_chat_url = f"{frontend_url}/chat-live?booking={booking_id}&property={req.property_id}"
        try:
            guest = await asyncio.to_thread(
                supabase_client.create_guest,
                booking_id,
                req.property_id,
                req.guest_name,
                guest_chat_url,
                host_chat_url,
            )
            return {
                "booking_id": booking_id,
                "guest_chat_url": guest_chat_url,
                "host_chat_url": host_chat_url,
            }
        except Exception as exc:
            if "duplicate" in str(exc).lower() or "unique" in str(exc).lower():
                continue
            raise HTTPException(status_code=500, detail=str(exc))

    raise HTTPException(status_code=500, detail="Could not generate unique booking ID")
