"""Thin async wrapper over the WhatsApp Cloud API (Meta, direct — no BSP).

The Telegram counterpart (services/telegram_client.py) is the template; this
mirrors it deliberately so the two channels stay comparable. Four senders:
  - send_message(): Alfred's AI answers and the welcome. Auto-splits at 4096.
  - send_italic(): system/transition notices, wrapped in WhatsApp's _italic_.
  - mark_read(): blue ticks + the "typing…" bubble while Gemini composes. This is
    the WhatsApp analogue of Telegram's sendChatAction.
  - download_media(): guest photos / voice notes, as raw bytes.

FOUR WAYS THIS DIFFERS FROM TELEGRAM — each cost a design decision:

1. Media download is TWO steps AND authenticated. Telegram's file endpoint serves
   bytes to anyone holding the resolved path; Meta's does not. GET /<media_id>
   returns a short-lived CDN url which must ITSELF be fetched with the bearer
   token. Sending an unauthenticated GET to that url returns 401, not bytes.

2. There is no way to disable formatting. Telegram let us dodge its Markdown
   parser entirely by omitting parse_mode — the fix for answers containing _ * [ `
   silently 400-ing. WhatsApp has no such switch and no escape syntax: _foo_ in an
   AI answer WILL render as italic. That is cosmetic and benign (Gemini writes
   prose, not markup), so we send content through unaltered rather than mangling
   it — but see _strip_markup for where it does matter.

3. The 24-hour service window. Outside 24h from the guest's last inbound message,
   Meta REJECTS a free-form send with error 131047 and it must be a pre-approved
   template instead. Callers that can hit this (host_send) check the window first;
   send_message surfaces the code so the caller can tell the host what happened
   rather than reporting a success that never arrived.

4. Meta redelivers. A non-200 from our webhook, or simply Meta's own retry, can
   deliver the same message twice — Telegram's per-chat serialisation meant we
   never needed idempotency. That is handled at the router (Cloud Tasks task name
   keyed on the message id), not here.
"""
import logging
import os

import httpx

log = logging.getLogger(__name__)

_GRAPH = "https://graph.facebook.com"
# WhatsApp's own limit for a text message body.
_MAX_LEN = 4096

# Meta error code for "outside the 24h customer service window". The caller turns
# this into an actionable message for the host instead of a silent failure.
WINDOW_EXPIRED_CODE = 131047


def _api_version() -> str:
    return os.environ.get("WHATSAPP_API_VERSION", "v25.0")


def _token() -> str:
    token = os.environ.get("WHATSAPP_ACCESS_TOKEN")
    if not token:
        raise RuntimeError("WHATSAPP_ACCESS_TOKEN is not set")
    return token


def _phone_number_id() -> str:
    pnid = os.environ.get("WHATSAPP_PHONE_NUMBER_ID")
    if not pnid:
        raise RuntimeError("WHATSAPP_PHONE_NUMBER_ID is not set")
    return pnid


def _auth_headers() -> dict:
    return {"Authorization": f"Bearer {_token()}"}


def _chunks(text: str, limit: int = _MAX_LEN):
    """Split text into <=limit pieces, preferring a newline boundary.
    Mirrors telegram_client._chunks — same contract, same limit."""
    while len(text) > limit:
        cut = text.rfind("\n", 0, limit)
        if cut <= 0:
            cut = limit
        yield text[:cut]
        text = text[cut:].lstrip("\n")
    if text:
        yield text


def _strip_markup(text: str) -> str:
    """Remove WhatsApp's formatting characters from text we are about to WRAP in
    formatting ourselves.

    WhatsApp has no escape syntax, so a host name like `Jean_Luc` inside an
    _italic_ notice would terminate the italic run early and leave stray
    underscores on screen. Only used by send_italic — plain answers keep their
    characters (see the module docstring, point 2)."""
    return text.replace("_", " ").replace("*", "").replace("~", "")


async def _post_message(payload: dict) -> dict | None:
    """POST to the messages endpoint. Returns the parsed body (including Meta's
    error object on failure) or None if the request never completed — the caller
    can distinguish "Meta refused" from "we could not reach Meta"."""
    url = f"{_GRAPH}/{_api_version()}/{_phone_number_id()}/messages"
    try:
        async with httpx.AsyncClient(timeout=15) as client:
            resp = await client.post(url, json=payload, headers=_auth_headers())
        data = resp.json()
    except Exception as exc:  # network/transport — never bubble into the webhook
        log.warning("whatsapp send error: %s", exc)
        return None

    error = data.get("error")
    if error:
        # Log the code explicitly: 131047 (window expired) and 131026 (undeliverable
        # / not a WhatsApp user) are the two that mean something actionable rather
        # than a bug on our side.
        log.warning(
            "whatsapp send failed: code=%s subcode=%s %s",
            error.get("code"), error.get("error_subcode"), error.get("message"),
        )
    return data


def send_failed_code(result: dict | None) -> int | None:
    """Extract Meta's error code from a send result, if it failed. None means the
    send succeeded (or never reached Meta, which is logged separately)."""
    if not result:
        return None
    error = result.get("error")
    return error.get("code") if isinstance(error, dict) else None


async def send_message(wa_id: str, text: str) -> dict | None:
    """Send plain text (AI answers, welcome). Auto-splits over 4096 chars.

    Returns the LAST chunk's result — matching telegram_client.send_message. If an
    early chunk fails the guest sees a partial answer; that is the same tradeoff
    Telegram has, and splitting is rare enough not to warrant unwinding."""
    last = None
    for chunk in _chunks(text):
        last = await _post_message({
            "messaging_product": "whatsapp",
            "recipient_type": "individual",
            "to": str(wa_id),
            "type": "text",
            # preview_url False for the same reason Telegram sets
            # disable_web_page_preview: a link in an answer should not blow up
            # into a card that buries the text under it.
            "text": {"preview_url": False, "body": chunk},
        })
    return last


async def send_italic(wa_id: str, text: str) -> dict | None:
    """Send an italic system/transition notice (handoff, resumed, resolved).

    WhatsApp cannot set text colour, so italic is the closest match to the web
    client's "italic + muted" system style — the same call Telegram makes."""
    return await _post_message({
        "messaging_product": "whatsapp",
        "recipient_type": "individual",
        "to": str(wa_id),
        "type": "text",
        "text": {"preview_url": False, "body": f"_{_strip_markup(text)}_"},
    })


async def mark_read(wa_id: str, message_id: str, typing: bool = True) -> dict | None:
    """Mark the guest's message read and (optionally) show the typing indicator.

    Meta ties the typing indicator to the read receipt — it cannot be sent on its
    own, and it expires by itself after ~25s or when our reply lands, so there is
    nothing to clear. `wa_id` is unused by the API here (the message id identifies
    the chat) but is kept in the signature so callers read the same as the
    Telegram ones. Best-effort: a failure here must never cost the guest a reply.
    """
    payload = {
        "messaging_product": "whatsapp",
        "status": "read",
        "message_id": message_id,
    }
    if typing:
        payload["typing_indicator"] = {"type": "text"}

    url = f"{_GRAPH}/{_api_version()}/{_phone_number_id()}/messages"
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            resp = await client.post(url, json=payload, headers=_auth_headers())
        return resp.json()
    except Exception as exc:
        log.warning("whatsapp mark_read error: %s", exc)
        return None


async def download_media(media_id: str) -> bytes | None:
    """Fetch a guest's media as raw bytes by media_id.

    Two steps, BOTH authenticated: GET /<media_id> returns a short-lived CDN url,
    then that url must be fetched with the same bearer token (an unauthenticated
    GET returns 401, not the file). Returns None on any failure — the caller falls
    back to the generic error reply, exactly as the Telegram path does.
    """
    try:
        async with httpx.AsyncClient(timeout=30) as client:
            meta = await client.get(
                f"{_GRAPH}/{_api_version()}/{media_id}", headers=_auth_headers(),
            )
            if meta.status_code != 200:
                log.warning(
                    "whatsapp download_media: lookup HTTP %s for %s",
                    meta.status_code, media_id,
                )
                return None

            url = (meta.json() or {}).get("url")
            if not url:
                log.warning("whatsapp download_media: no url for %s", media_id)
                return None

            # The CDN host differs from graph.facebook.com but still requires the
            # bearer token. This is the step that silently 401s if you reuse a
            # plain client.
            resp = await client.get(url, headers=_auth_headers())
        if resp.status_code != 200:
            log.warning(
                "whatsapp download_media: fetch HTTP %s for %s",
                resp.status_code, media_id,
            )
            return None
        return resp.content
    except Exception as exc:
        log.warning("whatsapp download_media error: %s", exc)
        return None
