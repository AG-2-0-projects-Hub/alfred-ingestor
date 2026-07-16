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


async def generate_with_retry(client: genai.Client, *, label: str = "gemini", **kwargs):
    """`client.aio.models.generate_content(**kwargs)`, retrying only on 429.

    Anything that is not a rate limit propagates immediately — we never want to
    paper over a real error by retrying it.

    Emits one WARNING per rate-limited attempt (naming the caller via `label` and
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
        try:
            response = await client.aio.models.generate_content(**kwargs)
            if attempt:
                log.info(
                    "%s: succeeded on attempt %d/%d after %.1fs total",
                    label, attempt + 1, _RETRY_ATTEMPTS, time.monotonic() - started,
                )
            return response
        except Exception as exc:
            if not is_rate_limited(exc):
                raise
            if attempt == _RETRY_ATTEMPTS - 1:
                log.warning(
                    "%s: rate-limited on final attempt %d/%d, giving up after %.1fs: %s",
                    label, attempt + 1, _RETRY_ATTEMPTS, time.monotonic() - started,
                    str(exc)[:200],
                )
                raise
            backoff = 0.5 * (2 ** attempt) * random.uniform(0.85, 1.15)  # ~0.5s, 1s, 2s
            log.warning(
                "%s: rate-limited (429) on attempt %d/%d after %.1fs; backing off %.1fs",
                label, attempt + 1, _RETRY_ATTEMPTS, time.monotonic() - started, backoff,
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
