"""Telegram guest channel — webhook receiver.

Guests chat with Alfred over Telegram exactly like the web messenger; the host
keeps using the dashboard (escalations surface there, and the host's reply is
delivered back to the guest's Telegram via messages.host_send).

Flow: validate the secret header → ack 200 immediately → process in the
background (Gemini can take up to ~45s; a slow webhook makes Telegram retry).
Host-side Telegram (relay + inline buttons) is intentionally out of scope.
"""
import asyncio
import logging
import os

import httpx
from fastapi import APIRouter, BackgroundTasks, HTTPException, Request

from services import supabase_client, telegram_client, welcome
from routers.messages import process_guest_message, _notify_tg_transition
from routers.guest_auth import _resolve_identity

router = APIRouter()

# Telegram splits an album (several photos sent at once) into one update per
# photo, all sharing a media_group_id. `_albums` buffers a group for this long
# so it can be answered as a single turn. Safe as process state: the backend runs
# with min-instances=1, and a lost buffer only costs one album's grouping.
_ALBUM_WINDOW_S = 2.0
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


@router.post("/telegram/webhook")
async def telegram_webhook(request: Request, background_tasks: BackgroundTasks):
    # Telegram sends this header when the webhook was registered with a
    # secret_token. Reject anything that doesn't match.
    expected = os.environ.get("TELEGRAM_WEBHOOK_SECRET")
    provided = request.headers.get("X-Telegram-Bot-Api-Secret-Token")
    if not expected or provided != expected:
        raise HTTPException(status_code=403, detail="forbidden")

    try:
        update = await request.json()
    except Exception:
        return {"ok": True}

    background_tasks.add_task(_handle_update, update)
    return {"ok": True}


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
        # is the largest. An album shares a media_group_id across updates, so
        # buffer those and answer the whole group once.
        photo = message.get("photo")
        if isinstance(photo, list) and photo:
            file_id = photo[-1].get("file_id")
            if file_id:
                group_id = message.get("media_group_id")
                if group_id:
                    await _buffer_album_photo(chat_id, group_id, file_id, caption)
                else:
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


async def _buffer_album_photo(
    chat_id, group_id: str, file_id: str, caption: str,
) -> None:
    """Collect the photos of one Telegram album, then handle them as a single turn.

    Telegram delivers an album as one update PER PHOTO, all sharing a
    media_group_id. Without this, each photo ran the Brain separately — the guest
    got one reply per photo and a "now speaking with <host>" notice per photo.
    The first photo of a group waits briefly for its siblings, then flushes once.
    """
    entry = _albums.get(group_id)
    if entry is not None:
        entry["items"].append((file_id, "image", "image/jpeg"))
        if caption and not entry["caption"]:
            entry["caption"] = caption
        return

    _albums[group_id] = {"items": [(file_id, "image", "image/jpeg")], "caption": caption}
    await asyncio.sleep(_ALBUM_WINDOW_S)
    entry = _albums.pop(group_id, None)
    if entry:
        await _handle_guest_media(chat_id, entry["items"], entry["caption"])


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
