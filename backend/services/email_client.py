"""Thin async wrapper over the Resend HTTP API.

Same shape as telegram_client.py: best-effort, never raises — a send failure
is logged and swallowed so it can never break a guest-facing flow. httpx is
already a backend dependency (see telegram_client.py, supabase_client.py).
"""
import logging
import os

import httpx

log = logging.getLogger(__name__)

_API = "https://api.resend.com/emails"


def _token() -> str:
    token = os.environ.get("RESEND_API_KEY")
    if not token:
        raise RuntimeError("RESEND_API_KEY is not set")
    return token


def _from_address() -> str:
    sender = os.environ.get("EMAIL_FROM")
    if not sender:
        raise RuntimeError("EMAIL_FROM is not set")
    return sender


async def send_email(to: str, subject: str, html: str) -> bool:
    """Send one HTML email. Returns True on success, False on any failure
    (missing config, network error, non-2xx) — never raises."""
    try:
        async with httpx.AsyncClient(timeout=15) as client:
            resp = await client.post(
                _API,
                headers={"Authorization": f"Bearer {_token()}"},
                json={
                    "from": _from_address(),
                    "to": [to],
                    "subject": subject,
                    "html": html,
                },
            )
        if resp.status_code >= 300:
            log.warning("resend send_email failed: %s %s", resp.status_code, resp.text)
            return False
        return True
    except Exception as exc:  # missing config, network/transport — never bubble up
        log.warning("resend send_email error: %s", exc)
        return False
