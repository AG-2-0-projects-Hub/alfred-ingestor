import asyncio
import json
import os
import random
import re
import time

import httpx
import sentry_sdk
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from firecrawl import FirecrawlApp
from google import genai

# Crash/error visibility. Empty SENTRY_DSN means Sentry is off -- local dev
# doesn't send events by default. ENVIRONMENT distinguishes staging/production
# events since those run as separate Cloud Run services, not a runtime flag.
_sentry_dsn = os.environ.get("SENTRY_DSN", "")
if _sentry_dsn:
    sentry_sdk.init(dsn=_sentry_dsn, environment=os.environ.get("ENVIRONMENT", "local"))

app = FastAPI(title="Alfred Airbnb Scraper")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["POST", "GET"],
    allow_headers=["*"],
)


def get_firecrawl_client():
    key = os.environ.get("FIRECRAWL_API_KEY")
    if not key:
        raise HTTPException(status_code=500, detail="FIRECRAWL_API_KEY not configured")
    return FirecrawlApp(api_key=key)


_TRUE = {"1", "true", "yes", "on"}


def get_gemini_client():
    """Vertex (prod) authenticates with the Cloud Run service account via ADC and
    bills through Cloud Billing, so Google Cloud credits apply to it. Otherwise
    fall back to an AI Studio API key (staging / local), which they do not cover.
    The scraper is a standalone service, so this mirrors backend genai_factory."""
    if os.environ.get("GOOGLE_GENAI_USE_VERTEXAI", "").strip().lower() in _TRUE:
        return genai.Client(
            vertexai=True,
            project=os.environ["GOOGLE_CLOUD_PROJECT"],
            location=os.environ.get("GOOGLE_CLOUD_LOCATION", "global"),
        )
    key = os.environ.get("GEMINI_API_KEY")
    if not key:
        raise HTTPException(status_code=500, detail="GEMINI_API_KEY not configured")
    return genai.Client(api_key=key)


_RETRY_ATTEMPTS = 4


def _is_rate_limited(exc: Exception) -> bool:
    text = str(exc)
    return "429" in text or "RESOURCE_EXHAUSTED" in text


def _generate_with_retry(client, **kwargs):
    """Vertex serves Gemini from a *dynamic shared* quota, so a burst can
    transiently 429. This standalone service can't import the backend's
    genai_factory.generate_with_retry, so mirror it: retry only on 429 with a
    short, jittered back-off (~0.5s, 1s, 2s), and let anything else propagate
    immediately (we never want to paper over a real error by retrying it)."""
    for attempt in range(_RETRY_ATTEMPTS):
        try:
            return client.models.generate_content(**kwargs)
        except Exception as exc:
            if not _is_rate_limited(exc) or attempt == _RETRY_ATTEMPTS - 1:
                raise
            backoff = 0.5 * (2 ** attempt) * random.uniform(0.85, 1.15)
            print(
                f"Gemini rate-limited (429) on attempt {attempt + 1}/{_RETRY_ATTEMPTS}; "
                f"backing off {backoff:.1f}s"
            )
            time.sleep(backoff)


def get_supabase_client():
    """Return a Supabase client scoped to the Ingestor project. (REQ-27)"""
    from supabase import create_client
    url = os.environ.get("INGESTOR_SUPABASE_URL")
    key = os.environ.get("INGESTOR_SUPABASE_SERVICE_KEY")
    if not url or not key:
        raise RuntimeError("INGESTOR_SUPABASE_URL or INGESTOR_SUPABASE_SERVICE_KEY not configured")
    return create_client(url, key)


class ScrapeRequest(BaseModel):
    url: str


def upsert_to_ingestor_supabase(url: str, structured_output: str):
    """Write scraped_markdown to Ingestor Supabase via UPSERT on airbnb_url.
    (REQ-27). Best-effort only — properties.airbnb_url has no unique
    constraint, so this upsert 404s at the DB level (42P10) whenever a row
    doesn't already exist for this exact URL; ingest.py's own property_id-keyed
    write (save_scraped_markdown) is the actually-reliable path. Curated/
    rejected photos are deliberately NOT written here for the same reason —
    see ingest.py's save_photo_triage call, which uses property_id instead of
    this URL-keyed upsert (2026-09-09: found via live E2E testing that this
    call silently failed 100% of the time, so those columns were never
    actually persisted through the real ingest flow)."""
    try:
        client = get_supabase_client()
        from datetime import datetime, timezone
        payload = {
            "airbnb_url": url,
            "scraped_markdown": structured_output,
            "status": "Scraped",
            "updated_at": datetime.now(timezone.utc).isoformat(),
        }
        client.table("properties").upsert(payload, on_conflict="airbnb_url").execute()
    except Exception as e:
        print(f"Ingestor Supabase upsert failed (non-critical): {e}")
        sentry_sdk.capture_exception(e)


# ── Structured scraper extraction (2026-09-28) ──────────────────────────────
# Replaces the old GEMINI_PROMPT_AIRBNB.md markdown-template approach (a
# Make.com formatting workaround, not a real requirement -- see
# _Context/Universal_Fields_Extraction_Reliability_Investigation_2026-09-25.md
# for the full investigation). That design forced a lossy structured-data ->
# prose -> structured-data-again round trip: the merge step had to re-parse
# free text the scraper itself produced, and the markdown template's
# "Not specified in listing" placeholder got coerced into fabricated 0/False/
# {lat:0,lng:0} values once that text hit a typed schema downstream, and its
# combined `**City:** [City, State, Country]` field caused the country-recall
# failures on neighborhood/region-ambiguous listings (Alfama, Cotswolds).
# response_schema-constrained JSON, straight from the scraper, removes that
# whole lossy hop. Empirically verified (N=5, two independent rounds) against
# the exact previously-failing fixtures: location recall 58-60% -> 100%,
# the documented Otago world-knowledge-leakage hallucination 1/25 runs -> 0/50.
SCRAPER_STRUCTURED_SCHEMA = {
    "type": "OBJECT",
    "properties": {
        "meta": {
            "type": "OBJECT",
            "properties": {
                "listing_id": {"type": "STRING"},
                "listing_url": {"type": "STRING"},
                "language_detected": {"type": "STRING"},
                "data_completeness": {"type": "STRING"},  # "High" | "Medium" | "Low"
            },
        },
        "property_identity": {
            "type": "OBJECT",
            "properties": {
                "property_name": {"type": "STRING"},
                "property_type": {"type": "STRING"},
                "summary": {"type": "STRING"},
            },
        },
        "capacity": {
            "type": "OBJECT",
            "properties": {
                "max_guests": {"type": "INTEGER"},
                "bedrooms": {"type": "INTEGER"},
                "beds": {"type": "INTEGER"},
                "bathrooms": {"type": "NUMBER"},
            },
        },
        "location": {
            "type": "OBJECT",
            "properties": {
                # Quote-first grounding: placed BEFORE the structured fields so
                # the model must ground itself in an exact source excerpt
                # before filling typed location fields -- the mechanism that
                # suppresses "Otago"-style world-knowledge leakage into
                # state_region/country (cross-LLM consensus recommendation,
                # empirically confirmed above).
                "location_evidence_quote": {"type": "STRING"},
                "address": {"type": "STRING"},
                "neighborhood": {"type": "STRING"},
                "neighborhood_description": {"type": "STRING"},
                "city": {"type": "STRING"},
                "state_region": {"type": "STRING"},
                "country": {"type": "STRING"},
                "postal_code": {"type": "STRING"},
                "coordinates": {
                    "type": "OBJECT",
                    "properties": {
                        "lat": {"type": "NUMBER"},
                        "lng": {"type": "NUMBER"},
                    },
                },
                "parking": {"type": "STRING"},
            },
        },
        "host": {
            "type": "OBJECT",
            "properties": {
                "name": {"type": "STRING"},
                "host_id": {"type": "STRING"},
                "is_superhost": {"type": "BOOLEAN"},
                "is_verified": {"type": "BOOLEAN"},
                "bio": {"type": "STRING"},
                "response_rate": {"type": "STRING"},
                "response_time": {"type": "STRING"},
                "years_hosting": {"type": "INTEGER"},
                "total_reviews": {"type": "INTEGER"},
            },
        },
        "check_in_out": {
            "type": "OBJECT",
            "properties": {
                "check_in_time": {"type": "STRING"},
                "check_out_time": {"type": "STRING"},
                "check_in_method": {"type": "STRING"},
                "cancellation_policy": {"type": "STRING"},
            },
        },
        "amenities": {
            "type": "OBJECT",
            "properties": {
                "highlights": {
                    "type": "ARRAY",
                    "items": {
                        "type": "OBJECT",
                        "properties": {
                            "title": {"type": "STRING"},
                            "description": {"type": "STRING"},
                        },
                    },
                },
                "kitchen_dining": {"type": "ARRAY", "items": {"type": "STRING"}},
                "entertainment": {"type": "ARRAY", "items": {"type": "STRING"}},
                "climate_control": {"type": "ARRAY", "items": {"type": "STRING"}},
                "bathroom": {"type": "ARRAY", "items": {"type": "STRING"}},
                "bedroom_laundry": {"type": "ARRAY", "items": {"type": "STRING"}},
                "outdoor_pool": {"type": "ARRAY", "items": {"type": "STRING"}},
                "safety_security": {"type": "ARRAY", "items": {"type": "STRING"}},
                "parking_facilities": {"type": "ARRAY", "items": {"type": "STRING"}},
                "not_available": {"type": "ARRAY", "items": {"type": "STRING"}},
            },
        },
        "house_rules": {
            "type": "OBJECT",
            "properties": {
                "guest_capacity_note": {"type": "STRING"},
                "allowed": {"type": "ARRAY", "items": {"type": "STRING"}},
                "not_allowed": {"type": "ARRAY", "items": {"type": "STRING"}},
                "quiet_hours": {"type": "STRING"},
                "other_rules": {"type": "STRING"},
            },
        },
        "description_full_text": {"type": "STRING"},
        "media": {
            "type": "OBJECT",
            "properties": {
                "total_photos": {"type": "INTEGER"},
                "thumbnail_url": {"type": "STRING"},
                "gallery": {
                    "type": "ARRAY",
                    "items": {
                        "type": "OBJECT",
                        "properties": {
                            "caption": {"type": "STRING"},
                            "url": {"type": "STRING"},
                        },
                    },
                },
            },
        },
        "reviews": {
            "type": "OBJECT",
            "properties": {
                "overall_rating": {"type": "NUMBER"},
                "total_reviews": {"type": "INTEGER"},
                "rating_breakdown": {
                    "type": "OBJECT",
                    "properties": {
                        "accuracy": {"type": "NUMBER"},
                        "cleanliness": {"type": "NUMBER"},
                        "check_in": {"type": "NUMBER"},
                        "communication": {"type": "NUMBER"},
                        "location": {"type": "NUMBER"},
                        "value": {"type": "NUMBER"},
                    },
                },
                "guest_recognition": {"type": "STRING"},
            },
        },
        "pricing": {
            "type": "OBJECT",
            "properties": {
                "base_rate": {"type": "STRING"},
                "cleaning_fee": {"type": "STRING"},
                "service_fee": {"type": "STRING"},
                "total": {"type": "STRING"},
            },
        },
        "additional_info": {
            "type": "OBJECT",
            "properties": {
                "availability": {"type": "STRING"},
                "special_notes": {"type": "STRING"},
            },
        },
        # Meta-commentary about gaps -- NOT a per-field placeholder, so it
        # doesn't trigger the type-coercion bug. Safe to keep as-is.
        "data_quality_notes": {"type": "ARRAY", "items": {"type": "STRING"}},
        # Preserves the old template's "Additional Categories Discovered"
        # escape hatch for listing data that doesn't fit any fixed section.
        "additional_categories": {
            "type": "ARRAY",
            "items": {
                "type": "OBJECT",
                "properties": {
                    "category_name": {"type": "STRING"},
                    "items": {"type": "ARRAY", "items": {"type": "STRING"}},
                },
            },
        },
        # Top-level, matching UNIVERSAL_FIELDS_SCHEMA's own top-level field --
        # often buried inside a host bio's free text, so it needs its own
        # explicit slot rather than relying on host.bio alone to carry it
        # through to the merge step.
        "emergency_contact": {"type": "STRING"},
    },
}

SCRAPER_STRUCTURED_SYSTEM_PROMPT = """\
You are an expert Data Architect for vacation rental systems. Extract ALL \
information from the raw Airbnb listing data below into the exact JSON shape \
given by the response schema. No filtering, no summarization -- every fact \
present in the source belongs in some field or category below.

Rules:
- Only extract what is actually stated in the source -- never guess or infer a \
plausible-sounding value, even if it's a well-known fact (e.g. do not add a \
state/region/province just because you recognize the city -- if the source \
says "Queenstown" and never says "Otago", state_region must be omitted, not \
filled from your own world knowledge).
- If a field genuinely has no source support, OMIT it entirely. Never write \
"Not specified in listing", "N/A", or any placeholder -- an omitted field and a \
placeholder-filled field must never be confused downstream.
- location.location_evidence_quote: before filling any other location field, \
copy the exact sentence(s) from the source that state the property's location. \
If the source states no location at all, leave this empty and omit every other \
location field too.
- location.country is the sovereign nation (e.g. "Mexico", "Portugal", "United \
Kingdom"). location.city is the municipality/town (e.g. "Tulum", "Lisbon", \
"Queenstown") -- not a neighborhood. location.neighborhood is a district within \
a city (e.g. "Alfama" is a neighborhood of Lisbon, not the city itself). \
location.state_region is the state/province/county between city and country. A \
region name like "Cotswolds" that spans multiple administrative divisions is \
not itself a state_region -- if the source only says "Cotswolds, England", \
country is "United Kingdom", state_region is "England", and neighborhood or \
address may carry "Cotswolds".
- location.coordinates: only include if the source states explicit numeric \
latitude/longitude values. Never estimate or geocode coordinates from a city \
or address name.
- Property name is required and must never be omitted or "Not specified in \
listing" -- search the entire input thoroughly (it is virtually always present \
near the top, e.g. a page title/H1). Only if truly absent after an exhaustive \
search, use the most specific location/property-type description available \
from the source (e.g. "Entire bungalow in Tulum") instead.
- meta.language_detected and meta.data_completeness are self-assessments, not \
extractions -- always determine and fill both from the source text itself \
(what language is it written in; how complete does the listing data look), \
never omit these two specifically just because they aren't literally labeled \
in the source.
- emergency_contact: if the source gives any explicit contact info for \
emergencies or urgent issues (a phone number, email, etc. -- often embedded \
inside a host bio paragraph rather than its own labeled field), extract it \
into this field as its own distinct value, in addition to leaving the \
original sentence intact in host.bio.
- Preserve host bio and the full property description verbatim -- do not \
paraphrase or summarize those two fields.
- additional_categories: if the source contains data that doesn't fit any \
fixed field/category above, add it here rather than dropping it or forcing it \
into an unrelated field.
- Output valid JSON only, matching the response schema exactly.
"""


# ── Photo triage ─────────────────────────────────────────────────────────────
# Two-phase Gemini Vision pass over Airbnb-scraped photos. Host-*uploaded*
# photos already get real vision analysis (backend file_processor.py); scraped
# photos never did — this was just a list of URLs regexed out of Firecrawl's
# raw markdown, no visual judgment at all. Phase 1 is a light pass (rough
# classification, every photo) so nothing slips through unclassified; Phase 2
# is careful (deeper analysis, only the curated ~20) so the expensive
# per-photo work scales with what's actually kept, not with how many photos
# the listing happens to have.
#
# Entirely non-fatal by design — see _triage_photos. A classification problem
# must never block the scrape itself.

_MUSCACHE_IMG_RE = re.compile(r'!\[([^\]]*)\]\((https://a0\.muscache\.com/[^\s\)]+)\)')
_MUSCACHE_URL_RE = re.compile(r'https://a0\.muscache\.com/[^\s\)"\']+')

_MAX_CANDIDATE_PHOTOS = 100  # defensive ceiling on raw candidates, before any filtering
_MAX_CURATED_PHOTOS = 20
_MAX_PER_ROOM = 3
_MAX_CONCURRENT_DOWNLOADS = 10  # bounded, not unbounded fan-out — avoids looking like a burst to the CDN
# Confirmed by live probing against real a0.muscache.com photo URLs (2026-09-09):
# im_w=320/480/720/960/1200/1440 all return 200; im_w=640/750/800/1080/1280 all 404 —
# only certain preset widths are pre-generated, arbitrary values aren't. 480 is plenty
# for Phase 1's coarse room/property classification; Phase 2 stays full resolution.
_PHASE1_IMG_WIDTH = 480


def _extract_candidate_photos(raw_markdown: str) -> list[dict]:
    """Every distinct Airbnb CDN photo URL in Firecrawl's raw page markdown,
    keeping whatever alt-text caption Firecrawl captured alongside it."""
    seen: dict[str, str] = {}
    for caption, url in _MUSCACHE_IMG_RE.findall(raw_markdown):
        seen.setdefault(url, caption.strip())
    for url in _MUSCACHE_URL_RE.findall(raw_markdown):
        seen.setdefault(url, "")
    return [{"url": u, "caption": c} for u, c in seen.items()][:_MAX_CANDIDATE_PHOTOS]


def _download_image(url: str) -> tuple[bytes, str] | None:
    try:
        resp = httpx.get(url, timeout=15, follow_redirects=True)
        resp.raise_for_status()
        content_type = resp.headers.get("content-type", "image/jpeg").split(";")[0].strip()
        return resp.content, content_type
    except Exception as e:
        print(f"Photo triage: download failed for {url}: {e}")
        sentry_sdk.capture_exception(e)
        return None


def _with_preset_width(url: str, width: int) -> str:
    """Override (or add) muscache's im_w query param. Only ever called for
    Phase 1 — Phase 2 downloads the candidate's original URL unmodified."""
    if "im_w=" in url:
        return re.sub(r"im_w=\d+", f"im_w={width}", url)
    sep = "&" if "?" in url else "?"
    return f"{url}{sep}im_w={width}"


async def _download_image_async(
    client: httpx.AsyncClient, semaphore: asyncio.Semaphore, url: str
) -> tuple[bytes, str] | None:
    async with semaphore:
        try:
            resp = await client.get(url, timeout=15, follow_redirects=True)
            resp.raise_for_status()
            content_type = resp.headers.get("content-type", "image/jpeg").split(";")[0].strip()
            return resp.content, content_type
        except Exception as e:
            print(f"Photo triage: download failed for {url}: {e}")
            sentry_sdk.capture_exception(e)
            return None


def _parse_json_array(text: str) -> list:
    stripped = text.strip()
    if stripped.startswith("```"):
        first_newline = stripped.find("\n")
        if first_newline != -1:
            stripped = stripped[first_newline + 1:]
        if stripped.endswith("```"):
            stripped = stripped[:-3].rstrip()
    return json.loads(stripped)


_PHASE1_INTRO = """\
You are triaging photos scraped from a vacation rental listing page. For EACH
numbered photo below, decide whether it is actually a photo of THIS
property's own interior, exterior, or amenities — or something else entirely
(a neighborhood/street view, a map, a generic Airbnb icon, a host headshot, a
nearby attraction, unrelated stock imagery, etc).

If it IS a property photo, also give your best guess at which space it shows
(e.g. "exterior", "living_room", "kitchen", "bedroom", "bathroom", "pool",
"dining" — or a short custom label if it's a distinct space not covered by
these, e.g. "rooftop_terrace"). Use each photo's own caption (if given) and
the property context below to disambiguate — e.g. if the caption says
"Bedroom 2", label it "bedroom_2", not just "bedroom".

PROPERTY CONTEXT (for cross-reference — the description and stated room
counts should roughly match what you see in the photos):
{property_context}
"""

_PHASE1_OUTPUT_INSTRUCTIONS = """
Respond with ONLY a JSON array, one object per photo, in this exact shape:
[{"index": 1, "is_property_photo": true, "room": "kitchen", "reason": "..."}]
"""


async def _run_photo_triage_phase1(client, candidates: list[dict], property_context: str) -> list[dict]:
    """One batched Gemini call over every candidate photo — a lighter,
    rougher pass than Phase 2 (shorter prompt, no per-photo description).

    Downloads run in parallel (bounded concurrency — see _MAX_CONCURRENT_DOWNLOADS)
    at a downscaled preset width (_PHASE1_IMG_WIDTH): a listing can have up to
    _MAX_CANDIDATE_PHOTOS=100 photos, and serial full-res downloads risked
    outrunning /scrape's own timeout on large listings, for a task (coarse
    room/property classification) that doesn't need full resolution anyway."""
    semaphore = asyncio.Semaphore(_MAX_CONCURRENT_DOWNLOADS)
    async with httpx.AsyncClient() as http_client:
        downloads = await asyncio.gather(*[
            _download_image_async(
                http_client, semaphore, _with_preset_width(c["url"], _PHASE1_IMG_WIDTH)
            )
            for c in candidates
        ])

    parts = [genai.types.Part(text=_PHASE1_INTRO.format(property_context=property_context))]
    by_index: dict[int, dict] = {}
    index = 0
    for c, downloaded in zip(candidates, downloads):
        if downloaded is None:
            continue
        index += 1
        data, mime = downloaded
        caption_note = f' — caption: "{c["caption"]}"' if c["caption"] else ""
        parts.append(genai.types.Part(text=f"\nPhoto #{index}{caption_note}:"))
        parts.append(genai.types.Part.from_bytes(data=data, mime_type=mime))
        by_index[index] = c

    if not by_index:
        return []

    parts.append(genai.types.Part(text=_PHASE1_OUTPUT_INSTRUCTIONS))
    response = _generate_with_retry(
        client,
        model="gemini-3.6-flash",
        contents=[genai.types.Content(role="user", parts=parts)],
        config=genai.types.GenerateContentConfig(
            temperature=0.0, response_mime_type="application/json"
        ),
    )
    results = _parse_json_array(response.text)

    out = []
    for r in results:
        src = by_index.get(r.get("index"))
        if src is None:
            continue
        r["url"] = src["url"]
        r["caption"] = src["caption"]
        out.append(r)
    return out


# Cheap, free sanity check — no extra Gemini call. If a photo's own caption
# clearly names a room category that disagrees with what Phase 1 assigned,
# flag it. Purely informational: never auto-corrects anything, just gives a
# quick way to spot-check classification quality later (e.g. a query counting
# how many curated_photos/rejected_photos entries across all properties carry
# this flag = a rough, free error-rate signal without a dedicated eval pass).
_ROOM_KEYWORDS = {
    "bedroom": ["bedroom", "bed room"],
    "kitchen": ["kitchen"],
    "bathroom": ["bathroom", "bath room", "toilet", "restroom"],
    "pool": ["pool"],
    "patio": ["patio", "terrace", "deck"],
    "living_room": ["living room", "lounge"],
    "dining": ["dining"],
    "exterior": ["exterior", "outdoor", "garden", "yard", "entrance", "parking", "path"],
}


def _caption_room_mismatch(caption: str, room: str) -> str | None:
    if not caption:
        return None
    caption_lower, room_lower = caption.lower(), room.lower()
    implied = next(
        (cat for cat, kws in _ROOM_KEYWORDS.items() if any(kw in caption_lower for kw in kws)),
        None,
    )
    if implied and implied not in room_lower and room_lower not in implied:
        return f"caption suggests '{implied}' but was classified as '{room}'"
    return None


def _select_phase2_candidates(phase1_results: list[dict]) -> tuple[list[dict], list[dict]]:
    """From Phase 1's rough classification, keep up to _MAX_PER_ROOM photos per
    room (in the order Phase 1 returned them), capped at _MAX_CURATED_PHOTOS
    total. Returns (selected, rejected) — rejected covers both non-property
    photos and property photos dropped purely for room-redundancy."""
    selected, rejected = [], []
    per_room_count: dict[str, int] = {}
    for r in phase1_results:
        if not r.get("is_property_photo"):
            rejected.append(
                {"url": r["url"], "reason": r.get("reason", "not a property photo"), "phase": 1}
            )
            continue
        room = (r.get("room") or "other").strip().lower().replace(" ", "_")
        mismatch = _caption_room_mismatch(r.get("caption", ""), room)
        if per_room_count.get(room, 0) >= _MAX_PER_ROOM or len(selected) >= _MAX_CURATED_PHOTOS:
            entry = {"url": r["url"], "reason": f"redundant — already have enough '{room}' photos", "phase": 1}
            if mismatch:
                entry["caption_mismatch"] = mismatch
            rejected.append(entry)
            continue
        per_room_count[room] = per_room_count.get(room, 0) + 1
        selected.append({**r, "room": room, "caption_mismatch": mismatch})
    return selected, rejected


_PHASE2_INTRO = """\
You previously did a rough first pass on these photos. Now look carefully at
each one at full resolution and give a refined answer.

PROPERTY CONTEXT (for cross-reference):
{property_context}
"""

_PHASE2_OUTPUT_INSTRUCTIONS = """
Respond with ONLY a JSON array, one object per photo, in this exact shape:
[{"index": 1, "still_property_photo": true, "room": "kitchen", "description": "..."}]

"room" should be a refined, specific label — e.g. distinguish "bedroom_1" from
"bedroom_2" if there are multiple, using captions and visual differences to
tell them apart, not just the rough category from the earlier pass.
"description" should be a genuine, specific 1-2 sentence description of what
is actually shown, useful for someone who has never seen the photo. If, on
closer look, this really isn't a property photo after all, set
"still_property_photo": false and explain why in "description".
"""


def _run_photo_triage_phase2(
    client, selected: list[dict], property_context: str
) -> tuple[list[dict], list[dict]]:
    """Full-resolution, careful pass on the curated subset only."""
    parts = [genai.types.Part(text=_PHASE2_INTRO.format(property_context=property_context))]
    by_index: dict[int, dict] = {}
    for i, r in enumerate(selected, start=1):
        downloaded = _download_image(r["url"])  # full resolution — no width override
        if downloaded is None:
            continue
        data, mime = downloaded
        caption_note = f' — caption: "{r["caption"]}"' if r.get("caption") else ""
        rough_note = f' — rough category from an earlier pass: "{r["room"]}"'
        parts.append(genai.types.Part(text=f"\nPhoto #{i}{caption_note}{rough_note}:"))
        parts.append(genai.types.Part.from_bytes(data=data, mime_type=mime))
        by_index[i] = r

    if not by_index:
        return [], []

    parts.append(genai.types.Part(text=_PHASE2_OUTPUT_INSTRUCTIONS))
    response = _generate_with_retry(
        client,
        model="gemini-3.6-flash",
        contents=[genai.types.Content(role="user", parts=parts)],
        config=genai.types.GenerateContentConfig(
            temperature=0.0, response_mime_type="application/json"
        ),
    )
    results = _parse_json_array(response.text)

    curated, rejected = [], []
    for res in results:
        src = by_index.get(res.get("index"))
        if src is None:
            continue
        if not res.get("still_property_photo", True):
            rejected.append(
                {"url": src["url"], "reason": res.get("description", "reclassified on closer look"), "phase": 2}
            )
            continue
        entry = {
            "url": src["url"],
            "room": (res.get("room") or src["room"]).strip().lower().replace(" ", "_"),
            "description": res.get("description", ""),
            "source": "scrape",
        }
        if src.get("caption_mismatch"):
            entry["caption_mismatch"] = src["caption_mismatch"]
        curated.append(entry)
    return curated, rejected


async def _triage_photos(client, raw_markdown: str, property_context: str) -> tuple[list[dict], list[dict]]:
    """Full two-phase triage. Never raises — a triage failure must never block
    the scrape itself, so any error here just yields no curation at all."""
    try:
        candidates = _extract_candidate_photos(raw_markdown)
        if not candidates:
            return [], []
        phase1 = await _run_photo_triage_phase1(client, candidates, property_context)
        selected, rejected1 = _select_phase2_candidates(phase1)
        if selected:
            curated, rejected2 = _run_photo_triage_phase2(client, selected, property_context)
        else:
            curated, rejected2 = [], []
        return curated, rejected1 + rejected2
    except Exception as e:
        print(f"Photo triage failed (non-fatal, scrape continues): {e}")
        sentry_sdk.capture_exception(e)
        return [], []


def _extract_completeness(structured_output: str) -> str | None:
    try:
        value = json.loads(structured_output).get("meta", {}).get("data_completeness")
    except (json.JSONDecodeError, AttributeError):
        return None
    return value.strip().title() if value else None


def _fetch_and_structure(client, url: str) -> tuple[str, str]:
    """One full Firecrawl-fetch + Gemini-structure pass. Returns
    (extracted_markdown, structured_output); raises on a hard failure.
    `max_age=0` forces a live fetch on every call — 2026-09-17 incident:
    Firecrawl cached an incomplete pre-hydration snapshot of an Airbnb
    listing (only nav chrome, no real content) and kept serving that same
    stale copy on every subsequent request indefinitely. Airbnb listing
    pages change per-request anyway (pricing/availability/share tokens), so
    there's no good reason to ever trust the cache here.

    `structured_output` is now a JSON string (SCRAPER_STRUCTURED_SCHEMA),
    not markdown prose — see that schema's comment for why."""
    fc = get_firecrawl_client()
    scrape_result = fc.scrape(url, formats=["markdown"], max_age=0)
    extracted_markdown = getattr(scrape_result, "markdown", "")
    if not extracted_markdown:
        raise RuntimeError("Firecrawl returned empty markdown content")

    response = _generate_with_retry(
        client,
        model="gemini-3.6-flash",
        contents=f"INPUT DATA (raw scrape):\n{extracted_markdown}",
        config=genai.types.GenerateContentConfig(
            system_instruction=SCRAPER_STRUCTURED_SYSTEM_PROMPT,
            response_mime_type="application/json",
            response_schema=SCRAPER_STRUCTURED_SCHEMA,
            temperature=0.0,
        ),
    )
    return extracted_markdown, response.text


@app.post("/scrape")
async def scrape_airbnb(req: ScrapeRequest):
    """
    1. Firecrawl scrapes the Airbnb listing → raw markdown (live, never cached).
    2. Gemini structures the markdown into the canonical format.
    3. If Gemini itself flags the result Low completeness, retry the whole
       fetch+structure pass once more before giving up on this request — a
       genuine one-off render timing flake (distinct from the caching bug
       above, which max_age=0 already rules out) can clear on a second try.
    4. Upserts scraped_markdown to Ingestor Supabase directly (REQ-27).
    5. Returns structured output to caller, including data_completeness so
       the caller (ingest_worker) can decide whether to schedule its own
       longer-horizon background retry.
    """
    url = req.url
    print(f"Starting scrape for URL: {url}")

    try:
        client = get_gemini_client()
    except Exception as e:
        print(f"ERROR: Gemini client init failed: {e}")
        raise HTTPException(status_code=500, detail=f"Gemini client init failed: {str(e)}")

    extracted_markdown = ""
    structured_output = ""
    completeness: str | None = None
    last_error: Exception | None = None
    for attempt in range(2):
        try:
            extracted_markdown, structured_output = _fetch_and_structure(client, url)
        except Exception as e:
            # Surface the actual error in Cloud Run logs (HTTPException details
            # don't end up in stdout — they only go in the response body).
            # Deliberately does NOT discard a usable (if Low) result from a
            # prior attempt — only the retry attempt failing, not the whole
            # request, so a network blip on attempt 2 doesn't turn an
            # already-good-enough attempt 1 into a hard 500.
            print(f"ERROR: scrape/structure attempt {attempt + 1}/2 failed: {e}")
            sentry_sdk.capture_exception(e)
            last_error = e
            continue
        last_error = None
        completeness = _extract_completeness(structured_output)
        if completeness != "Low":
            break
        print(f"Scrape attempt {attempt + 1}/2 came back Low completeness, {'retrying' if attempt == 0 else 'giving up'}")

    if last_error is not None and not structured_output:
        raise HTTPException(status_code=500, detail=f"Scrape failed: {last_error}")

    # 2.5. Photo triage — non-fatal, never blocks the scrape (see _triage_photos)
    curated_photos, rejected_photos = await _triage_photos(client, extracted_markdown, structured_output)

    # 3. Write to Ingestor Supabase (REQ-27) — failures are non-fatal and logged.
    # curated_photos/rejected_photos are NOT written here — see the function's
    # own docstring; the backend persists those via property_id instead.
    upsert_to_ingestor_supabase(url, structured_output)

    # 4. Return to caller
    return {
        "status": "success",
        "data": structured_output,
        "curated_photos": curated_photos,
        "rejected_photos": rejected_photos,
        "data_completeness": completeness,
    }


@app.api_route("/health", methods=["GET", "HEAD"])
def health_check():
    return {"status": "ok"}


# ── Smoke test: verifies SCRAPER_STRUCTURED_SCHEMA's "omit, don't guess" +
# location-hierarchy contract, real Gemini calls ────────────────────────────
# This project has no pytest suite (see backend/services/gemini_merge_resolve.py's
# _UNIVERSAL_FIELDS_TEST for the established pattern, which this mirrors, and
# _tests/health/run_health_check.py for the live-Gemini-smoke-test idiom in
# general). A mocked response would prove nothing here -- the whole point is
# verifying Gemini itself respects the anti-hallucination rules, not that this
# module's own plumbing works. Requires local Vertex ADC and scraper/requirements.txt
# installed. Run:
#   python -m venv venv && venv/bin/pip install -r requirements.txt
#   venv/bin/python main.py

_FIXTURE_WITH_FACTS = """
Charming flat in Alfama, the oldest neighborhood in Lisbon
Entire rental unit in Lisbon, Portugal
3 guests, 1 bedroom, 2 beds, 1 bath

Tucked into the winding cobblestone streets of Alfama, Lisbon's oldest and
most authentic neighborhood. Hosted by Joao, Superhost. "I grew up two
streets from this flat -- reach me at +351 91 234 5678 for anything urgent."
Amenities: Wifi, Kitchen, Washer, Air conditioning, Smoke alarm.
"""

_FIXTURE_NO_WORLD_KNOWLEDGE = """
Lakeview Lodge -- Queenstown, New Zealand, gateway to Milford Sound
Entire home, 8 guests, 4 bedrooms

Perched above Lake Wakatipu in Queenstown, New Zealand -- gateway to
Milford Sound. Queenstown is New Zealand's adventure capital.
Amenities: Wifi, Fireplace, Hot tub, Smoke alarm.
"""


async def _SCRAPER_STRUCTURED_TEST() -> None:
    try:
        import google.auth
        google.auth.default()
    except Exception as exc:
        print(f"_SCRAPER_STRUCTURED_TEST: SKIP (no local ADC -- run "
              f"'gcloud auth application-default login') -- {exc}")
        return
    os.environ.setdefault("GOOGLE_GENAI_USE_VERTEXAI", "true")
    os.environ.setdefault("GOOGLE_CLOUD_PROJECT", "alfred-prod-502215")
    os.environ.setdefault("GOOGLE_CLOUD_LOCATION", "global")

    client = genai.Client()

    async def _extract(raw: str) -> dict:
        response = await client.aio.models.generate_content(
            model="gemini-3.6-flash",
            contents=f"INPUT DATA (raw scrape):\n{raw}",
            config=genai.types.GenerateContentConfig(
                system_instruction=SCRAPER_STRUCTURED_SYSTEM_PROMPT,
                response_mime_type="application/json",
                response_schema=SCRAPER_STRUCTURED_SCHEMA,
                temperature=0.0,
            ),
        )
        return json.loads(response.text)

    with_facts = await _extract(_FIXTURE_WITH_FACTS)
    no_world_knowledge = await _extract(_FIXTURE_NO_WORLD_KNOWLEDGE)

    failures = []

    loc = with_facts.get("location", {})
    if loc.get("city") != "Lisbon":
        failures.append(f"expected location.city='Lisbon', got {loc.get('city')!r}")
    if loc.get("country") != "Portugal":
        failures.append(f"expected location.country='Portugal', got {loc.get('country')!r}")
    if loc.get("neighborhood") != "Alfama":
        failures.append(f"expected location.neighborhood='Alfama', got {loc.get('neighborhood')!r}")
    if with_facts.get("emergency_contact") != "+351 91 234 5678":
        failures.append(f"expected emergency_contact='+351 91 234 5678', got "
                         f"{with_facts.get('emergency_contact')!r}")
    meta = with_facts.get("meta", {})
    if not meta.get("language_detected") or not meta.get("data_completeness"):
        failures.append(f"expected meta.language_detected/data_completeness both filled, got {meta!r}")

    nwk_loc = no_world_knowledge.get("location", {})
    state_region = (nwk_loc.get("state_region") or "").lower()
    for forbidden in ("otago", "south island", "milford sound", "wakatipu"):
        if forbidden in state_region:
            failures.append(f"world-knowledge leakage: state_region={nwk_loc.get('state_region')!r} "
                             f"contains {forbidden!r} (never stated in the source)")
    coords = nwk_loc.get("coordinates") or {}
    if coords.get("lat") or coords.get("lng"):
        failures.append(f"fabricated coordinates: {coords!r} (source states no coordinates)")

    if failures:
        print("_SCRAPER_STRUCTURED_TEST: FAIL")
        for f in failures:
            print(f"  - {f}")
    else:
        print("_SCRAPER_STRUCTURED_TEST: PASS")


if __name__ == "__main__":
    asyncio.run(_SCRAPER_STRUCTURED_TEST())
