"""Waitlist for the Mayordommo landing, with double opt-in.

Same pattern as the host escalation-email confirmation in routers/messages.py
(one-time token stored only as a hash, GET page that changes nothing so link
scanners cannot confirm for the owner, atomic POST, unsubscribe link, QA
addresses that get the links back instead of an email), in Spanish.

The landing page is a static site on another origin, so it calls POST /waitlist
as a plain "simple" request (text body, no custom headers: no CORS preflight)
and these endpoints answer with Access-Control-Allow-Origin: * and no cookies.
That leaves the host app's credentialed CORS list (main.py) untouched.

Table and columns: migrations/2026-10-05_waitlist_signups.sql and
2026-10-05_waitlist_double_opt_in.sql. confirmed_at is the proof of consent.
"""
import asyncio
import hashlib
import logging
import os
import re
import secrets
from datetime import datetime, timedelta, timezone
from urllib.parse import quote

from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse, JSONResponse

from services import email_client, supabase_client

log = logging.getLogger(__name__)
router = APIRouter()

_EMAIL_RE = re.compile(r"^[^\s@]+@[^\s@]+\.[^\s@]{2,}$")
_HOMES = {"1", "2-5", "6+"}
_CONFIRM_TTL = timedelta(days=7)
_RESEND_COOLDOWN = timedelta(minutes=10)   # per address, before a new link is mailed
_MAX_NEW_PER_MINUTE = 30                   # new signups, whole list
# The SendGrid free plan (100/day) is shared with the host escalation alerts: a
# flood of fake signups must never use it all up.
_MAX_EMAILS_PER_DAY = 40
# RFC 2606 reserved TLD: can never receive mail, so the links are handed back in
# the response instead (lets QA play the mailbox owner). Harmless anywhere.
_TEST_ONLY_ADDRESS_SUFFIX = "@example.invalid"
_CORS = {"Access-Control-Allow-Origin": "*"}


def _hash_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def _escape_html(text: str) -> str:
    return (text or "").replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;")


def _json(body: dict, status: int = 200) -> JSONResponse:
    return JSONResponse(body, status_code=status, headers=_CORS)


def _parse_ts(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def _page(body_html: str, status_code: int = 200) -> HTMLResponse:
    return HTMLResponse(
        '<!doctype html><html lang="es"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width,initial-scale=1">'
        '<meta name="robots" content="noindex"><title>Mayordommo</title></head>'
        '<body style="margin:0;background:#F4ECE0;color:#1B102C;font-family:Arial,Helvetica,sans-serif">'
        '<div style="max-width:480px;margin:56px auto;padding:0 20px;line-height:1.55">'
        '<p style="font-size:13px;letter-spacing:.08em;text-transform:uppercase;color:#5E4D75;margin:0 0 16px">Mayordommo</p>'
        f"{body_html}</div></body></html>",
        status_code=status_code,
    )


def _button(label: str) -> str:
    return (
        '<button type="submit" style="font-size:16px;font-weight:700;padding:12px 24px;border:0;'
        f'border-radius:999px;background:#6235AF;color:#fff;cursor:pointer">{label}</button>'
    )


_INVALID_LINK = (
    "<h1 style=\"font:400 24px/1.25 Georgia,serif;margin:0 0 12px\">Este enlace ya no es válido</h1>"
    "<p>Venció o ya se usó. Si ya confirmaste tu lugar, no tienes que hacer nada.</p>"
)


def _confirmation_email_html(email: str, confirm_url: str, unsub_url: str) -> str:
    return (
        '<div style="background:#F4ECE0;padding:32px 16px;font-family:Arial,Helvetica,sans-serif;color:#1B102C">'
        '<div style="max-width:480px;margin:0 auto;background:#FCF8F1;border-radius:16px;padding:28px">'
        '<p style="font-size:13px;letter-spacing:.08em;text-transform:uppercase;color:#5E4D75;margin:0 0 12px">Mayordommo</p>'
        '<h1 style="font:400 24px/1.25 Georgia,serif;margin:0 0 12px">Confirma tu lugar</h1>'
        '<p style="line-height:1.55;margin:0 0 20px">Alguien pidió un lugar en la lista de Mayordommo con '
        f"<b>{_escape_html(email)}</b>. Si fuiste tú, confírmalo para guardarlo. El enlace funciona 7 días.</p>"
        f'<p style="margin:0 0 24px"><a href="{_escape_html(confirm_url)}" style="display:inline-block;background:#6235AF;'
        'color:#ffffff;text-decoration:none;font-weight:700;padding:12px 24px;border-radius:999px">Confirmar mi lugar</a></p>'
        '<p style="font-size:13px;line-height:1.5;color:#5E4D75;margin:0">Si no fuiste tú, ignora este correo: no te escribiremos más. '
        f'<a href="{_escape_html(unsub_url)}" style="color:#5E4D75">No quiero estar en la lista</a>.</p>'
        "</div></div>"
    )


@router.post("/waitlist")
async def join_waitlist(request: Request):
    """Public. Body is JSON (sent as text/plain, see module docstring):
    {email, homes?, source?, consent_text?}. The answer for a new, a repeated
    and an already-confirmed address is the same {"status": "ok"} so the form
    never reveals who is on the list."""
    try:
        data = await request.json()
    except Exception:
        return _json({"status": "error", "detail": "bad_request"}, 400)
    if not isinstance(data, dict):
        return _json({"status": "error", "detail": "bad_request"}, 400)

    email = str(data.get("email") or "").strip().lower()
    if len(email) > 254 or not _EMAIL_RE.match(email):
        return _json({"status": "error", "detail": "invalid_email"}, 400)
    homes_raw = data.get("homes")
    homes = str(homes_raw).strip() if homes_raw not in (None, "") else None
    if homes is not None and homes not in _HOMES:
        return _json({"status": "error", "detail": "invalid_homes"}, 400)
    source = (str(data.get("source") or "")[:60]) or None
    consent_text = (str(data.get("consent_text") or "")[:400]) or None

    now = datetime.now(timezone.utc)
    existing = await asyncio.to_thread(supabase_client.waitlist_get, email)
    unsubscribed = bool(existing and existing.get("unsubscribed_at"))

    # Already confirmed and still subscribed: nothing to send. homes may be filled in.
    if existing and existing.get("confirmed_at") and not unsubscribed:
        if homes and not existing.get("homes"):
            await asyncio.to_thread(supabase_client.waitlist_update, email, {"homes": homes})
        return _json({"status": "ok"})

    # Pending with a live link that was mailed recently: do not mail again.
    if existing and not unsubscribed and existing.get("confirm_hash"):
        sent_at = _parse_ts(existing.get("confirm_sent_at"))
        if sent_at and now - sent_at < _RESEND_COOLDOWN:
            if homes and not existing.get("homes"):
                await asyncio.to_thread(supabase_client.waitlist_update, email, {"homes": homes})
            return _json({"status": "ok"})

    # Whole-list guards (new signups per minute, confirmation emails per day).
    if existing is None:
        recent = await asyncio.to_thread(
            supabase_client.waitlist_count_since, "created_at", (now - timedelta(minutes=1)).isoformat(),
        )
        if recent >= _MAX_NEW_PER_MINUTE:
            return _json({"status": "busy"}, 429)
    sent_today = await asyncio.to_thread(
        supabase_client.waitlist_count_since, "confirm_sent_at", (now - timedelta(hours=24)).isoformat(),
    )
    if sent_today >= _MAX_EMAILS_PER_DAY:
        return _json({"status": "busy"}, 429)

    token = secrets.token_urlsafe(32)
    pending = {
        "confirm_hash": _hash_token(token),
        "confirm_expires_at": (now + _CONFIRM_TTL).isoformat(),
        "confirm_sent_at": now.isoformat(),
    }
    if existing is None:
        unsub_token = secrets.token_urlsafe(24)
        await asyncio.to_thread(supabase_client.waitlist_insert, {
            "email": email, "homes": homes, "source": source, "consent_text": consent_text,
            "unsub_token": unsub_token, **pending,
        })
    else:
        unsub_token = existing.get("unsub_token") or secrets.token_urlsafe(24)
        fields = {**pending, "unsub_token": unsub_token}
        if homes and not existing.get("homes"):
            fields["homes"] = homes
        if unsubscribed:
            # they left and now ask again: that is a new consent, to be confirmed again
            fields.update({"unsubscribed_at": None, "confirmed_at": None,
                           "source": source, "consent_text": consent_text})
        await asyncio.to_thread(supabase_client.waitlist_update, email, fields)

    backend_url = os.environ.get("BACKEND_URL", "").strip().rstrip("/")
    confirm_url = f"{backend_url}/api/waitlist/confirm?token={quote(token)}"
    unsub_url = f"{backend_url}/api/waitlist/unsubscribe?token={quote(unsub_token)}"
    if email.endswith(_TEST_ONLY_ADDRESS_SUFFIX):
        return _json({"status": "ok", "confirm_url": confirm_url, "unsubscribe_url": unsub_url})

    sent = await email_client.send_email(
        email, "Confirma tu lugar en Mayordommo",
        _confirmation_email_html(email, confirm_url, unsub_url), from_name="Mayordommo",
    )
    if not sent:
        # Nothing was mailed: drop the pending link (and its cooldown stamp) so a retry mails again.
        await asyncio.to_thread(supabase_client.waitlist_update, email, {
            "confirm_hash": None, "confirm_expires_at": None, "confirm_sent_at": None,
        })
        return _json({"status": "error", "detail": "email_failed"}, 502)
    return _json({"status": "ok"})


@router.get("/waitlist/confirm", response_class=HTMLResponse)
async def confirm_page(token: str):
    """Public, the token is the authorization. Shows a button and changes
    NOTHING: mail scanners that prefetch links must not confirm for the owner."""
    email = await asyncio.to_thread(supabase_client.waitlist_pending_email, _hash_token(token))
    if not email:
        return _page(_INVALID_LINK, 400)
    return _page(
        '<h1 style="font:400 24px/1.25 Georgia,serif;margin:0 0 12px">¿Guardamos tu lugar?</h1>'
        f"<p>Te avisaremos en <b>{_escape_html(email)}</b> cuando Mayordommo esté listo para tu casa.</p>"
        f'<form method="post" action="?token={quote(token)}">{_button("Sí, guarda mi lugar")}</form>'
    )


@router.post("/waitlist/confirm", response_class=HTMLResponse)
async def confirm_submit(token: str):
    """Public, the token is the authorization. One atomic UPDATE: valid and
    unexpired -> confirmed; otherwise nothing changes. A second press finds the
    token already spent."""
    email = await asyncio.to_thread(supabase_client.waitlist_confirm, _hash_token(token))
    if not email:
        return _page(_INVALID_LINK, 400)
    return _page(
        '<h1 style="font:400 24px/1.25 Georgia,serif;margin:0 0 12px">Listo, tu lugar está guardado</h1>'
        f"<p>Te escribiremos a <b>{_escape_html(email)}</b> cuando haya un lugar para ti.</p>"
    )


@router.get("/waitlist/unsubscribe", response_class=HTMLResponse)
async def unsubscribe_page(token: str):
    """Public. A button, nothing changes yet (same reason as confirm)."""
    email = await asyncio.to_thread(supabase_client.waitlist_email_by_unsub_token, token)
    if not email:
        return _page(_INVALID_LINK, 400)
    return _page(
        '<h1 style="font:400 24px/1.25 Georgia,serif;margin:0 0 12px">¿Quitar tu correo de la lista?</h1>'
        f"<p>Dejaremos de escribir a <b>{_escape_html(email)}</b>.</p>"
        f'<form method="post" action="?token={quote(token)}">{_button("Sí, quítame de la lista")}</form>'
    )


@router.post("/waitlist/unsubscribe", response_class=HTMLResponse)
async def unsubscribe_submit(token: str):
    """Public. Marks the row unsubscribed (kept, so we never e-mail it again)."""
    email = await asyncio.to_thread(supabase_client.waitlist_unsubscribe, token)
    if not email:
        return _page(_INVALID_LINK, 400)
    return _page(
        '<h1 style="font:400 24px/1.25 Georgia,serif;margin:0 0 12px">Listo, no te escribiremos más</h1>'
        f"<p>Quitamos <b>{_escape_html(email)}</b> de la lista.</p>"
    )
