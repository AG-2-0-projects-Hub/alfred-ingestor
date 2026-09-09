"""The single place that decides how we reach Gemini.

Two transports, one SDK:

* **Vertex AI** (prod) — authenticates with the Cloud Run service account via ADC,
  so no API key exists anywhere, and usage bills through the project's Cloud
  Billing account, which means Google Cloud credits apply to it.
* **AI Studio / Gemini Developer API** (staging, local) — a plain `GEMINI_API_KEY`.
  It is billed on its own prepay plan that Cloud credits do *not* cover.

Set `GOOGLE_GENAI_USE_VERTEXAI=true` (with `GOOGLE_CLOUD_PROJECT`) to pick Vertex.
Model ids are identical across both, so callers don't care which is active.
"""
import asyncio
import logging
import os
import random
import time

from google import genai

log = logging.getLogger(__name__)

_TRUE = {"1", "true", "yes", "on"}

# Vertex serves Gemini from a *dynamic shared* quota rather than a fixed
# per-project one, so any burst — a multi-file ingest, or simply two guests
# typing at once — can transiently 429. Every Gemini call in the app goes
# through generate_with_retry() so no path is left unprotected.
_RETRY_ATTEMPTS = 4


def use_vertex() -> bool:
    return os.getenv("GOOGLE_GENAI_USE_VERTEXAI", "").strip().lower() in _TRUE


def is_rate_limited(exc: Exception) -> bool:
    text = str(exc)
    return "429" in text or "RESOURCE_EXHAUSTED" in text


async def generate_with_retry(
    client: genai.Client, *, label: str = "gemini", call_timeout: float | None = None, **kwargs
):
    """`client.aio.models.generate_content(**kwargs)`, retrying on 429 and,
    when `call_timeout` is given, on a stalled call too.

    Anything that is not a rate limit or a `call_timeout` stall propagates
    immediately — we never want to paper over a real error by retrying it.

    `call_timeout` defaults to None (no per-call ceiling — unchanged legacy
    behavior) so existing callers (chat, merge, knowledge query) are unaffected.
    It exists because a single Gemini call has no timeout of its own: a plain
    stall (no exception, no 429, just no response) used to hang until whatever
    *outer* caller's own watchdog gave up, with zero retry ever attempted —
    confirmed live 2026-09-09 on two host-uploaded photos. Pass it from a
    caller that has its own outer deadline to retry into, not just wait it out.

    Emits one WARNING per retried attempt (naming the caller via `label` and
    the back-off it is about to wait) plus an INFO whenever a call only lands
    after retrying. Without this the retry loop was silent, so a request that
    trips the 45s chat ceiling gave no way to tell genuine grounded-search
    latency apart from time lost to 429 back-off. `label` lets us see which
    pass — first_pass vs the grounded second_pass — actually stalled.

    Back-off is short and jittered (~0.5s, 1s, 2s ±15%). A transient Vertex 429
    clears near-instantly, so the old 2/4/8s waits mostly added dead air and were
    the main way a cold-start burst of 429s stacked past the 45s chat ceiling;
    the jitter keeps concurrent guests from retrying in lockstep.
    """
    started = time.monotonic()
    for attempt in range(_RETRY_ATTEMPTS):
        call = client.aio.models.generate_content(**kwargs)
        stalled = False
        try:
            response = await (asyncio.wait_for(call, timeout=call_timeout) if call_timeout else call)
            if attempt:
                log.info(
                    "%s: succeeded on attempt %d/%d after %.1fs total",
                    label, attempt + 1, _RETRY_ATTEMPTS, time.monotonic() - started,
                )
            return response
        except asyncio.TimeoutError as exc:
            stalled = True
            reason = f"no response within {call_timeout:.0f}s"
            last_exc = exc
        except Exception as exc:
            if not is_rate_limited(exc):
                raise
            reason = f"rate-limited (429): {str(exc)[:200]}"
            last_exc = exc

        if attempt == _RETRY_ATTEMPTS - 1:
            log.warning(
                "%s: giving up on final attempt %d/%d after %.1fs — %s",
                label, attempt + 1, _RETRY_ATTEMPTS, time.monotonic() - started, reason,
            )
            if stalled:
                raise TimeoutError(f"No response after {_RETRY_ATTEMPTS} attempts — try again")
            raise last_exc
        backoff = 0.5 * (2 ** attempt) * random.uniform(0.85, 1.15)  # ~0.5s, 1s, 2s
        log.warning(
            "%s: retrying (attempt %d/%d) after %.1fs — %s; backing off %.1fs",
            label, attempt + 1, _RETRY_ATTEMPTS, time.monotonic() - started, reason, backoff,
        )
        await asyncio.sleep(backoff)


def make_client() -> genai.Client:
    if use_vertex():
        return genai.Client(
            vertexai=True,
            project=os.environ["GOOGLE_CLOUD_PROJECT"],
            # "global" routes to whichever region has capacity. Override with
            # GOOGLE_CLOUD_LOCATION (e.g. an EU region) if data residency is
            # required — see the open GDPR decision (D4).
            location=os.getenv("GOOGLE_CLOUD_LOCATION", "global"),
        )
    return genai.Client(api_key=os.environ["GEMINI_API_KEY"])
