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


async def send_alert(chat_id, text: str, buttons: list[tuple[str, str]]) -> int | None:
    """Send a host escalation alert with inline buttons (label, callback_data).
    HTML parse mode — callers must escape any guest/AI-generated text themselves
    (see routers/messages._build_host_alert_text). Returns the sent message's
    message_id so the caller can store it on conversations.host_alert_message_id
    for reply-to routing, or None on failure (best-effort, never raises)."""
    keyboard = {
        "inline_keyboard": [[{"text": label, "callback_data": data}]
                             for label, data in buttons]
    }
    result = await _post("sendMessage", {
        "chat_id": chat_id, "text": text, "parse_mode": "HTML",
        "disable_web_page_preview": True, "reply_markup": keyboard,
    })
    if not result or not result.get("ok"):
        return None
    return (result.get("result") or {}).get("message_id")


async def answer_callback_query(callback_query_id: str, text: str | None = None) -> None:
    """Dismiss Telegram's loading spinner on an inline button press, optionally
    with a small toast. Must be called even on failure paths — otherwise the
    button stays in a spinning state client-side until Telegram times it out."""
    payload: dict = {"callback_query_id": callback_query_id}
    if text:
        payload["text"] = text
    await _post("answerCallbackQuery", payload)


async def edit_message(chat_id, message_id: int, text: str) -> None:
    """Rewrite an already-sent message's text AND remove its inline keyboard.
    Every current caller edits a message specifically to retire its buttons
    after they've been acted on (resolved, or a picker choice made) — Telegram
    keeps the original keyboard attached unless a reply_markup is explicitly
    supplied on the edit, so this always clears it."""
    await _post("editMessageText", {
        "chat_id": chat_id, "message_id": message_id, "text": text,
        "reply_markup": {"inline_keyboard": []},
    })


async def download_file(file_id: str) -> bytes | None:
    """Fetch a Telegram file's raw bytes by file_id (two steps: getFile resolves
    the file_path, then the file endpoint serves the bytes). Returns None on any
    failure — the caller falls back to the text-only "please type" reply."""
    try:
        info = await _post("getFile", {"file_id": file_id})
        if not info or not info.get("ok"):
            return None
        file_path = (info.get("result") or {}).get("file_path")
        if not file_path:
            return None
        url = f"{_API}/file/bot{_token()}/{file_path}"
        async with httpx.AsyncClient(timeout=30) as client:
            resp = await client.get(url)
        if resp.status_code != 200:
            log.warning("telegram download_file: HTTP %s for %s", resp.status_code, file_path)
            return None
        return resp.content
    except Exception as exc:
        log.warning("telegram download_file error: %s", exc)
        return None
