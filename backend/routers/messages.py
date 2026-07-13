import asyncio
import logging
import os
import random
import re
import string
from datetime import datetime, timedelta, timezone
from fastapi import APIRouter, Header, HTTPException
from pydantic import BaseModel
from services import guardrails, learning_triage, supabase_client, gemini_messenger, telegram_client, welcome
from routers.guest_auth import _resolve_identity  # host/property name from master_json

router = APIRouter()
log = logging.getLogger(__name__)

GEMINI_TIMEOUT_S = 45


async def _require_host(authorization: str | None) -> str:
    """Validate the host's Supabase access token (Authorization: Bearer <token>)
    and return the host user id. These endpoints run as service-role (bypassing
    RLS), so the caller must be authenticated here; per-object ownership is then
    checked by the caller via supabase_client.host_owns_*."""
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="Missing bearer token")
    token = authorization.split(" ", 1)[1].strip()
    host_id = await asyncio.to_thread(supabase_client.get_user_id_from_token, token)
    if not host_id:
        raise HTTPException(status_code=401, detail="Invalid or expired token")
    return host_id


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


async def _notify_tg_transition(
    guest: dict | None, host_name: str | None, kind: str,
    active_channel: str = "telegram",
) -> None:
    """Push the same transition notice the web shows to a Telegram-linked guest.

    kind: 'intervene' (a human takes over) or 'resume' (Alfred is back). Copy
    mirrors ChatSystemMessages.formatForGuest. No-op unless the guest's ACTIVE
    channel is Telegram (a web guest sees the marker via realtime — don't ping
    their Telegram) and they have a telegram_chat_id. Best-effort.
    """
    if active_channel != "telegram":
        return
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
    message: str = ""
    # Optional media the web client already uploaded to chat_media. When set, the
    # Brain fetches the bytes and analyzes them (image or voice note).
    media_url: str | None = None
    media_kind: str | None = None  # 'image' | 'audio'
    media_mime: str | None = None


class HostSendRequest(BaseModel):
    conversation_id: str
    message: str


async def process_guest_message(
    booking_id: str, message: str, channel: str = "web",
    media: dict | list[dict] | None = None,
) -> dict:
    """Channel-agnostic guest pipeline shared by the web chat and the Telegram
    bot. `channel` ('web' | 'telegram') is the channel this message arrived on;
    it becomes the conversation's active_channel so guest-facing pushes follow
    the guest. Runs the Brain (Gemini first pass → optional web-search second
    pass → escalation) and persists everything.

    Returns {reply, requires_escalation, conversation_id, mode}. In intervene
    mode `reply` is None (the host answers). Raises HTTPException(404) if the
    guest/property is missing and HTTPException(504) on Gemini timeout — the web
    caller surfaces these as HTTP errors; the Telegram caller catches them and
    sends a friendly message.
    """
    # Guardrail: cap input length before it hits storage or the prompt.
    message = guardrails.truncate_message(message)

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

    # Media (image / voice) vs plain text. For media we attach the raw bytes to
    # the Gemini call below so Alfred actually analyzes the photo / voice note.
    # `media` is a list because a Telegram album arrives as several photos that
    # must produce ONE reply, not one per photo. A single dict is still accepted.
    media_items = [media] if isinstance(media, dict) else list(media or [])
    media_parts: list[tuple[bytes, str]] = []
    media_kind: str | None = None  # 'image' | 'audio' — what this turn carried
    image_count = 0
    for item in media_items:
        kind = item.get("kind")
        mime = item.get("mime") or ("image/jpeg" if kind == "image" else "audio/ogg")
        media_kind = media_kind or kind
        if kind == "image":
            image_count += 1

        item_bytes: bytes | None = None
        if item.get("bytes") is not None:
            # Telegram: persist to chat_media so the host sees it in the dashboard,
            # then log the guest row here (the web client does its own upload+insert).
            item_bytes = item["bytes"]
            ext = (mime.split("/")[-1].split(";")[0]
                   or ("jpg" if kind == "image" else "ogg"))
            ts = int(datetime.now(timezone.utc).timestamp() * 1000)
            storage_path: str | None = (
                f"{conversation['id']}/chat_media/{kind}_{ts}_{len(media_parts)}.{ext}"
            )
            try:
                await asyncio.to_thread(
                    supabase_client.upload_chat_media,
                    storage_path, item_bytes, mime,
                )
            except Exception as exc:
                log.warning("chat_media upload failed for booking=%s: %s", booking_id, exc)
                storage_path = None
            await asyncio.to_thread(
                supabase_client.insert_message,
                conversation["id"],
                "guest",
                message or ("[image]" if kind == "image" else "[voice message]"),
                message_type=kind,
                media_url=storage_path,
            )
        elif item.get("url"):
            # Web: the client already uploaded to chat_media and inserted the
            # message row — just fetch the bytes for analysis.
            try:
                item_bytes = await asyncio.to_thread(
                    supabase_client.download_chat_media, item["url"]
                )
            except Exception as exc:
                log.warning("chat_media download failed for booking=%s: %s", booking_id, exc)

        if item_bytes:
            media_parts.append((item_bytes, mime))

    if not media_items and not is_duplicate:
        # Always log the guest message so the host can see it even in intervene mode.
        await asyncio.to_thread(
            supabase_client.insert_message,
            conversation["id"],
            "guest",
            message,
        )

    # Follow the guest: the channel this message arrived on becomes the active
    # one, so host replies + transition notices route back to it (and only it).
    if conversation.get("active_channel") != channel:
        await asyncio.to_thread(
            supabase_client.set_active_channel, conversation["id"], channel
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

    # Guardrail: per-conversation rate limit (R3 — runaway cost/abuse). Checked
    # after the guest message is stored (host always sees it) but before any
    # Gemini spend. On breach the cooldown notice is posted at most once per
    # streak — repeat breaches stay silent.
    now = datetime.now(timezone.utc)
    hourly = await asyncio.to_thread(
        supabase_client.count_recent_guest_messages,
        conversation["id"], (now - timedelta(hours=1)).isoformat(),
    )
    daily = hourly
    if hourly <= guardrails.RATE_LIMIT_PER_HOUR:
        daily = await asyncio.to_thread(
            supabase_client.count_recent_guest_messages,
            conversation["id"], (now - timedelta(hours=24)).isoformat(),
        )
    if hourly > guardrails.RATE_LIMIT_PER_HOUR or daily > guardrails.RATE_LIMIT_PER_DAY:
        log.warning("rate limit tripped for booking=%s (hour=%s day=%s)",
                    booking_id, hourly, daily)
        notice = guardrails.rate_limit_reply(guest.get("preferred_language"))
        last_ai = next(
            (m for m in reversed(history) if m.get("sender_type") == "ai"), None
        )
        reply_out = None
        if last_ai is None or last_ai.get("content") != notice:
            await asyncio.to_thread(
                supabase_client.insert_message, conversation["id"], "ai", notice
            )
            reply_out = notice
        return {
            "reply": reply_out,
            "requires_escalation": False,
            "conversation_id": conversation["id"],
            "mode": conversation.get("mode") or "autopilot",
        }

    property_data = await asyncio.to_thread(
        supabase_client.get_property_for_chat,
        guest["property_id"],
    )
    if not property_data or not property_data.get("master_json"):
        raise HTTPException(status_code=404, detail="Property data not found")

    # Attach the guest's media (if any) to the first pass, with a short text
    # anchor so a caption-less photo/voice note still has a prompt. An album is
    # announced as one prompt so Alfred addresses the photos together.
    if message:
        prompt_message = message
    elif media_kind == "image":
        prompt_message = "[image]" if image_count <= 1 else f"[{image_count} images]"
    elif media_kind == "audio":
        prompt_message = "[voice message]"
    else:
        prompt_message = message

    try:
        first_result = await asyncio.wait_for(
            gemini_messenger.first_pass(
                master_json=property_data["master_json"],
                conversation_history=history,
                preferred_language=guest.get("preferred_language") or "not_set",
                guest_message=prompt_message,
                learned_knowledge=property_data.get("learned_knowledge") or [],
                media=media_parts or None,
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
    escalation_reason = first_result.get("escalation_reason")

    # Guardrail: high-stakes backstop (R2). If the guest asked for an address,
    # access code, wifi password, or check-in/out time that the Master JSON
    # can't safely answer (missing or conflicted) and the model did NOT
    # escalate, don't trust its reply — replace it with a safe holding line
    # and force the escalation the prompt should have produced.
    if not requires_escalation:
        backstop = guardrails.high_stakes_backstop(
            message, property_data["master_json"]
        )
        if backstop:
            log.warning(
                "high-stakes backstop tripped: intent=%s reason=%s booking=%s",
                backstop["intent"], backstop["reason"], booking_id,
            )
            requires_escalation = True
            escalation_reason = backstop["reason"]
            reply = guardrails.holding_reply(
                first_result.get("detected_language")
                or guest.get("preferred_language")
            )

    # Media-burst escalation: a guest sending several PHOTOS in a short burst
    # usually wants a human to look, so escalate — Alfred's analysis still goes
    # out as the reply. Only photos count and only within the burst window: a
    # single photo, or a voice note, is ordinary conversation and must not
    # escalate on volume alone.
    if image_count and not requires_escalation:
        recent_images = await asyncio.to_thread(
            supabase_client.count_recent_guest_media,
            conversation["id"],
            (datetime.now(timezone.utc)
             - timedelta(minutes=guardrails.MEDIA_BURST_WINDOW_MIN)).isoformat(),
            ("image",),
        )
        if recent_images >= guardrails.MEDIA_ESCALATE_COUNT:
            log.info("media-burst escalation for booking=%s (images=%s in %smin)",
                     booking_id, recent_images, guardrails.MEDIA_BURST_WINDOW_MIN)
            requires_escalation = True
            escalation_reason = "media_needs_host_review"

    # Persist the language Alfred actually replied in, so the next turn has a
    # stable anchor instead of re-detecting (and possibly flip-flopping) from
    # scratch. The prompt only reports a real, deliberate switch.
    detected_language = first_result.get("detected_language")
    if detected_language:
        await asyncio.to_thread(
            supabase_client.update_guest_language, booking_id, detected_language
        )

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
        update_fields["escalation_reason"] = escalation_reason

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
    host_name = None
    if requires_escalation:
        await asyncio.to_thread(
            supabase_client.insert_message,
            conversation["id"],
            "system",
            "__SYS_INTERVENE__",
        )
        # A web guest renders the marker via realtime. A Telegram guest can't,
        # so the "You are now speaking with <host>" notice is pushed by the
        # Telegram caller AFTER it delivers Alfred's reply — otherwise the notice
        # arrives first and Alfred's reply reads as if the host wrote it. Return
        # the host name so the caller can send it in the right order.
        _, host_name = _resolve_identity(property_data)

    return {
        "reply": reply,
        "requires_escalation": requires_escalation,
        "conversation_id": conversation["id"],
        "mode": conversation.get("mode") or "autopilot",
        "host_name": host_name,
    }


@router.post("/messages/web-incoming")
async def web_incoming(req: WebIncomingRequest):
    media = None
    if req.media_url and req.media_kind:
        media = {"kind": req.media_kind, "url": req.media_url, "mime": req.media_mime}
    result = await process_guest_message(req.booking_id, req.message, media=media)
    if result["mode"] == "intervene":
        return {"status": "intervene_mode", "reply": None}
    return {
        "reply": result["reply"],
        "requires_escalation": result["requires_escalation"],
        "conversation_id": result["conversation_id"],
    }


@router.post("/messages/host-send")
async def host_send(req: HostSendRequest, authorization: str | None = Header(default=None)):
    host_id = await _require_host(authorization)
    if not await asyncio.to_thread(
        supabase_client.host_owns_conversation, host_id, req.conversation_id
    ):
        raise HTTPException(status_code=403, detail="Not your conversation")
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

    # Deliver the host's reply to Telegram ONLY if Telegram is the guest's active
    # channel. A web guest reads it live via Supabase realtime — don't also ping
    # their Telegram. Best-effort — never fail the host send if delivery hiccups.
    try:
        active_channel = await asyncio.to_thread(
            supabase_client.get_active_channel, req.conversation_id
        )
        if active_channel == "telegram":
            guest = await asyncio.to_thread(
                supabase_client.get_guest_by_conversation_id, req.conversation_id
            )
            if guest and guest.get("telegram_chat_id"):
                await telegram_client.send_message(
                    guest["telegram_chat_id"], req.message
                )
    except Exception as exc:
        log.warning("host_send: Telegram delivery failed for conv=%s: %s",
                    req.conversation_id, exc)

    return {"status": "sent"}


# ── Resolve escalation + learn ────────────────────────────────────────────────

class ResolveRequest(BaseModel):
    booking_id: str


@router.post("/conversations/resolve")
async def resolve_conversation(req: ResolveRequest, authorization: str | None = Header(default=None)):
    host_id = await _require_host(authorization)
    if not await asyncio.to_thread(
        supabase_client.host_owns_booking, host_id, req.booking_id
    ):
        raise HTTPException(status_code=403, detail="Not your conversation")
    guest = await asyncio.to_thread(supabase_client.get_guest_by_booking_id, req.booking_id)
    if not guest:
        raise HTTPException(status_code=404, detail="Guest not found")

    conv_id, thread, escalation_reason = await asyncio.to_thread(
        supabase_client.get_conversation_thread_for_resolve,
        req.booking_id,
    )
    if not conv_id:
        raise HTTPException(status_code=404, detail="Conversation not found")

    property_id = guest["property_id"]

    # ── Automated-learning triage ────────────────────────────────────────────
    # Two layers decide whether this resolution becomes reusable knowledge; every
    # outcome is recorded (pseudonymized) in the learning_events ledger.
    learned_entry = None
    event = None  # (disposition, skip_reason, summary-or-None) to record

    if not thread:
        # Nothing to learn from (manual resolve of an empty/pending thread).
        event = ("dropped", "no_content", None)
    elif learning_triage.reason_disposition(escalation_reason) == "drop":
        # Layer 1: emergencies / hostility / financial / out-of-scope never
        # learn — skip the summarizer entirely (cheaper + no PII exposure).
        event = ("dropped", learning_triage.layer1_skip_reason(escalation_reason), None)
    else:
        # Layer 2: let the summarizer judge reusability.
        try:
            summary = await asyncio.wait_for(
                gemini_messenger.summarize_escalation(thread),
                timeout=GEMINI_TIMEOUT_S,
            )
            reusable = bool(summary.get("is_reusable_knowledge"))
            has_content = bool(
                (summary.get("problem_summary") or "").strip()
                or (summary.get("solution_summary") or "").strip()
            )
            if reusable and has_content:
                learned_entry = {
                    "problem_summary": summary.get("problem_summary", ""),
                    "solution_summary": summary.get("solution_summary", ""),
                    "category": summary.get("category", "other"),
                    "language": summary.get("language", "en"),
                    "resolved_at": _now_iso(),
                    "booking_id": req.booking_id,
                    "reviewed": False,
                }
                event = ("learned", None, summary)
            else:
                event = ("dropped", summary.get("skip_reason") or "not_reusable", summary)
        except asyncio.TimeoutError:
            log.warning(
                "Gemini summarizer exceeded %ss for booking=%s; resolving without learning",
                GEMINI_TIMEOUT_S, req.booking_id,
            )
            event = ("dropped", "summarizer_timeout", None)
        except Exception as exc:
            log.exception("Summarizer failed for booking=%s: %s", req.booking_id, exc)
            event = ("dropped", "summarizer_error", None)

    await asyncio.to_thread(
        supabase_client.resolve_conversation,
        conv_id,
        property_id,
        learned_entry,
    )

    # Record the triage outcome in the permanent ledger. Best-effort — a ledger
    # hiccup must never fail the resolve the host just performed.
    if event:
        disposition, skip_reason, summary = event
        try:
            await asyncio.to_thread(
                supabase_client.record_learning_event,
                property_id,
                req.booking_id,
                escalation_reason,
                disposition,
                skip_reason,
                (summary or {}).get("problem_summary"),
                (summary or {}).get("solution_summary"),
                (summary or {}).get("category"),
                (summary or {}).get("language"),
            )
        except Exception as exc:
            log.warning("learning_events insert failed for booking=%s: %s",
                        req.booking_id, exc)

    # Telegram guest gets the same "Alfred has resumed" notice — only if TG is
    # their active channel (a web guest sees the marker via realtime).
    active_channel = await asyncio.to_thread(
        supabase_client.get_active_channel, conv_id
    )
    await _notify_tg_transition(guest, None, "resume", active_channel)

    return {"status": "resolved", "learned": learned_entry}


class ArchiveRequest(BaseModel):
    conversation_id: str


@router.post("/conversations/archive")
async def archive_conversation(req: ArchiveRequest, authorization: str | None = Header(default=None)):
    """Manually archive a conversation (host "delete conversation" action).

    Non-destructive: it drops off the dashboard active list but keeps messages
    and returns to active if the guest sends a new message (see
    supabase_client.insert_message)."""
    host_id = await _require_host(authorization)
    if not await asyncio.to_thread(
        supabase_client.host_owns_conversation, host_id, req.conversation_id
    ):
        raise HTTPException(status_code=403, detail="Not your conversation")
    await asyncio.to_thread(
        supabase_client.archive_conversation, req.conversation_id
    )
    return {"status": "archived"}


class TransitionRequest(BaseModel):
    conversation_id: str
    kind: str  # 'intervene' | 'resume'


@router.post("/conversations/announce-transition")
async def announce_transition(req: TransitionRequest, authorization: str | None = Header(default=None)):
    """Called by the host dashboard right after it inserts a manual mode-change
    marker (Intervene / Resume). Pushes the matching notice to the guest's
    Telegram if linked. No-op for web-only guests. Best-effort."""
    host_id = await _require_host(authorization)
    if not await asyncio.to_thread(
        supabase_client.host_owns_conversation, host_id, req.conversation_id
    ):
        raise HTTPException(status_code=403, detail="Not your conversation")
    guest = await asyncio.to_thread(
        supabase_client.get_guest_by_conversation_id, req.conversation_id
    )
    active_channel = await asyncio.to_thread(
        supabase_client.get_active_channel, req.conversation_id
    )
    host_name = None
    if req.kind == "intervene" and guest:
        prop = await asyncio.to_thread(
            supabase_client.get_property_for_chat, guest["property_id"]
        )
        _, host_name = _resolve_identity(prop)
    await _notify_tg_transition(guest, host_name, req.kind, active_channel)
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
async def create_guest(req: CreateGuestRequest, authorization: str | None = Header(default=None)):
    host_id = await _require_host(authorization)
    if not await asyncio.to_thread(
        supabase_client.host_owns_property, host_id, req.property_id
    ):
        raise HTTPException(status_code=403, detail="Not your property")
    # Fetch property name for the slug
    prop = await asyncio.to_thread(supabase_client.get_property_for_chat, req.property_id)
    if not prop:
        raise HTTPException(status_code=404, detail="Property not found")

    slug = _slugify(prop.get("name") or "property")
    frontend_url = os.environ.get("FRONTEND_URL", "").split(",")[0].strip().rstrip("/")
    bot_username = os.environ.get("TELEGRAM_BOT_USERNAME", "").lstrip("@").strip()
    # t.me and telegram.me are interchangeable official front-ends for the same
    # deep link. Keep the domain configurable: on 2026-07-13 t.me stopped
    # resolving worldwide (NXDOMAIN from three independent networks) while
    # telegram.me stayed up, which would otherwise have left every guest unable
    # to reach the bot with no lever on our side.
    tg_domain = os.environ.get("TELEGRAM_LINK_DOMAIN", "t.me").strip().strip("/")

    # Retry on booking_id collision (very unlikely but safe)
    for _ in range(5):
        booking_id = f"{slug}-{_random_suffix()}"
        guest_chat_url = f"{frontend_url}/chat?booking={booking_id}"
        host_chat_url = f"{frontend_url}/chat-live?booking={booking_id}&property={req.property_id}"
        # Telegram deep link: tapping it opens the bot and sends `/start <booking_id>`,
        # which links this guest's chat. booking_ids are [a-z0-9-] → Telegram-safe.
        telegram_link = (
            f"https://{tg_domain}/{bot_username}?start={booking_id}"
            if bot_username else None
        )
        try:
            await asyncio.to_thread(
                supabase_client.create_guest,
                booking_id,
                req.property_id,
                req.guest_name,
                guest_chat_url,
                host_chat_url,
            )
            # Create the conversation + store the welcome now, so the new link
            # shows on the dashboard immediately as "Awaiting reply" (pending),
            # before the guest ever opens it. Idempotent on later /open.
            property_name, _ = _resolve_identity(prop)
            welcome_text = welcome.build_welcome(
                property_name or prop.get("name"),
                prop.get("master_json"),
                also_english=bool(prop.get("welcome_also_english")),
            )
            await asyncio.to_thread(
                supabase_client.ensure_conversation_with_welcome,
                booking_id, req.property_id, welcome_text,
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
