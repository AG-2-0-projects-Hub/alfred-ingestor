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
import os

from google import genai

_TRUE = {"1", "true", "yes", "on"}


def use_vertex() -> bool:
    return os.getenv("GOOGLE_GENAI_USE_VERTEXAI", "").strip().lower() in _TRUE


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
