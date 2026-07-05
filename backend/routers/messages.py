import asyncio
import logging
import os
import random
import re
import string
from datetime import datetime, timezone
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from services import supabase_client, gemini_messenger, telegram_client
from routers.guest_auth import _resolve_identity  # host/property name from master_json

router = APIRouter()
log = logging.getLogger(__name__)

GEMINI_TIMEOUT_S = 45


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


async def _notify_tg_transition(guest: dict | None, host_name: str | None, kind: str) -> None:
    """Push the same transition notice the web shows to a Telegram-linked guest.

    kind: 'intervene' (a human takes over) or 'resume' (Alfred is back). Copy
    mirrors ChatSystemMessages.formatForGuest. No-op for web-only guests
    (no telegram_chat_id). Best-effort — never fail the caller.
    """
    if not guest or not guest.get("telegram_chat_id"):
        return
    if kind == "intervene":
        text = f"You are now speaking with {host_name or 'your host'}."
    else:
        text = "Alfred has resumed the conversation."
    try:
        await telegram_client.send_italic(guest["telegram_chat_id"], text)
    except Exception as exc:
        log.warning("telegram transition notice (%s) failed: %s", kind, exc)


class WebIncomingRequest(BaseModel):
    booking_id: str
    message: str


class HostSendRequest(BaseModel):
    conversation_id: str
    message: str


async def process_guest_message(booking_id: str, message: str) -> dict:
    """Channel-agnostic guest pipeline shared by the web chat and the Telegram
    bot. Runs the Brain (Gemini first pass → optional web-search second pass →
    escalation) and persists everything.

    Returns {reply, requires_escalation, conversation_id, mode}. In intervene
    mode `reply` is None (the host answers). Raises HTTPException(404) if the
    guest/property is missing and HTTPException(504) on Gemini timeout — the web
    caller surfaces these as HTTP errors; the Telegram caller catches them and
    sends a friendly message.
    """
    guest = await asyncio.to_thread(supabase_client.get_guest_by_booking_id, booking_id)
    if not guest:
        raise HTTPException(status_code=404, detail="Guest not found")

    conversation = await asyncio.to_thread(
        supabase_client.find_or_create_conversation,
        booking_id,
        guest["property_id"],
    )

    # History as it stood BEFORE this message — Gemini sees it separately from
    # the "Current Guest Message" field (matching the blueprint template).
    history = await asyncio.to_thread(
        supabase_client.get_conversation_messages,
        conversation["id"],
    )

    # Dedupe guard: a client retry (web) or a Telegram webhook re-delivery can
    # replay the same message. Skip the insert if it's identical to the most
    # recent guest message — avoids piling up duplicate guest rows on retry.
    last_guest = next(
        (m for m in reversed(history) if m.get("sender_type") == "guest"), None
    )
    is_duplicate = last_guest is not None and last_guest.get("content") == message
    if not is_duplicate:
        # Always log the guest message so the host can see it even in intervene mode.
        await asyncio.to_thread(
            supabase_client.insert_message,
            conversation["id"],
            "guest",
            message,
        )

    if conversation.get("mode") == "intervene":
        await asyncio.to_thread(
            supabase_client.update_conversation,
            conversation["id"],
            ai_status="paused",
        )
        return {
            "reply": None,
            "requires_escalation": False,
            "conversation_id": conversation["id"],
            "mode": "intervene",
        }

    property_data = await asyncio.to_thread(
        supabase_client.get_property_for_chat,
        guest["property_id"],
    )
    if not property_data or not property_data.get("master_json"):
        raise HTTPException(status_code=404, detail="Property data not found")

    try:
        first_result = await asyncio.wait_for(
            gemini_messenger.first_pass(
                master_json=property_data["master_json"],
                conversation_history=history,
                preferred_language=guest.get("preferred_language") or "not_set",
                guest_message=message,
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
                    guest_message=message,
                    search_query=first_result["search_query"],
                ),
                timeout=GEMINI_TIMEOUT_S,
            )
        else:
            reply = first_result["reply_to_guest"]
    except asyncio.TimeoutError:
        log.warning(
            "Gemini call exceeded %ss for booking=%s; returning 504 so the client gets a CORS-friendly error",
            GEMINI_TIMEOUT_S, booking_id,
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

    # On auto-escalation, insert a system marker so the guest sees
    # "You are now speaking with [host name]." even when the host hasn't
    # opened the chat dialog yet. Frontend renderers expand the marker
    # per-viewer (guest vs host). Marker kept in sync with
    # frontend/lib/utils/chat_system_messages.dart.
    if requires_escalation:
        await asyncio.to_thread(
            supabase_client.insert_message,
            conversation["id"],
            "system",
            "__SYS_INTERVENE__",
        )
        # Telegram guests don't render the web marker — push the same notice.
        _, host_name = _resolve_identity(property_data)
        await _notify_tg_transition(guest, host_name, "intervene")

    return {
        "reply": reply,
        "requires_escalation": requires_escalation,
        "conversation_id": conversation["id"],
        "mode": conversation.get("mode") or "autopilot",
    }


@router.post("/messages/web-incoming")
async def web_incoming(req: WebIncomingRequest):
    result = await process_guest_message(req.booking_id, req.message)
    if result["mode"] == "intervene":
        return {"status": "intervene_mode", "reply": None}
    return {
        "reply": result["reply"],
        "requires_escalation": result["requires_escalation"],
        "conversation_id": result["conversation_id"],
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

    # If the guest is on Telegram, deliver the host's reply there too. Web guests
    # get it live via Supabase realtime; Telegram guests need an active push.
    # Best-effort — never fail the host send if Telegram delivery hiccups.
    try:
        guest = await asyncio.to_thread(
            supabase_client.get_guest_by_conversation_id, req.conversation_id
        )
        if guest and guest.get("telegram_chat_id"):
            await telegram_client.send_message(guest["telegram_chat_id"], req.message)
    except Exception as exc:
        log.warning("host_send: Telegram delivery failed for conv=%s: %s",
                    req.conversation_id, exc)

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
                "reviewed": False,
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

    # Telegram guest gets the same "Alfred has resumed" notice the web shows.
    await _notify_tg_transition(guest, None, "resume")

    return {"status": "resolved", "learned": learned_entry}


class TransitionRequest(BaseModel):
    conversation_id: str
    kind: str  # 'intervene' | 'resume'


@router.post("/conversations/announce-transition")
async def announce_transition(req: TransitionRequest):
    """Called by the host dashboard right after it inserts a manual mode-change
    marker (Intervene / Resume). Pushes the matching notice to the guest's
    Telegram if linked. No-op for web-only guests. Best-effort."""
    guest = await asyncio.to_thread(
        supabase_client.get_guest_by_conversation_id, req.conversation_id
    )
    host_name = None
    if req.kind == "intervene" and guest:
        prop = await asyncio.to_thread(
            supabase_client.get_property_for_chat, guest["property_id"]
        )
        _, host_name = _resolve_identity(prop)
    await _notify_tg_transition(guest, host_name, req.kind)
    return {"status": "ok"}


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
    bot_username = os.environ.get("TELEGRAM_BOT_USERNAME", "").lstrip("@").strip()

    # Retry on booking_id collision (very unlikely but safe)
    for _ in range(5):
        booking_id = f"{slug}-{_random_suffix()}"
        guest_chat_url = f"{frontend_url}/chat?booking={booking_id}"
        host_chat_url = f"{frontend_url}/chat-live?booking={booking_id}&property={req.property_id}"
        # Telegram deep link: tapping it opens the bot and sends `/start <booking_id>`,
        # which links this guest's chat. booking_ids are [a-z0-9-] → Telegram-safe.
        telegram_link = (
            f"https://t.me/{bot_username}?start={booking_id}" if bot_username else None
        )
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
                "telegram_link": telegram_link,
            }
        except Exception as exc:
            if "duplicate" in str(exc).lower() or "unique" in str(exc).lower():
                continue
            raise HTTPException(status_code=500, detail=str(exc))

    raise HTTPException(status_code=500, detail="Could not generate unique booking ID")
