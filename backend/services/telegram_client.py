"""Thin async wrapper over the Telegram Bot API.

Guest channel only (MVP): send text replies and a "typing" action. Uses the
same bot as the legacy Make.com scenario — `TELEGRAM_BOT_TOKEN` from env.
httpx is already a backend dependency (see supabase_client.upload_hero_image).
"""
import logging
import os

import httpx

log = logging.getLogger(__name__)

_API = "https://api.telegram.org"


def _token() -> str:
    token = os.environ.get("TELEGRAM_BOT_TOKEN")
    if not token:
        raise RuntimeError("TELEGRAM_BOT_TOKEN is not set")
    return token


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
    """Send a text message. Markdown is enabled for light emphasis in bot copy."""
    return await _post(
        "sendMessage",
        {"chat_id": chat_id, "text": text, "parse_mode": "Markdown",
         "disable_web_page_preview": True},
    )


async def send_chat_action(chat_id, action: str = "typing") -> dict | None:
    """Show a transient status (e.g. 'typing…') while Gemini composes a reply."""
    return await _post("sendChatAction", {"chat_id": chat_id, "action": action})
