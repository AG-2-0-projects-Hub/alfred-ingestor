"""Thin async wrapper over the SendGrid v3 Mail Send API.

Same shape as telegram_client.py: best-effort, never raises — a send failure
is logged and swallowed so it can never break a guest-facing flow. httpx is
already a backend dependency (see telegram_client.py, supabase_client.py).

Beta note: no domain is owned/verified yet, so EMAIL_FROM is a Single Sender
Verification address (alfred.bnb.host@gmail.com) rather than a verified
domain — SendGrid lets a verified single address send to any recipient,
unlike Resend's sandbox sender which only delivers to its own account email.
Swapping EMAIL_FROM to a domain address once one exists needs no code change.
(Resend's sandbox sender and, before that, Gmail SMTP were both tried and
dropped — Resend couldn't reach real testers without a domain; Cloud Run's
network path to Gmail's SMTP was unreliable, unrelated to credentials; see
git history 2026-09-29/30.)
"""
import logging
import os

import httpx

log = logging.getLogger(__name__)

_API = "https://api.sendgrid.com/v3/mail/send"


def _token() -> str:
    token = os.environ.get("SENDGRID_API_KEY")
    if not token:
        raise RuntimeError("SENDGRID_API_KEY is not set")
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
                    "personalizations": [{"to": [{"email": to}]}],
                    "from": {"email": _from_address()},
                    "subject": subject,
                    "content": [{"type": "text/html", "value": html}],
                },
            )
        if resp.status_code >= 300:
            log.warning("sendgrid send_email failed: %s %s", resp.status_code, resp.text)
            return False
        return True
    except Exception as exc:  # missing config, network/transport — never bubble up
        log.warning("sendgrid send_email error: %s", exc)
        return False
