#!/usr/bin/env python3
"""WhatsApp guest channel — offline test suite.

WHY THIS EXISTS
---------------
The WhatsApp channel (routers/whatsapp.py, services/whatsapp_client.py) talks to
Meta's Graph API, so almost none of it can be exercised by hand without a live
WABA, an access token and a real phone. That is exactly the situation in which
bugs reach staging and cost a debugging cycle. Everything here runs offline:
httpx is faked, Supabase is stubbed, the Brain is spied on.

It covers the four places WhatsApp is NOT a drop-in port of Telegram, because
those are where the real risk lives:

  1. No /start payload  -> the booking code rides in an EDITABLE prefilled
     message. The regex must find every real id and must NOT match "check-out",
     which would divert ordinary guest messages off the burst-coalescing path.
  2. Meta REDELIVERS     -> the same message id must never be processed twice.
  3. No media_group_id   -> several photos are debounced by SENDER into ONE turn.
  4. The 24h window      -> outside it Meta refuses a free-form send, and the
     host must be TOLD rather than shown a false "sent".

Plus the authenticated TWO-HOP media download, whose second hop silently 401s if
the bearer token is dropped — the single easiest mistake to make in this file's
subject matter.

USAGE
-----
    python3 _tests/whatsapp_channel.py

Requires the backend's dependencies importable (fastapi, httpx, supabase, ...).
If they are not installed system-wide, point PYTHONPATH at a directory holding
them, e.g.:

    python3 -m pip install --target /tmp/wa-deps -r backend/requirements.txt
    PYTHONPATH=/tmp/wa-deps python3 _tests/whatsapp_channel.py

Exits non-zero on any failure, so it can gate a release.
"""
import asyncio
import hashlib
import hmac
import json
import os
import random
import re
import string
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "backend"))

# Set BEFORE importing the app: these are read at import time.
os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "test-key")
os.environ["WHATSAPP_APP_SECRET"] = "test-app-secret"
os.environ["WHATSAPP_VERIFY_TOKEN"] = "test-verify-token"
os.environ["WHATSAPP_ACCESS_TOKEN"] = "test-token"
os.environ["WHATSAPP_PHONE_NUMBER_ID"] = "111222333"
os.environ["WHATSAPP_NUMBER"] = "+52 155 1234 5678"
os.environ["TELEGRAM_WEBHOOK_SECRET"] = "worker-secret"
# Must stay unset: with it, dispatch enqueues to Cloud Tasks instead of running
# the in-process fallback these tests drive.
os.environ.pop("CLOUD_TASKS_QUEUE", None)

from fastapi import BackgroundTasks  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

import main  # noqa: E402  -- the import itself is the wiring test
from routers import messages as msg  # noqa: E402
from routers import whatsapp as wa  # noqa: E402
from services import supabase_client  # noqa: E402
from services import whatsapp_client as wc  # noqa: E402

FAILURES = []
WA_ID = "5215599998888"

_loop = asyncio.new_event_loop()
asyncio.set_event_loop(_loop)


def run(coro):
    return _loop.run_until_complete(coro)


def check(name, cond, detail=""):
    print(("OK   " if cond else "FAIL ") + name + ("" if cond else "  " + str(detail)))
    if not cond:
        FAILURES.append(name)


def section(title):
    print("\n── " + title + " " + "─" * max(0, 60 - len(title)))


# ─────────────────────────────────────────────────────────────────────────────
section("Wiring")

paths = {r.path for r in main.app.routes}
check("whatsapp webhook registered", "/api/whatsapp/webhook" in paths,
      sorted(p for p in paths if "whats" in p))
check("whatsapp worker registered", "/api/whatsapp/process" in paths)
check("telegram routes still registered", "/api/telegram/webhook" in paths)

client = TestClient(main.app)


# ─────────────────────────────────────────────────────────────────────────────
section("Booking code recovery (no /start payload)")

def slugify(t):
    t = t.lower().strip()
    t = re.sub(r"[^\w\s-]", "", t)
    t = re.sub(r"[\s_]+", "-", t)
    return re.sub(r"-+", "-", t)


def make_booking(name):
    """Mirror of messages._slugify + _random_suffix."""
    return slugify(name) + "-" + "".join(
        random.choices(string.ascii_lowercase + string.digits, k=6)
    )


random.seed(7)
missed = None
for prop_name in ["Casa Gate2 Test", "Paris Flat", "Bungalow Santa Fe", "Loft",
                  "A", "Villa del Mar 22", "El Nido"]:
    for _ in range(300):
        b = make_booking(prop_name)
        if b not in wa._BOOKING_RE.findall("Hola Alfred, mi reserva es " + b):
            missed = b
            break
    if missed:
        break
check("every generated booking id is recoverable", missed is None, missed)

# The regression that matters: these are phrases guests type constantly. A looser
# regex matches "check-out" and steals the message from burst coalescing.
false_positives = [p for p in [
    "what is the check-out time?", "check-in please", "the wi-fi is down",
    "self-service is fine", "air-conditioning is broken", "e-mail me",
    "is it non-smoking?", "my check-out is late", "the a-c does not work",
    "twenty-four hours",
] if wa._BOOKING_RE.findall(p)]
check("domain phrases are not mistaken for booking codes",
      not false_positives, false_positives)


# ─────────────────────────────────────────────────────────────────────────────
section("Webhook authentication")

r = client.get("/api/whatsapp/webhook", params={
    "hub.mode": "subscribe", "hub.verify_token": "test-verify-token",
    "hub.challenge": "1158201444"})
# Meta requires the bare challenge; a JSON-wrapped body fails its check.
check("verify challenge echoes plaintext",
      r.status_code == 200 and r.text == "1158201444", (r.status_code, r.text))

r = client.get("/api/whatsapp/webhook", params={
    "hub.mode": "subscribe", "hub.verify_token": "WRONG", "hub.challenge": "x"})
check("verify rejects a wrong token", r.status_code == 403, r.status_code)

body = json.dumps({"object": "whatsapp_business_account", "entry": []}).encode()
good_sig = "sha256=" + hmac.new(b"test-app-secret", body, hashlib.sha256).hexdigest()

r = client.post("/api/whatsapp/webhook", content=body,
                headers={"Content-Type": "application/json",
                         "X-Hub-Signature-256": good_sig})
check("valid signature accepted", r.status_code == 200, (r.status_code, r.text))

r = client.post("/api/whatsapp/webhook", content=body,
                headers={"Content-Type": "application/json",
                         "X-Hub-Signature-256": "sha256=deadbeef"})
check("forged signature rejected", r.status_code == 403, r.status_code)

r = client.post("/api/whatsapp/webhook", content=body,
                headers={"Content-Type": "application/json"})
check("missing signature rejected", r.status_code == 403, r.status_code)

r = client.post("/api/whatsapp/process", json={"kind": "noop"},
                headers={"X-Telegram-Bot-Api-Secret-Token": "worker-secret"})
check("worker accepts the shared secret", r.status_code == 200, r.status_code)
r = client.post("/api/whatsapp/process", json={"kind": "noop"},
                headers={"X-Telegram-Bot-Api-Secret-Token": "nope"})
check("worker rejects a wrong secret", r.status_code == 403, r.status_code)


# ─────────────────────────────────────────────────────────────────────────────
section("Inbound dispatch")

sent = []
brain_calls = []


async def fake_send(wa_id, text):
    sent.append((wa_id, text))
    return {"messages": [{"id": "wamid.out"}]}


async def fake_mark_read(wa_id, message_id, typing=True):
    return {}


async def fake_process(booking_id, text, channel="web", media=None,
                       already_stored=False):
    brain_calls.append({"booking_id": booking_id, "text": text,
                        "channel": channel, "media": media,
                        "already_stored": already_stored})
    return {"reply": "Got it", "requires_escalation": False,
            "conversation_id": "conv-1", "mode": "autopilot", "host_name": None}


wa.whatsapp_client.send_message = fake_send
wa.whatsapp_client.mark_read = fake_mark_read
wa.process_guest_message = fake_process
supabase_client.get_guest_by_whatsapp_wa_id = lambda w: None
supabase_client.get_guest_by_booking_id = lambda b: None


def text_payload(text, wamid="wamid.T1"):
    return {"object": "whatsapp_business_account", "entry": [{"id": "WABA", "changes": [{
        "field": "messages",
        "value": {"messaging_product": "whatsapp",
                  "metadata": {"phone_number_id": "111222333"},
                  "contacts": [{"wa_id": WA_ID}],
                  "messages": [{"from": WA_ID, "id": wamid, "timestamp": "1",
                                "type": "text", "text": {"body": text}}]}}]}]}


def post(payload):
    raw = json.dumps(payload).encode()
    sig = "sha256=" + hmac.new(b"test-app-secret", raw, hashlib.sha256).hexdigest()
    return client.post("/api/whatsapp/webhook", content=raw,
                       headers={"Content-Type": "application/json",
                                "X-Hub-Signature-256": sig})


# A guest who cleared the prefilled text arrives unrecognised. Silence would
# leave them staring at a chat that never answers.
sent.clear()
post(text_payload("hola quiero preguntar algo"))
check("unknown sender gets a reply, not silence", len(sent) == 1, sent)
check("unknown sender gets the NOT_LINKED copy",
      bool(sent) and "not connected to a booking" in sent[0][1].lower(), sent)

# Meta retries on any non-200 and can duplicate a delivery outright.
sent.clear()
post(text_payload("hola otra vez", wamid="wamid.T2"))
check("a fresh message id is processed", len(sent) == 1, sent)
post(text_payload("hola otra vez", wamid="wamid.T2"))
check("redelivery of the same id is suppressed", len(sent) == 1, sent)

# Delivery/read receipts for messages WE sent are not guest input.
sent.clear()
post({"object": "whatsapp_business_account", "entry": [{"id": "W", "changes": [{
    "field": "messages",
    "value": {"messaging_product": "whatsapp",
              "metadata": {"phone_number_id": "111222333"},
              "statuses": [{"id": "wamid.OUT", "status": "delivered",
                            "recipient_id": WA_ID}]}}]}]})
check("status callbacks are ignored", len(sent) == 0, sent)


# ─────────────────────────────────────────────────────────────────────────────
section("Media download (two hops, both authenticated)")

class FakeResponse:
    def __init__(self, status_code=200, json_data=None, content=b""):
        self.status_code = status_code
        self._json = json_data if json_data is not None else {}
        self.content = content

    def json(self):
        return self._json


class FakeAsyncClient:
    calls = []
    responses = {}

    def __init__(self, timeout=None):
        pass

    async def __aenter__(self):
        return self

    async def __aexit__(self, *a):
        return False

    async def get(self, url, headers=None):
        FakeAsyncClient.calls.append(("GET", url, dict(headers or {})))
        return FakeAsyncClient.responses.get(url, FakeResponse(404))

    async def post(self, url, json=None, headers=None):
        FakeAsyncClient.calls.append(("POST", url, dict(headers or {})))
        return FakeAsyncClient.responses.get(
            url, FakeResponse(200, {"messages": [{"id": "wamid.x"}]}))


wc.httpx.AsyncClient = FakeAsyncClient
GRAPH = "https://graph.facebook.com/v25.0"
CDN = "https://lookaside.fbsbx.com/whatsapp/MEDIA123"


def reset_http(**responses):
    FakeAsyncClient.calls = []
    FakeAsyncClient.responses = dict(responses)


reset_http(**{f"{GRAPH}/MEDIA123": FakeResponse(200, {"url": CDN}),
              CDN: FakeResponse(200, content=b"\xff\xd8\xff-jpeg")})
check("download_media returns the bytes",
      run(wc.download_media("MEDIA123")) == b"\xff\xd8\xff-jpeg")
check("download_media makes exactly 2 requests", len(FakeAsyncClient.calls) == 2,
      FakeAsyncClient.calls)
# The CDN hop is a different host and STILL needs the token; dropping it there
# returns 401 rather than bytes, and the guest silently gets an error reply.
check("both hops carry the bearer token",
      all(c[2].get("Authorization") == "Bearer test-token"
          for c in FakeAsyncClient.calls), FakeAsyncClient.calls)
check("second hop targets the CDN url", FakeAsyncClient.calls[1][1] == CDN)

reset_http(**{f"{GRAPH}/MEDIA123": FakeResponse(404)})
check("lookup 404 -> None", run(wc.download_media("MEDIA123")) is None)
reset_http(**{f"{GRAPH}/MEDIA123": FakeResponse(200, {})})
check("missing url -> None", run(wc.download_media("MEDIA123")) is None)
reset_http(**{f"{GRAPH}/MEDIA123": FakeResponse(200, {"url": CDN}),
              CDN: FakeResponse(401)})
check("CDN 401 -> None", run(wc.download_media("MEDIA123")) is None)


# ─────────────────────────────────────────────────────────────────────────────
section("Media becomes ONE turn (no media_group_id)")

async def fake_download(media_id):
    return b"bytes-for-" + media_id.encode()


wa.whatsapp_client.download_media = fake_download
supabase_client.get_guest_by_whatsapp_wa_id = lambda w: {
    "id": "g1", "booking_id": "casa-test-ab12cd", "property_id": "p1",
    "preferred_language": "es", "whatsapp_wa_id": w,
}
supabase_client.touch_guest_inbound = lambda c: None
wa._notify_channel_transition = lambda *a, **k: asyncio.sleep(0)


def image_msg(media_id, caption=None):
    node = {"id": media_id, "mime_type": "image/jpeg"}
    if caption:
        node["caption"] = caption
    return {"type": "image", "image": node}


wa._media_groups.clear()
brain_calls.clear()
sent.clear()
bt = BackgroundTasks()
run(wa._dispatch_media(WA_ID, "image", image_msg("M1"), bt))
run(wa._dispatch_media(WA_ID, "image", image_msg("M2", caption="mira esto"), bt))
run(wa._dispatch_media(WA_ID, "image", image_msg("M3"), bt))
check("3 photos collected into one group",
      len(wa._media_groups[WA_ID]["items"]) == 3, wa._media_groups)
check("only the first photo schedules a flush", len(bt.tasks) == 1, len(bt.tasks))

run(wa._flush_media(WA_ID, [], ""))
check("an album produces exactly ONE Brain call", len(brain_calls) == 1, brain_calls)
check("all 3 photos reach the Brain",
      bool(brain_calls) and len(brain_calls[0]["media"]) == 3, brain_calls)
check("a caption on any photo is carried",
      bool(brain_calls) and brain_calls[0]["text"] == "mira esto", brain_calls)
check("channel is whatsapp",
      bool(brain_calls) and brain_calls[0]["channel"] == "whatsapp")
check("exactly one reply is sent", len(sent) == 1, sent)
check("the group is cleared after flushing", WA_ID not in wa._media_groups)

wa._media_groups.clear()
brain_calls.clear()
run(wa._dispatch_media(WA_ID, "audio",
                       {"type": "audio",
                        "audio": {"id": "V1", "voice": True,
                                  "mime_type": "audio/ogg; codecs=opus"}},
                       BackgroundTasks()))
run(wa._flush_media(WA_ID, [], ""))
check("a voice note reaches the Brain", len(brain_calls) == 1, brain_calls)
if brain_calls:
    item = brain_calls[0]["media"][0]
    # Gemini rejects a mime carrying codec parameters.
    check("voice mime is stripped of codec params", item["mime"] == "audio/ogg", item)
    check("voice is classified as audio", item["kind"] == "audio", item)

wa._media_groups.clear()
brain_calls.clear()
sent.clear()
run(wa._dispatch_media(WA_ID, "document", {"type": "document",
                                           "document": {"id": "D1"}},
                       BackgroundTasks()))
check("an unsupported attachment is declined aloud", len(sent) == 1, sent)
check("an unsupported attachment never reaches the Brain",
      len(brain_calls) == 0, brain_calls)


async def failing_download(media_id):
    return None


wa.whatsapp_client.download_media = failing_download
brain_calls.clear()
sent.clear()
run(wa._handle_guest_media(WA_ID, [["M9", "image", "image/jpeg"]], ""))
check("a failed download does not call the Brain empty-handed",
      len(brain_calls) == 0, brain_calls)
check("a failed download still tells the guest something", len(sent) == 1, sent)


async def flaky_download(media_id):
    return None if media_id == "BAD" else b"ok-bytes"


wa.whatsapp_client.download_media = flaky_download
brain_calls.clear()
run(wa._handle_guest_media(
    WA_ID, [["BAD", "image", "image/jpeg"], ["GOOD", "image", "image/jpeg"]], ""))
check("a partial download still answers", len(brain_calls) == 1, brain_calls)
check("only successfully downloaded items are attached",
      bool(brain_calls) and len(brain_calls[0]["media"]) == 1, brain_calls)


# ─────────────────────────────────────────────────────────────────────────────
section("The 24-hour service window (host_send)")

wa_sent = []


async def spy_send(wa_id, text):
    wa_sent.append((wa_id, text))
    return {"messages": [{"id": "wamid.ok"}]}


msg.whatsapp_client.send_message = spy_send


def with_inbound(delta):
    stamp = (datetime.now(timezone.utc) - delta).isoformat()
    msg.supabase_client.get_last_guest_inbound_at = lambda c: stamp


wa_sent.clear()
with_inbound(timedelta(hours=1))
res = run(msg._deliver_host_whatsapp("conv-1", WA_ID, "hola"))
check("inside the window -> delivered", res is None and len(wa_sent) == 1,
      (res, wa_sent))

wa_sent.clear()
with_inbound(timedelta(hours=30))
res = run(msg._deliver_host_whatsapp("conv-1", WA_ID, "hola"))
check("outside the window -> not sent", len(wa_sent) == 0, wa_sent)
# The whole point: the host must not believe they answered someone they did not.
check("outside the window -> the host is told why",
      res is not None and "24-hour" in res, res)

wa_sent.clear()
with_inbound(timedelta(hours=23, minutes=50))
res = run(msg._deliver_host_whatsapp("conv-1", WA_ID, "hola"))
check("just inside the boundary -> delivered", res is None and len(wa_sent) == 1,
      (res, wa_sent))

wa_sent.clear()
msg.supabase_client.get_last_guest_inbound_at = lambda c: None
run(msg._deliver_host_whatsapp("conv-1", WA_ID, "hola"))
check("no timestamp -> attempt the send, let Meta decide", len(wa_sent) == 1)

wa_sent.clear()
msg.supabase_client.get_last_guest_inbound_at = lambda c: "not-a-date"
run(msg._deliver_host_whatsapp("conv-1", WA_ID, "hola"))
check("an unparseable timestamp does not block a good send", len(wa_sent) == 1)


async def refusing_send(wa_id, text):
    return {"error": {"code": 131047, "message": "outside window"}}


msg.whatsapp_client.send_message = refusing_send
msg.supabase_client.get_last_guest_inbound_at = lambda c: None
res = run(msg._deliver_host_whatsapp("conv-1", WA_ID, "hola"))
check("Meta 131047 -> reported to the host",
      res is not None and "24-hour" in res, res)


async def undeliverable_send(wa_id, text):
    return {"error": {"code": 131026, "message": "undeliverable"}}


msg.whatsapp_client.send_message = undeliverable_send
res = run(msg._deliver_host_whatsapp("conv-1", WA_ID, "hola"))
check("any other Meta error -> reported as undelivered",
      res is not None and "did not accept" in res.lower(), res)


# ─────────────────────────────────────────────────────────────────────────────
section("Guest deep link")

number = re.sub(r"\D", "", os.environ["WHATSAPP_NUMBER"])
check("E.164 normalised for wa.me", number == "5215512345678", number)
check("booking code survives the deep-link round trip",
      "casa-test-ab12cd" in wa._BOOKING_RE.findall(
          "Hola Alfred, mi reserva es casa-test-ab12cd"))

print()
if FAILURES:
    print(str(len(FAILURES)) + " FAILURES: " + str(FAILURES))
    sys.exit(1)
print("ALL PASS")
