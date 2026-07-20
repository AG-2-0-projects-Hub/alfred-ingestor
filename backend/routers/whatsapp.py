"""WhatsApp guest channel — webhook receiver (Meta Cloud API, direct).

A port of the native Telegram channel (routers/telegram.py). Guests chat with
Alfred over WhatsApp exactly like the web messenger and Telegram; the host keeps
using the dashboard, and their reply is delivered back via messages.host_send.

Flow is identical to Telegram: verify the request → ack 200 immediately → do the
real work (Gemini can take ~15-45s) in a SEPARATE request dispatched by Cloud
Tasks, because Cloud Run throttles CPU to ~0 once a response is sent. See
services/task_queue.py. Where Cloud Tasks is not configured (local), we fall back
to BackgroundTasks.

WHERE WHATSAPP IS NOT TELEGRAM — the four things that shaped this file:

1. THERE IS NO /start PAYLOAD. Telegram's t.me deep link carries the booking_id
   invisibly. wa.me has only `?text=`, a PREFILLED MESSAGE THE GUEST CAN EDIT OR
   DELETE. So linking parses a booking-id-shaped token out of the first message,
   and — critically — must not go silent when it isn't there, because real guests
   WILL clear that text. See _handle_link and _NOT_LINKED.

2. META REDELIVERS. Any non-200, or Meta's own retry, can deliver a message
   twice; Telegram's per-chat serialisation meant we never needed idempotency.
   Two layers guard it: an in-process seen-set of message ids (_seen), and Cloud
   Tasks task names keyed on the message id (duplicate names are rejected).
   Hence this endpoint ALWAYS answers 200, even on a malformed payload — a 500
   here buys nothing and triggers Meta's retry storm.

3. NO media_group_id. WhatsApp sends several photos as SEPARATE messages with no
   grouping key at all, so an album is debounced by SENDER over a short window
   (_media_add), rather than by group id the way Telegram's _albums works.

4. THE 24-HOUR WINDOW. Replying to a guest is unrestricted within 24h of their
   last inbound message, which covers every reply this file sends. The constraint
   only bites host_send hours later — handled in routers/messages.py. Every
   inbound message stamps conversations.last_guest_inbound_at for it.
   ⚠️ Free ≠ unrestricted: these "service" messages are free of charge only until
   2026-10-01, when Meta extends per-message billing to them. The 24h RULE is
   unaffected; the COST assumption this channel was planned on is not.

Host-side WhatsApp and message templates are intentionally out of scope.
"""
import asyncio
import hashlib
import hmac
import logging
import os
import re
import time
from collections import deque

from fastapi import APIRouter, BackgroundTasks, HTTPException, Request
from fastapi.responses import PlainTextResponse

from services import (
    burst_buffer, guardrails, supabase_client, task_queue, welcome,
    whatsapp_client,
)
from routers import messages as messages_router
from routers.messages import process_guest_message, _notify_channel_transition
from routers.guest_auth import _resolve_identity

router = APIRouter()
log = logging.getLogger(__name__)

# Seconds to wait for the rest of a photo burst. Mirrors telegram._ALBUM_WINDOW_S.
_MEDIA_WINDOW_S = 3

# Photos from one sender, collected so an "album" becomes ONE turn. Process
# memory, exactly like telegram._albums — the scheduled task carries a seed so a
# guest is never left unanswered even if the flush lands on another instance.
_media_groups: dict[str, dict] = {}

# Message ids already handled, so Meta's redelivery cannot double-store a guest
# message. Bounded — this is a duplicate guard, not an audit log.
_SEEN_MAX = 2048
_seen_ids: set[str] = set()
_seen_order: deque[str] = deque()

# Booking ids are built as "<slug>-<6 random chars>" (messages._slugify +
# _random_suffix): lowercase [a-z0-9-], and the FINAL segment is exactly 6 chars.
#
# That last constraint is load-bearing, not pedantry. A looser
# `[a-z0-9]+(?:-[a-z0-9]+)+` matches "check-out" — a phrase guests in this domain
# type constantly — which would divert ordinary messages down the linking path and
# rob them of burst coalescing. Requiring a 6-char tail rules that out ("out" is
# 3). This only PROPOSES candidates; the database lookup is what decides.
_BOOKING_RE = re.compile(r"\b[a-z0-9]+(?:-[a-z0-9]+)*-[a-z0-9]{6}\b")

_STRANGER = (
    "I couldn't find that booking. Please open the WhatsApp link your host "
    "shared with you."
)
_NOT_LINKED = (
    "You're not connected to a booking yet. Please open the WhatsApp link your "
    "host shared with you, and send the message it prepares for you."
)
_UNSUPPORTED = (
    "For now I can read text, photos and voice notes — please send one of those."
)
_TOO_LONG = "Sorry, that took a little too long. Please send your message again."
_GENERIC_ERR = "Sorry, something went wrong on my side. Please try again in a moment."


# ── Request authentication ───────────────────────────────────────────────────

def _check_signature(raw: bytes, request: Request) -> None:
    """Verify Meta's X-Hub-Signature-256 over the RAW body.

    Must be the raw bytes: re-serialising the parsed JSON changes whitespace and
    key order, and the HMAC would never match. The service has to stay publicly
    reachable (Meta calls it), so this signature — not IAM — is what proves the
    request came from Meta.
    """
    secret = os.environ.get("WHATSAPP_APP_SECRET")
    if not secret:
        raise HTTPException(status_code=500, detail="WHATSAPP_APP_SECRET not set")

    provided = request.headers.get("X-Hub-Signature-256", "")
    expected = "sha256=" + hmac.new(
        secret.encode(), raw, hashlib.sha256
    ).hexdigest()
    # compare_digest, not ==, so a wrong signature can't be recovered byte by byte
    # from response timing.
    if not hmac.compare_digest(provided, expected):
        raise HTTPException(status_code=403, detail="forbidden")


def _check_worker_secret(request: Request) -> None:
    """Guard the Cloud Tasks callback.

    Reuses TELEGRAM_WEBHOOK_SECRET and the X-Telegram-Bot-Api-Secret-Token header
    because that is what services/task_queue.py sends on every task it creates.
    The name is now a misnomer — it is the generic worker-auth secret for this
    service — but renaming it would touch the live Telegram path for no
    behavioural gain, so it stays.
    """
    expected = os.environ.get("TELEGRAM_WEBHOOK_SECRET")
    provided = request.headers.get("X-Telegram-Bot-Api-Secret-Token")
    if not expected or provided != expected:
        raise HTTPException(status_code=403, detail="forbidden")


def _already_seen(message_id: str) -> bool:
    """True if this message id was already dispatched (Meta redelivery)."""
    if not message_id:
        return False
    if message_id in _seen_ids:
        return True
    _seen_ids.add(message_id)
    _seen_order.append(message_id)
    if len(_seen_order) > _SEEN_MAX:
        _seen_ids.discard(_seen_order.popleft())
    return False


# ── Endpoints ────────────────────────────────────────────────────────────────

@router.get("/whatsapp/webhook")
async def whatsapp_verify(request: Request):
    """Meta's one-time subscription handshake. It calls this with a verify token
    we chose and expects hub.challenge echoed back as PLAIN TEXT — a JSON-wrapped
    body fails the check."""
    params = request.query_params
    expected = os.environ.get("WHATSAPP_VERIFY_TOKEN")
    if (
        params.get("hub.mode") == "subscribe"
        and expected
        and params.get("hub.verify_token") == expected
    ):
        return PlainTextResponse(params.get("hub.challenge") or "")
    raise HTTPException(status_code=403, detail="forbidden")


@router.post("/whatsapp/webhook")
async def whatsapp_webhook(request: Request, background_tasks: BackgroundTasks):
    raw = await request.body()
    _check_signature(raw, request)

    try:
        payload = await request.json()
    except Exception:
        return {"ok": True}

    # Always 200 from here on. Meta retries anything else, and a payload we cannot
    # parse will not parse on the retry either — it would just loop.
    try:
        for entry in payload.get("entry") or []:
            for change in entry.get("changes") or []:
                await _dispatch(change.get("value") or {}, background_tasks)
    except Exception as exc:
        log.exception("whatsapp: dispatch failed: %s", exc)
    return {"ok": True}


@router.post("/whatsapp/process")
async def whatsapp_process(request: Request):
    """Worker endpoint — only Cloud Tasks calls this, a moment after the webhook
    already answered Meta. Being a request of its own is the whole point: Cloud
    Run allocates CPU for its full duration, so the Gemini call can take its time
    without being throttled mid-flight."""
    _check_worker_secret(request)

    try:
        job = await request.json()
    except Exception:
        return {"ok": True}

    kind = job.get("kind")
    if kind == "burst":
        await _flush_burst(job.get("wa_id"), job.get("seed") or [])
    elif kind == "media":
        await _flush_media(job.get("wa_id"), job.get("seed_items") or [],
                           job.get("caption") or "")
    elif kind == "link":
        await _handle_link(job.get("wa_id"), job.get("text") or "")
    elif kind == "message":
        await _handle_guest_message(job.get("wa_id"), job.get("text") or "")
    return {"ok": True}


# ── Dispatch ─────────────────────────────────────────────────────────────────

async def _dispatch(value: dict, background_tasks: BackgroundTasks) -> None:
    """Route one webhook `value` object to whatever can run it with a CPU.

    `value` also carries delivery/read `statuses` for messages WE sent — those are
    not guest input and are ignored.
    """
    for message in value.get("messages") or []:
        wa_id = message.get("from")
        wamid = message.get("id")
        if not wa_id or _already_seen(wamid):
            continue
        await _dispatch_one(wa_id, wamid, message, background_tasks)


async def _dispatch_one(
    wa_id: str, wamid: str, message: dict, background_tasks: BackgroundTasks,
) -> None:
    msg_type = message.get("type")

    # Blue-tick the guest's message and raise the typing bubble now, before the
    # burst window and the ~15-45s Gemini turn. This is the WhatsApp analogue of
    # Telegram's sendChatAction. Awaited rather than backgrounded because Cloud Run
    # throttles the CPU the instant this request responds. Best-effort inside the
    # client — it never costs the guest a reply.
    if wamid:
        await whatsapp_client.mark_read(wa_id, wamid)

    if msg_type == "text":
        text = ((message.get("text") or {}).get("body") or "").strip()
        if not text:
            return

        guest = await asyncio.to_thread(
            supabase_client.get_guest_by_whatsapp_wa_id, wa_id
        )

        # An unlinked sender, or a message that LOOKS like it carries a booking
        # code (a returning guest starting a new stay), goes down the linking
        # path. Only the cheap regex runs here — resolving the code needs database
        # round-trips per candidate, and this is pre-ack, where latency makes Meta
        # retry. _handle_link does the authoritative lookup in the worker and
        # falls through to a normal message if nothing resolves.
        if not guest or _BOOKING_RE.search(text.lower()):
            _enqueue(background_tasks, _handle_link,
                     {"kind": "link", "wa_id": wa_id, "text": text},
                     name=f"walink-{task_queue.sanitize_task_name(wamid)}",
                     args=(wa_id, text))
            return

        # Store it now so the host's dashboard shows the message the instant it
        # lands (and lights up live over realtime), even though the ANSWER waits
        # for the rest of the burst. Mirrors the Telegram path exactly.
        await messages_router.store_guest_text(
            guest["booking_id"], text, channel="whatsapp",
        )

        if not burst_buffer.add(f"wa:{wa_id}", text):
            return  # a flush is already scheduled; this message rides along

        _enqueue(background_tasks, _sleep_then_flush_burst,
                 {"kind": "burst", "wa_id": wa_id, "seed": [text]},
                 name=f"waburst-{task_queue.sanitize_task_name(wa_id)}"
                      f"-{int(time.time())}",
                 delay=burst_buffer.WINDOW_SECONDS,
                 args=(wa_id,))
        return

    if msg_type in ("image", "audio", "voice", "video", "document"):
        await _dispatch_media(wa_id, msg_type, message, background_tasks)
        return

    # Stickers, locations, contacts, reactions, system messages…
    await whatsapp_client.send_message(wa_id, _UNSUPPORTED)


async def _dispatch_media(
    wa_id: str, msg_type: str, message: dict, background_tasks: BackgroundTasks,
) -> None:
    """Collect media from one sender into a single turn.

    WhatsApp gives photos no grouping key, so several photos sent together arrive
    as independent messages. They are debounced by SENDER: the first opens the
    window and schedules the one flush, the rest ride along.
    """
    if msg_type in ("video", "document"):
        # The Brain handles images and audio only; saying so is better than
        # silently ignoring an attachment the guest thinks we read.
        await whatsapp_client.send_message(wa_id, _UNSUPPORTED)
        return

    node = message.get(msg_type) or {}
    media_id = node.get("id")
    if not media_id:
        return

    kind = "image" if msg_type == "image" else "audio"
    # WhatsApp voice notes are audio/ogg; codecs=opus — the same container
    # Telegram sends, which Gemini accepts. Do NOT "modernise" this to webm.
    mime = (node.get("mime_type") or
            ("image/jpeg" if kind == "image" else "audio/ogg")).split(";")[0].strip()
    caption = (node.get("caption") or "").strip()
    item = [media_id, kind, mime]

    opened = _media_add(wa_id, item, caption)
    if not opened:
        return

    _enqueue(background_tasks, _sleep_then_flush_media,
             {"kind": "media", "wa_id": wa_id, "seed_items": [item],
              "caption": caption},
             name=f"wamedia-{task_queue.sanitize_task_name(wa_id)}"
                  f"-{int(time.time())}",
             delay=_MEDIA_WINDOW_S,
             args=(wa_id,))


def _enqueue(
    background_tasks: BackgroundTasks, fallback_fn, payload: dict,
    *, name: str, delay: int = 0, args: tuple = (),
) -> None:
    """Cloud Tasks where configured, in-process BackgroundTask otherwise."""
    if not task_queue.enabled():
        background_tasks.add_task(fallback_fn, *args)
        return
    task_queue.enqueue(
        "/api/whatsapp/process", payload, delay_seconds=delay, name=name,
    )


def _media_add(wa_id: str, item: list, caption: str) -> bool:
    """Append a media item for `wa_id`. True if it opened a new group, i.e. the
    caller must schedule the flush. Mirrors burst_buffer.add."""
    entry = _media_groups.get(wa_id)
    if entry is None:
        _media_groups[wa_id] = {"items": [item], "caption": caption}
        return True
    entry["items"].append(item)
    if caption and not entry["caption"]:
        entry["caption"] = caption
    return False


async def _find_booking_code(text: str, exclude: str | None = None) -> str | None:
    """Pull a booking id out of the guest's message, if there is one.

    The wa.me deep link prefills something like "…mi reserva es paris-flat-hszxxv",
    but the guest can edit it, so we scan for every booking-id-shaped token and let
    the database decide. `exclude` is the sender's CURRENT booking — a linked guest
    repeating their own code is just conversation, not a re-link.
    """
    for candidate in _BOOKING_RE.findall(text.lower()):
        if exclude and candidate == exclude:
            continue
        guest = await asyncio.to_thread(
            supabase_client.get_guest_by_booking_id, candidate
        )
        if guest:
            return candidate
    return None


# ── Flushes ──────────────────────────────────────────────────────────────────

async def _sleep_then_flush_burst(wa_id: str) -> None:
    await asyncio.sleep(burst_buffer.WINDOW_SECONDS)
    await _flush_burst(wa_id, [])


async def _flush_burst(wa_id: str, seed: list) -> None:
    """Answer a run of quick guest messages as one turn. The messages themselves
    were already stored as they arrived (see _dispatch_one), so the host sees the
    bubbles the guest actually sent — only the ANSWER is coalesced."""
    if not wa_id:
        return
    messages = burst_buffer.pop(f"wa:{wa_id}", seed)
    if not messages:
        return
    await _handle_guest_message(
        wa_id, burst_buffer.combine(messages), already_stored=True,
    )


async def _sleep_then_flush_media(wa_id: str) -> None:
    await asyncio.sleep(_MEDIA_WINDOW_S)
    await _flush_media(wa_id, [], "")


async def _flush_media(wa_id: str, seed_items: list, seed_caption: str) -> None:
    if not wa_id:
        return
    entry = _media_groups.pop(wa_id, None)
    items = (entry or {}).get("items") or seed_items
    caption = (entry or {}).get("caption") or seed_caption
    if not items:
        return
    await _handle_guest_media(wa_id, items, caption)


# ── Handlers ─────────────────────────────────────────────────────────────────

def _error_reply(he: HTTPException) -> str:
    """Map a process_guest_message failure to what the guest should read.

    410 carries its own guest-facing, already-localized text (the listing is gone)
    — showing "something went wrong" there would be a lie, and the guest would
    keep retrying a conversation that is never coming back."""
    if he.status_code == 504:
        return _TOO_LONG
    if he.status_code == 410 and isinstance(he.detail, dict):
        return he.detail.get("message") or _GENERIC_ERR
    return _GENERIC_ERR


async def _handle_link(wa_id: str, text: str) -> None:
    """Link this WhatsApp sender to a booking, using the code in their message.

    The WhatsApp equivalent of Telegram's `/start <booking_id>` — but because the
    code rides in an EDITABLE prefilled message, the miss path is a real, expected
    outcome rather than a defensive branch.
    """
    guest_now = await asyncio.to_thread(
        supabase_client.get_guest_by_whatsapp_wa_id, wa_id
    )
    code = await _find_booking_code(text, exclude=(guest_now or {}).get("booking_id"))

    if not code:
        # Already linked and no new code: ordinary conversation that merely looked
        # like it might carry one.
        if guest_now:
            await _handle_guest_message(wa_id, text)
            return
        await whatsapp_client.send_message(
            wa_id, _NOT_LINKED if not _BOOKING_RE.search(text.lower()) else _STRANGER
        )
        return

    guest = await asyncio.to_thread(supabase_client.get_guest_by_booking_id, code)
    if not guest:
        await whatsapp_client.send_message(wa_id, _STRANGER)
        return

    prop = await asyncio.to_thread(
        supabase_client.get_property_for_chat, guest["property_id"]
    )
    # Don't link to a listing that no longer exists — the guest would be greeted by
    # a property whose knowledge has been wiped, and every message after it would
    # bounce. Refuse the link and say so, in their language.
    if prop and prop.get("deleted_at"):
        await whatsapp_client.send_message(
            wa_id,
            guardrails.closed_conversation_notice(guest.get("preferred_language")),
        )
        return

    await asyncio.to_thread(supabase_client.link_guest_whatsapp, code, wa_id)

    property_name, _ = _resolve_identity(prop)
    welcome_text = welcome.build_welcome(
        property_name or (prop or {}).get("name"),
        (prop or {}).get("master_json"),
        also_english=bool((prop or {}).get("welcome_also_english")),
    )
    # Create the conversation + store the welcome (once) so it shows on the
    # dashboard immediately, then greet the guest.
    conversation, _ = await asyncio.to_thread(
        supabase_client.ensure_conversation_with_welcome,
        code, guest["property_id"], welcome_text,
    )
    if conversation and conversation.get("id"):
        await asyncio.to_thread(
            supabase_client.set_active_channel, conversation["id"], "whatsapp"
        )
        await asyncio.to_thread(
            supabase_client.touch_guest_inbound, conversation["id"]
        )
    await whatsapp_client.send_message(wa_id, welcome_text)


async def _handle_guest_message(
    wa_id: str, text: str, already_stored: bool = False,
) -> None:
    """A normal message from a linked guest → run the shared Brain and reply."""
    guest = await asyncio.to_thread(
        supabase_client.get_guest_by_whatsapp_wa_id, wa_id
    )
    if not guest:
        await whatsapp_client.send_message(wa_id, _NOT_LINKED)
        return

    try:
        result = await process_guest_message(
            guest["booking_id"], text, channel="whatsapp",
            already_stored=already_stored,
        )
    except HTTPException as he:
        await whatsapp_client.send_message(wa_id, _error_reply(he))
        return

    await _deliver(wa_id, guest, result)


async def _handle_guest_media(wa_id: str, items: list, caption: str) -> None:
    """Photos / a voice note from a linked guest → download them, run the shared
    Brain ONCE with all the media attached, and send a single reply. Several
    photos therefore yield one reply and one transition notice, not one each."""
    guest = await asyncio.to_thread(
        supabase_client.get_guest_by_whatsapp_wa_id, wa_id
    )
    if not guest:
        await whatsapp_client.send_message(wa_id, _NOT_LINKED)
        return

    media: list[dict] = []
    for media_id, kind, mime in items:
        data = await whatsapp_client.download_media(media_id)
        if data:
            media.append({"kind": kind, "mime": mime, "bytes": data})
    if not media:
        await whatsapp_client.send_message(wa_id, _GENERIC_ERR)
        return

    try:
        result = await process_guest_message(
            guest["booking_id"], caption, channel="whatsapp", media=media,
        )
    except HTTPException as he:
        await whatsapp_client.send_message(wa_id, _error_reply(he))
        return

    await _deliver(wa_id, guest, result)


async def _deliver(wa_id: str, guest: dict, result: dict) -> None:
    """Send Alfred's reply, stamp the 24h window, then the escalation notice."""
    # In intervene mode `reply` is None — the host answers from the dashboard and
    # host_send delivers it here; stay silent.
    reply = result.get("reply")
    if reply:
        await whatsapp_client.send_message(wa_id, reply)

    conversation_id = result.get("conversation_id")
    if conversation_id:
        # Stamp AFTER the turn is processed: this is what host_send reads to know
        # whether Meta will still accept a free-form message.
        await asyncio.to_thread(
            supabase_client.touch_guest_inbound, conversation_id
        )

    # On auto-escalation, send the "You are now speaking with <host>" notice AFTER
    # Alfred's reply, so the guest reads the acknowledgement first and the notice
    # doesn't make the reply look like the host wrote it.
    if result.get("requires_escalation"):
        await _notify_channel_transition(
            guest, result.get("host_name"), "intervene", "whatsapp"
        )
