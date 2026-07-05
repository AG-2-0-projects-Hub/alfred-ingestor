"""Thin async wrapper over the Telegram Bot API.

Guest channel only (MVP). Two senders:
  - send_message(): PLAIN text — for Alfred's AI answers and the welcome. No
    parse_mode, so answers containing _ * [ ` never 400 on Telegram's Markdown
    parser (a real failure mode that would silently drop the reply).
  - send_italic(): system/transition notices in italic (HTML <i>), content
    escaped. Telegram can't set text colour, so italic is the closest match to
    the web's "italic + muted" system style.

Messages over Telegram's 4096-char limit are split into chunks. httpx is
already a backend dependency (see supabase_client.upload_hero_image).
"""
import logging
import os

import httpx

log = logging.getLogger(__name__)

_API = "https://api.telegram.org"
_MAX_LEN = 4096


def _token() -> str:
    token = os.environ.get("TELEGRAM_BOT_TOKEN")
    if not token:
        raise RuntimeError("TELEGRAM_BOT_TOKEN is not set")
    return token


def _chunks(text: str, limit: int = _MAX_LEN):
    """Split text into <=limit pieces, preferring a newline boundary."""
    while len(text) > limit:
        cut = text.rfind("\n", 0, limit)
        if cut <= 0:
            cut = limit
        yield text[:cut]
        text = text[cut:].lstrip("\n")
    if text:
        yield text


def _escape_html(text: str) -> str:
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


async def _post(method: str, payload: dict) -> dict | None:
    url = f"{_API}/bot{_token()}/{method}"
    try:
        async with httpx.AsyncClient(timeout=15) as client:
            resp = await client.post(url, json=payload)
        data = resp.json()
        if not data.get("ok"):
            log.warning("telegram %s failed: %s", method, data.get("description"))
        return data
    except Exception as exc:  # network/transport — never bubble into the webhook
        log.warning("telegram %s error: %s", method, exc)
        return None


async def send_message(chat_id, text: str) -> dict | None:
    """Send plain text (AI answers, welcome). Auto-splits over 4096 chars."""
    last = None
    for chunk in _chunks(text):
        last = await _post("sendMessage",
                           {"chat_id": chat_id, "text": chunk,
                            "disable_web_page_preview": True})
    return last


async def send_italic(chat_id, text: str) -> dict | None:
    """Send an italic system/transition notice (handoff, resumed, resolved)."""
    return await _post(
        "sendMessage",
        {"chat_id": chat_id, "text": f"<i>{_escape_html(text)}</i>",
         "parse_mode": "HTML", "disable_web_page_preview": True},
    )


async def send_chat_action(chat_id, action: str = "typing") -> dict | None:
    """Show a transient status (e.g. 'typing…') while Gemini composes a reply."""
    return await _post("sendChatAction", {"chat_id": chat_id, "action": action})
