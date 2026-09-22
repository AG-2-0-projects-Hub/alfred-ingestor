"""Telegram guest + host-escalation channel — webhook receiver.

Guests chat with Alfred over Telegram exactly like the web messenger. A host
who has connected their own Telegram (see routers/properties.py's
/host/telegram/link-code and messages.py's escalation block) additionally gets
an alert on escalation and can reply directly from that chat — see
_handle_host_reply / _handle_callback below — without needing the dashboard
open at all.

Flow: validate the secret header → ack 200 immediately → do the real work
(Gemini can take ~15-45s) in a SEPARATE request dispatched by Cloud Tasks.

The ack must be immediate for two reasons: a slow webhook makes Telegram retry,
and Telegram serialises updates per chat — it withholds the next update for a
chat until the current one is answered, so blocking here would stall an incoming
album mid-delivery. But the work cannot simply continue after the response
either: Cloud Run throttles the CPU to ~0 once a response is sent, which froze
the old BackgroundTasks reply until the next request thawed it (guests saw
answers arrive minutes late, stacked). Cloud Tasks resolves both — see
services/task_queue.py. Where it is not configured (staging on Render, local),
we fall back to BackgroundTasks, which is safe on a non-throttled host.
"""
import asyncio
import logging
import os
import time

import httpx
from fastapi import APIRouter, BackgroundTasks, HTTPException, Request

from services import (
    burst_buffer, guardrails, supabase_client, task_queue, telegram_client,
    welcome,
)
from routers import messages as messages_router
from routers.messages import process_guest_message, _notify_channel_transition
from routers.guest_auth import _resolve_identity

router = APIRouter()

# Telegram splits an album (several photos sent at once) into one update per
# photo, all sharing a media_group_id. `_albums` collects a group so it can be
# answered as a single turn; the flush is scheduled once, by media_group_id, and
# runs a few seconds later once the siblings have landed.
_ALBUM_WINDOW_S = 3
_albums: dict[str, dict] = {}
log = logging.getLogger(__name__)

_STRANGER = (
    "I couldn't find that booking. Please use the exact Telegram link your host "
    "shared with you."
)
_INCOMPLETE_START = (
    "👋 Welcome! Please open the Telegram link your host sent you so I can connect "
    "you to your booking."
)
_NOT_LINKED = (
    "You're not connected to a booking yet. Please open the Telegram link your host "
    "shared, then tap *Start*."
)
_MEDIA_ONLY = "For now I can only read text messages — please type your question."
_TOO_LONG = "Sorry, that took a little too long. Please send your message again."
_GENERIC_ERR = "Sorry, something went wrong on my side. Please try again in a moment."

# Host-side (escalation alerts + reply-from-Telegram) — see routers/messages.py's
# escalation block for where the alert itself is sent.
_HOST_LINK_EXPIRED = (
    "This connection link has expired or was already used. Generate a new one "
    "from your dashboard profile."
)
_HOST_LINKED = "✅ Connected! You'll get an alert here whenever a guest needs you."
_HOST_REPLY_NONE_ACTIVE = "No conversation is currently waiting for a reply."
_HOST_REPLY_AMBIGUOUS = (
    "You have more than one conversation waiting for a reply. Please reply "
    "directly to the alert for the guest you want to answer (swipe/long-press "
    "it → Reply)."
)
_RESOLVED_PREFIX = "resolved_"


def _check_secret(request: Request) -> None:
    """Telegram sends this header when the webhook was registered with a
    secret_token; Cloud Tasks sends the same one back on the worker callback.
    The service must stay publicly reachable (Telegram calls it), so this shared
    secret — not IAM — is what guards both endpoints."""
    expected = os.environ.get("TELEGRAM_WEBHOOK_SECRET")
    provided = request.headers.get("X-Telegram-Bot-Api-Secret-Token")
    if not expected or provided != expected:
        raise HTTPException(status_code=403, detail="forbidden")


@router.post("/telegram/webhook")
async def telegram_webhook(request: Request, background_tasks: BackgroundTasks):
    _check_secret(request)

    try:
        update = await request.json()
    except Exception:
        return {"ok": True}

    await _dispatch(update, background_tasks)
    return {"ok": True}


@router.post("/telegram/process")
async def telegram_process(request: Request):
    """Worker endpoint — only Cloud Tasks calls this, a few seconds after the
    webhook already answered Telegram. Being a request of its own is the whole
    point: Cloud Run allocates CPU for its full duration, so the Gemini call can
    take its time without being throttled mid-flight."""
    _check_secret(request)

    try:
        job = await request.json()
    except Exception:
        return {"ok": True}

    kind = job.get("kind")
    if kind == "album":
        await _flush_album(
            job.get("chat_id"), job.get("group_id"),
            job.get("seed_items") or [], job.get("caption") or "",
        )
    elif kind == "burst":
        await _flush_burst(job.get("chat_id"), job.get("seed") or [])
    elif kind == "update":
        await _handle_update(job.get("update") or {})
    elif kind == "callback":
        await _handle_callback(job.get("callback") or {})
    elif kind == "host_reply":
        await _handle_host_reply(
            job.get("chat_id"), job.get("host_id"),
            job.get("text") or "", job.get("reply_to_message_id"),
        )
    return {"ok": True}


async def _flush_burst(chat_id, seed: list[str]) -> None:
    """Answer a run of quick guest messages as one turn. The messages themselves
    were already stored as they arrived (see _dispatch), so the host sees the
    bubbles the guest actually sent — only the ANSWER is coalesced."""
    if chat_id is None:
        return
    messages = burst_buffer.pop(f"tg:{chat_id}", seed)
    if not messages:
        return
    await _handle_guest_message(
        chat_id, burst_buffer.combine(messages), already_stored=True,
    )


async def _sleep_then_flush_burst(chat_id) -> None:
    await asyncio.sleep(burst_buffer.WINDOW_SECONDS)
    await _flush_burst(chat_id, [])


async def _dispatch(update: dict, background_tasks: BackgroundTasks) -> None:
    """Hand the update to whatever can run it with a CPU: Cloud Tasks in prod,
    an in-process BackgroundTask on a host that doesn't throttle (staging/local).

    Two cases can't be dispatched per-update, because several updates are really
    one turn — a photo album (one update per photo, shared media_group_id) and a
    burst of quick text messages ("Dos perros" / "Y tres gatos"). Both collect
    their parts and schedule a SINGLE flush, named after the group/chat: Cloud
    Tasks rejects the duplicate name, so the rest ride along instead of each
    triggering its own reply.
    """
    callback = update.get("callback_query")
    if callback:
        if task_queue.enabled():
            task_queue.enqueue("/api/telegram/process", {"kind": "callback", "callback": callback})
        else:
            background_tasks.add_task(_handle_callback, callback)
        return

    message = update.get("message") or update.get("edited_message") or {}
    chat_id = (message.get("chat") or {}).get("id")
    text = message.get("text")

    # Host branch: a plain-text message from a chat_id already linked to a host
    # account (via "Connect Telegram") is a reply-to-guest attempt, not guest
    # conversation — route it before any of the guest album/burst logic below.
    # Commands ('/start H-...') are excluded so linking itself is unaffected.
    # Only plain text is handled here — hosts don't send photos/voice through
    # this bot in V1 (see FMEA "out of scope" row).
    if chat_id is not None and text and not text.startswith("/"):
        host_id = await asyncio.to_thread(
            supabase_client.get_host_by_telegram_chat_id, chat_id
        )
        if host_id:
            reply_to_message_id = (message.get("reply_to_message") or {}).get("message_id")
            job = {
                "kind": "host_reply", "chat_id": chat_id, "host_id": host_id,
                "text": text, "reply_to_message_id": reply_to_message_id,
            }
            if task_queue.enabled():
                task_queue.enqueue("/api/telegram/process", job)
            else:
                background_tasks.add_task(
                    _handle_host_reply, chat_id, host_id, text, reply_to_message_id
                )
            return

    group_id = message.get("media_group_id")
    photo = message.get("photo")

    if group_id and isinstance(photo, list) and photo and chat_id is not None:
        file_id = photo[-1].get("file_id")
        caption = message.get("caption") or ""
        item = [file_id, "image", "image/jpeg"]

        entry = _albums.setdefault(group_id, {"items": [], "caption": ""})
        entry["items"].append(item)
        if caption and not entry["caption"]:
            entry["caption"] = caption

        if not task_queue.enabled():
            # Non-throttled host: the classic debounce still works.
            if len(entry["items"]) == 1:
                background_tasks.add_task(
                    _sleep_then_flush_album, chat_id, group_id
                )
            return

        # `seed_items` is a safety net: the flush lands on whichever instance
        # Cloud Run routes it to, and only the enqueueing one holds `_albums`.
        # In practice that is the same instance, but if it ever isn't, the guest
        # still gets an answer about the first photo rather than silence.
        task_queue.enqueue(
            "/api/telegram/process",
            {"kind": "album", "group_id": group_id, "chat_id": chat_id,
             "seed_items": [item], "caption": caption},
            delay_seconds=_ALBUM_WINDOW_S,
            name=f"album-{task_queue.sanitize_task_name(group_id)}",
        )
        return

    # Plain text from a linked guest → coalesce a burst into one turn. `/start`
    # is a command, not conversation, so it stays immediate.
    if text and not text.startswith("/") and chat_id is not None:
        guest = await asyncio.to_thread(
            supabase_client.get_guest_by_telegram_chat_id, chat_id
        )
        if not guest:
            await telegram_client.send_message(chat_id, _NOT_LINKED)
            return

        # Store it now so the host's dashboard shows the message the instant it
        # lands (and lights up live over realtime), even though the ANSWER waits
        # for the rest of the burst.
        await messages_router.store_guest_text(
            guest["booking_id"], text, channel="telegram",
        )

        opened = burst_buffer.add(f"tg:{chat_id}", text)
        if not opened:
            return  # a flush is already scheduled; this message rides along

        if not task_queue.enabled():
            background_tasks.add_task(_sleep_then_flush_burst, chat_id)
            return

        task_queue.enqueue(
            "/api/telegram/process",
            {"kind": "burst", "chat_id": chat_id, "seed": [text]},
            delay_seconds=burst_buffer.WINDOW_SECONDS,
            name=f"burst-{task_queue.sanitize_task_name(str(chat_id))}"
                 f"-{int(time.time())}",
        )
        return

    if task_queue.enabled():
        task_queue.enqueue("/api/telegram/process",
                           {"kind": "update", "update": update})
    else:
        background_tasks.add_task(_handle_update, update)


async def _sleep_then_flush_album(chat_id, group_id: str) -> None:
    await asyncio.sleep(_ALBUM_WINDOW_S)
    await _flush_album(chat_id, group_id, [], "")


async def _flush_album(
    chat_id, group_id: str, seed_items: list, seed_caption: str,
) -> None:
    entry = _albums.pop(group_id, None) if group_id else None
    items = entry["items"] if entry and entry["items"] else seed_items
    caption = (entry or {}).get("caption") or seed_caption
    if not items or chat_id is None:
        return
    await _handle_guest_media(chat_id, [tuple(i) for i in items], caption)


@router.post("/telegram/set-webhook")
async def set_webhook(request: Request):
    """One-shot: point this bot's webhook at THIS deployment. Guarded by the same
    secret, so the token never leaves the server. Call it once per environment
    (staging, then prod) after deploying. Registering here detaches any previous
    webhook (e.g. the legacy Make.com scenario) — a bot allows only one."""
    expected = os.environ.get("TELEGRAM_WEBHOOK_SECRET")
    provided = request.headers.get("X-Telegram-Bot-Api-Secret-Token")
    if not expected or provided != expected:
        raise HTTPException(status_code=403, detail="forbidden")

    token = os.environ.get("TELEGRAM_BOT_TOKEN")
    if not token:
        raise HTTPException(status_code=500, detail="TELEGRAM_BOT_TOKEN not set")

    # Build the public https webhook URL from the incoming request's host.
    base = str(request.base_url).rstrip("/")
    if base.startswith("http://"):
        base = "https://" + base[len("http://"):]
    webhook_url = f"{base}/api/telegram/webhook"

    async with httpx.AsyncClient(timeout=15) as client:
        resp = await client.post(
            f"https://api.telegram.org/bot{token}/setWebhook",
            json={
                "url": webhook_url,
                "secret_token": expected,
                "allowed_updates": ["message", "edited_message", "callback_query"],
            },
        )
    return {"requested_url": webhook_url, "telegram": resp.json()}


async def _handle_update(update: dict) -> None:
    """Process a single Telegram update. Guest text only (MVP)."""
    message = update.get("message") or update.get("edited_message")
    if not isinstance(message, dict):
        return  # callback_query is intercepted earlier in _dispatch; anything else is a no-op

    chat = message.get("chat") or {}
    chat_id = chat.get("id")
    if chat_id is None:
        return
    text = message.get("text")
    caption = message.get("caption") or ""

    try:
        if text and text.startswith("/start"):
            await _handle_start(chat_id, text)
            return

        # Photo → analyze as an image. Telegram sends a list of sizes; the last
        # is the largest. Album photos never reach here — _dispatch groups them
        # by media_group_id and routes the group to _flush_album instead.
        photo = message.get("photo")
        if isinstance(photo, list) and photo:
            file_id = photo[-1].get("file_id")
            if file_id:
                await _handle_guest_media(
                    chat_id, [(file_id, "image", "image/jpeg")], caption
                )
                return

        # Voice note / audio → transcribe + answer.
        voice = message.get("voice") or message.get("audio")
        if isinstance(voice, dict) and voice.get("file_id"):
            mime = voice.get("mime_type") or "audio/ogg"
            await _handle_guest_media(
                chat_id, [(voice["file_id"], "audio", mime)], caption
            )
            return

        if not text:
            # Other non-text (sticker, document, location, …) — unchanged.
            await telegram_client.send_message(chat_id, _MEDIA_ONLY)
            return

        await _handle_guest_message(chat_id, text)
    except Exception as exc:
        log.exception("telegram: failed handling update for chat=%s: %s", chat_id, exc)
        await telegram_client.send_message(chat_id, _GENERIC_ERR)


def _error_reply(he: HTTPException) -> str:
    """Map a process_guest_message failure to what the guest should read.

    410 carries its own guest-facing, already-localized text (the listing is
    gone) — showing "something went wrong" there would be a lie, and the guest
    would keep retrying a conversation that is never coming back.
    """
    if he.status_code == 504:
        return _TOO_LONG
    if he.status_code == 410 and isinstance(he.detail, dict):
        return he.detail.get("message") or _GENERIC_ERR
    return _GENERIC_ERR


async def _handle_start(chat_id, text: str) -> None:
    """`/start <booking_id>` links this Telegram chat to the guest booking.
    `/start H-<code>` (uppercase prefix — booking_ids are always a lowercase
    slug, so the two can never collide) links it to a host account instead."""
    payload = text[len("/start"):].strip()
    if not payload:
        await telegram_client.send_message(chat_id, _INCOMPLETE_START)
        return

    if payload.startswith("H-"):
        await _handle_host_start(chat_id, payload[len("H-"):])
        return

    guest = await asyncio.to_thread(supabase_client.get_guest_by_booking_id, payload)
    if not guest:
        await telegram_client.send_message(chat_id, _STRANGER)
        return

    prop = await asyncio.to_thread(
        supabase_client.get_property_for_chat, guest["property_id"]
    )
    # Don't link a chat to a listing that no longer exists — the guest would be
    # greeted by a property whose knowledge has been wiped, and every message
    # after it would bounce. Refuse the link and say so.
    if prop and prop.get("deleted_at"):
        await telegram_client.send_message(
            chat_id,
            guardrails.closed_conversation_notice(guest.get("preferred_language")),
        )
        return

    await asyncio.to_thread(supabase_client.link_guest_telegram, payload, chat_id)
    property_name, _ = _resolve_identity(prop)
    welcome_text = welcome.build_welcome(
        property_name or (prop or {}).get("name"),
        (prop or {}).get("master_json"),
        also_english=bool((prop or {}).get("welcome_also_english")),
    )
    # Create the conversation + store the welcome (once) so it shows on the
    # dashboard immediately, then greet the guest on Telegram.
    await asyncio.to_thread(
        supabase_client.ensure_conversation_with_welcome,
        payload, guest["property_id"], welcome_text,
    )
    await telegram_client.send_message(chat_id, welcome_text)


async def _handle_host_start(chat_id, code: str) -> None:
    """`/start H-<code>` links this Telegram chat to a host account (the
    "Connect Telegram" flow on the dashboard). The code is short-lived and
    single-use — see supabase_client.create_host_telegram_link_code."""
    host_id = await asyncio.to_thread(supabase_client.resolve_host_telegram_code, code)
    if not host_id:
        await telegram_client.send_message(chat_id, _HOST_LINK_EXPIRED)
        return
    await asyncio.to_thread(supabase_client.link_host_telegram, host_id, chat_id)
    await telegram_client.send_message(chat_id, _HOST_LINKED)


async def _handle_host_reply(
    chat_id, host_id: str, text: str, reply_to_message_id: int | None,
) -> None:
    """A typed message from a linked host's chat — deliver it to the guest.

    Routing: a reply-to a specific alert always wins (multi-property hosts can
    have several conversations escalated at once); otherwise fall back to "the
    one conversation currently awaiting a reply," refusing to guess if there
    is more than one. Every successfully routed reply gets a lightweight echo
    so the host is never unsure which guest/property it reached.
    """
    try:
        conversation = None
        if reply_to_message_id:
            conversation = await asyncio.to_thread(
                supabase_client.get_conversation_by_host_alert_message_id,
                host_id, reply_to_message_id,
            )
            if conversation and conversation.get("mode") != "intervene":
                # Stale/already-resolved alert — still deliver (harmless), but
                # this is worth knowing about rather than failing silently.
                log.warning(
                    "telegram host reply: conv=%s from reply-to=%s is not in "
                    "intervene mode (mode=%s)",
                    conversation["id"], reply_to_message_id, conversation.get("mode"),
                )

        if not conversation:
            active = await asyncio.to_thread(
                supabase_client.get_active_intervene_conversations, host_id
            )
            if not active:
                await telegram_client.send_message(chat_id, _HOST_REPLY_NONE_ACTIVE)
                return
            if len(active) > 1:
                await telegram_client.send_message(chat_id, _HOST_REPLY_AMBIGUOUS)
                return
            conversation = active[0]

        # _host_send_core's own DB calls (insert_message/update_conversation)
        # are NOT wrapped in try/except — that mirrors the original host_send
        # HTTP route, where an uncaught exception just 500s to the host's own
        # browser. There is no such backstop here: this runs off a Cloud Tasks
        # callback, so an uncaught exception would both leave the host with no
        # feedback at all AND risk Cloud Tasks retrying the job (a retry after
        # insert_message already succeeded would re-deliver the same reply to
        # the guest a second time). Catch it here instead.
        await messages_router._host_send_core(conversation["id"], text)
        label = conversation.get("guest_name") or "your guest"
        if conversation.get("property_name"):
            label = f"{label} — {conversation['property_name']}"
        await telegram_client.send_italic(chat_id, f"✓ Sent to {label}")
    except Exception as exc:
        log.exception("telegram host reply failed for host=%s: %s", host_id, exc)
        await telegram_client.send_message(chat_id, _GENERIC_ERR)


async def _handle_callback(callback: dict) -> None:
    """Inline-button press on a host's escalation alert. Only 'Mark Resolved'
    exists in V1 (callback_data 'resolved_<booking_id>'); anything else is
    answered as unsupported rather than silently ignored, so the button never
    just spins forever client-side."""
    callback_id = callback.get("id")
    data = callback.get("data") or ""
    message = callback.get("message") or {}
    chat_id = (message.get("chat") or {}).get("id")
    message_id = message.get("message_id")

    if not data.startswith(_RESOLVED_PREFIX) or chat_id is None:
        if callback_id:
            await telegram_client.answer_callback_query(callback_id, "Unsupported action")
        return

    booking_id = data[len(_RESOLVED_PREFIX):]
    try:
        host_id = await asyncio.to_thread(
            supabase_client.get_host_by_telegram_chat_id, chat_id
        )
        owns = host_id and await asyncio.to_thread(
            supabase_client.host_owns_booking, host_id, booking_id
        )
        if not owns:
            # Rejected silently (generic toast only) — never confirms whether
            # the booking exists, so this can't be used to probe other hosts'
            # data.
            if callback_id:
                await telegram_client.answer_callback_query(callback_id, "Not your conversation")
            return

        await messages_router._resolve_conversation_core(booking_id)
    except Exception as exc:
        log.exception("telegram resolve callback failed for booking=%s: %s", booking_id, exc)
        if callback_id:
            await telegram_client.answer_callback_query(
                callback_id, "Something went wrong — try the dashboard"
            )
        return

    if callback_id:
        await telegram_client.answer_callback_query(callback_id, "Resolved ✓")
    if message_id is not None:
        await telegram_client.edit_message(chat_id, message_id, "✅ Resolved")


async def _handle_guest_message(
    chat_id, text: str, already_stored: bool = False,
) -> None:
    """A normal message from a linked guest → run the shared Brain and reply."""
    guest = await asyncio.to_thread(
        supabase_client.get_guest_by_telegram_chat_id, chat_id
    )
    if not guest:
        await telegram_client.send_message(chat_id, _NOT_LINKED)
        return

    await telegram_client.send_chat_action(chat_id, "typing")

    try:
        result = await process_guest_message(
            guest["booking_id"], text, channel="telegram",
            already_stored=already_stored,
        )
    except HTTPException as he:
        await telegram_client.send_message(chat_id, _error_reply(he))
        return

    # In intervene mode `reply` is None — the host answers from the dashboard and
    # host_send delivers it here; stay silent.
    reply = result.get("reply")
    if reply:
        await telegram_client.send_message(chat_id, reply)

    await _emit_escalation_notice(guest, result)


async def _handle_guest_media(
    chat_id, items: list[tuple[str, str, str]], caption: str,
) -> None:
    """Photos / a voice note from a linked guest → download them, run the shared
    Brain ONCE with all the media attached (Alfred analyzes the images / transcribes
    the voice), and send a single reply. An album therefore yields one reply and one
    transition notice, not one per photo. The media is also saved to chat_media so
    the host sees it. `items` is a list of (file_id, kind, mime)."""
    guest = await asyncio.to_thread(
        supabase_client.get_guest_by_telegram_chat_id, chat_id
    )
    if not guest:
        await telegram_client.send_message(chat_id, _NOT_LINKED)
        return

    media: list[dict] = []
    for file_id, kind, mime in items:
        data = await telegram_client.download_file(file_id)
        if data:
            media.append({"kind": kind, "mime": mime, "bytes": data})
    if not media:
        await telegram_client.send_message(chat_id, _GENERIC_ERR)
        return

    await telegram_client.send_chat_action(chat_id, "typing")
    try:
        result = await process_guest_message(
            guest["booking_id"], caption, channel="telegram", media=media,
        )
    except HTTPException as he:
        await telegram_client.send_message(chat_id, _error_reply(he))
        return

    reply = result.get("reply")
    if reply:
        await telegram_client.send_message(chat_id, reply)

    await _emit_escalation_notice(guest, result)


async def _emit_escalation_notice(guest: dict, result: dict) -> None:
    # On auto-escalation, send the "You are now speaking with <host>" notice
    # AFTER Alfred's reply, so the guest reads the acknowledgement first and the
    # notice doesn't make the reply look like the host wrote it. (A web guest
    # renders the __SYS_INTERVENE__ marker via realtime; this is Telegram-only.)
    if result.get("requires_escalation"):
        await _notify_channel_transition(
            guest, result.get("host_name"), "intervene", "telegram"
        )
