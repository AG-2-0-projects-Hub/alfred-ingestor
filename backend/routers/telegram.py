"""Telegram guest channel — webhook receiver.

Guests chat with Alfred over Telegram exactly like the web messenger; the host
keeps using the dashboard (escalations surface there, and the host's reply is
delivered back to the guest's Telegram via messages.host_send).

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

Host-side Telegram (relay + inline buttons) is intentionally out of scope.
"""
import asyncio
import logging
import os

import httpx
from fastapi import APIRouter, BackgroundTasks, HTTPException, Request

from services import supabase_client, task_queue, telegram_client, welcome
from routers.messages import process_guest_message, _notify_tg_transition
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
    elif kind == "update":
        await _handle_update(job.get("update") or {})
    return {"ok": True}


async def _dispatch(update: dict, background_tasks: BackgroundTasks) -> None:
    """Hand the update to whatever can run it with a CPU: Cloud Tasks in prod,
    an in-process BackgroundTask on a host that doesn't throttle (staging/local).

    An album is the one case that can't be dispatched per-update: Telegram sends
    one update per photo, so we collect the group and schedule a SINGLE flush,
    named after the media_group_id — Cloud Tasks rejects the duplicate name, so
    the siblings ride along instead of each triggering their own reply.
    """
    message = update.get("message") or update.get("edited_message") or {}
    chat_id = (message.get("chat") or {}).get("id")
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
                "allowed_updates": ["message", "edited_message"],
            },
        )
    return {"requested_url": webhook_url, "telegram": resp.json()}


async def _handle_update(update: dict) -> None:
    """Process a single Telegram update. Guest text only (MVP)."""
    message = update.get("message") or update.get("edited_message")
    if not isinstance(message, dict):
        return  # callback_query / other update types are out of scope for MVP

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


async def _handle_start(chat_id, text: str) -> None:
    """`/start <booking_id>` links this Telegram chat to the guest booking."""
    payload = text[len("/start"):].strip()
    if not payload:
        await telegram_client.send_message(chat_id, _INCOMPLETE_START)
        return

    guest = await asyncio.to_thread(supabase_client.get_guest_by_booking_id, payload)
    if not guest:
        await telegram_client.send_message(chat_id, _STRANGER)
        return

    await asyncio.to_thread(supabase_client.link_guest_telegram, payload, chat_id)
    prop = await asyncio.to_thread(
        supabase_client.get_property_for_chat, guest["property_id"]
    )
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


async def _handle_guest_message(chat_id, text: str) -> None:
    """A normal message from a linked guest → run the shared Brain and reply."""
    guest = await asyncio.to_thread(
        supabase_client.get_guest_by_telegram_chat_id, chat_id
    )
    if not guest:
        await telegram_client.send_message(chat_id, _NOT_LINKED)
        return

    await telegram_client.send_chat_action(chat_id, "typing")

    try:
        result = await process_guest_message(guest["booking_id"], text, channel="telegram")
    except HTTPException as he:
        await telegram_client.send_message(
            chat_id, _TOO_LONG if he.status_code == 504 else _GENERIC_ERR
        )
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
        await telegram_client.send_message(
            chat_id, _TOO_LONG if he.status_code == 504 else _GENERIC_ERR
        )
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
        await _notify_tg_transition(
            guest, result.get("host_name"), "intervene", "telegram"
        )
