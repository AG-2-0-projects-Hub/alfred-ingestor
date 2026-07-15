"""Deferred work that must NOT run after an HTTP response has been sent.

Cloud Run bills two ways. Under the default *request-based* billing it throttles
the CPU to ~0 the moment a response goes out — so anything still running in a
FastAPI BackgroundTask freezes there and only limps forward when the next request
happens to grant CPU. That is what made Telegram replies arrive minutes late and
stacked (2026-07-13). Keeping the CPU on around the clock fixes it, but bills an
idle container 24/7 (~$55/mo) whether or not a single guest ever writes.

The fix is to make the deferred work its own HTTP request. Cloud Tasks takes a
payload now and POSTs it back to us a moment later; that callback is a fresh
request, so it gets full CPU for its whole duration and the service can stay on
cheap request-based billing (and even scale to zero).

Falls back to running the work in-process when CLOUD_TASKS_QUEUE is unset, so
staging (Render, where nothing is throttled) and local dev are unaffected.
"""
import json
import logging
import os

log = logging.getLogger(__name__)

_ALREADY_EXISTS = "ALREADY_EXISTS"


def enabled() -> bool:
    return bool(os.environ.get("CLOUD_TASKS_QUEUE"))


def enqueue(
    path: str,
    payload: dict,
    *,
    delay_seconds: int = 0,
    name: str | None = None,
) -> bool:
    """POST `payload` to `path` on this service via Cloud Tasks.

    `name` makes the task idempotent: Cloud Tasks rejects a duplicate name, which
    is how a Telegram album (delivered as one update per photo, all sharing a
    media_group_id) schedules exactly ONE flush no matter how many photos land.

    Returns True if the task was created, False if a task with that name already
    existed — the caller treats that as "someone else already scheduled it".
    """
    from google.api_core import exceptions as gexc
    from google.cloud import tasks_v2
    from google.protobuf import duration_pb2, timestamp_pb2

    project = os.environ["GOOGLE_CLOUD_PROJECT"]
    location = os.environ["CLOUD_TASKS_LOCATION"]
    queue = os.environ["CLOUD_TASKS_QUEUE"]
    base_url = os.environ["SERVICE_BASE_URL"].rstrip("/")
    secret = os.environ.get("TELEGRAM_WEBHOOK_SECRET", "")

    client = tasks_v2.CloudTasksClient()
    parent = client.queue_path(project, location, queue)

    task: dict = {
        "http_request": {
            "http_method": tasks_v2.HttpMethod.POST,
            "url": f"{base_url}{path}",
            "headers": {
                "Content-Type": "application/json",
                # Same shared secret the Telegram webhook uses. The service is
                # public (Telegram must reach it), so the worker endpoint is
                # guarded the same way rather than by IAM.
                "X-Telegram-Bot-Api-Secret-Token": secret,
            },
            "body": json.dumps(payload).encode(),
        }
    }
    if name:
        task["name"] = client.task_path(project, location, queue, name)
    if delay_seconds:
        ts = timestamp_pb2.Timestamp()
        ts.GetCurrentTime()
        ts.seconds += delay_seconds
        task["schedule_time"] = ts

    try:
        client.create_task(parent=parent, task=task)
        return True
    except gexc.AlreadyExists:
        return False


def sanitize_task_name(raw: str) -> str:
    """Cloud Tasks names allow only [A-Za-z0-9_-]."""
    return "".join(c if c.isalnum() or c in "-_" else "-" for c in str(raw))
