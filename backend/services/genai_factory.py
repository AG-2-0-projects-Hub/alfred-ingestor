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
import os

from google import genai

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


async def generate_with_retry(client: genai.Client, **kwargs):
    """`client.aio.models.generate_content(**kwargs)`, retrying only on 429.

    Anything that is not a rate limit propagates immediately — we never want to
    paper over a real error by retrying it.
    """
    for attempt in range(_RETRY_ATTEMPTS):
        try:
            return await client.aio.models.generate_content(**kwargs)
        except Exception as exc:
            if not is_rate_limited(exc) or attempt == _RETRY_ATTEMPTS - 1:
                raise
            await asyncio.sleep(2 * (2 ** attempt))  # 2s, 4s, 8s


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
