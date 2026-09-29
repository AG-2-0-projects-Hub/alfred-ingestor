"""Thin wrapper over Gmail SMTP.

Same shape as telegram_client.py: best-effort, never raises — a send failure
is logged and swallowed so it can never break a guest-facing flow. smtplib is
stdlib (no new dependency). Beta-scoped choice: no owned domain exists yet to
verify with a transactional provider (Resend/etc. can't send "from" a domain
you don't control DNS for, and *.vercel.app's DNS belongs to Vercel, not this
project) -- Gmail can send as itself for real, no vendor account needed.
Revisit with a proper transactional provider once a domain exists.
"""
import asyncio
import logging
import os
import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

log = logging.getLogger(__name__)

_HOST = "smtp.gmail.com"
_PORT = 587


def _user() -> str:
    user = os.environ.get("GMAIL_SMTP_USER")
    if not user:
        raise RuntimeError("GMAIL_SMTP_USER is not set")
    return user


def _app_password() -> str:
    password = os.environ.get("GMAIL_SMTP_APP_PASSWORD")
    if not password:
        raise RuntimeError("GMAIL_SMTP_APP_PASSWORD is not set")
    return password


def _send_sync(to: str, subject: str, html: str) -> None:
    user = _user()
    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"] = user
    msg["To"] = to
    msg.attach(MIMEText(html, "html"))

    with smtplib.SMTP(_HOST, _PORT, timeout=15) as server:
        server.starttls()
        server.login(user, _app_password())
        server.sendmail(user, [to], msg.as_string())


async def send_email(to: str, subject: str, html: str) -> bool:
    """Send one HTML email. Returns True on success, False on any failure
    (missing config, network/auth error) — never raises. smtplib is blocking,
    so the actual send runs in a thread (same pattern as every Supabase call
    in this codebase) rather than blocking the event loop."""
    try:
        await asyncio.to_thread(_send_sync, to, subject, html)
        return True
    except Exception as exc:  # missing config, network/auth — never bubble up
        log.warning("gmail smtp send_email error: %s", exc)
        return False
