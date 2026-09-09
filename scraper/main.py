import asyncio
import json
import os
import random
import re
import time

import httpx
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from firecrawl import FirecrawlApp
from google import genai

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


def upsert_to_ingestor_supabase(
    url: str,
    structured_output: str,
    curated_photos: list[dict] | None = None,
    rejected_photos: list[dict] | None = None,
):
    """Write scraped_markdown (+ photo triage results, if any) to Ingestor
    Supabase via UPSERT on airbnb_url. (REQ-27)"""
    try:
        client = get_supabase_client()
        from datetime import datetime, timezone
        payload = {
            "airbnb_url": url,
            "scraped_markdown": structured_output,
            "status": "Scraped",
            "updated_at": datetime.now(timezone.utc).isoformat(),
        }
        if curated_photos is not None:
            payload["curated_photos"] = curated_photos
        if rejected_photos is not None:
            payload["rejected_photos"] = rejected_photos
        client.table("properties").upsert(payload, on_conflict="airbnb_url").execute()
    except Exception as e:
        print(f"Ingestor Supabase upsert failed (non-critical): {e}")


def get_gemini_prompt(markdown_data: str) -> str:
    prompt_path = os.path.join(os.path.dirname(__file__), "GEMINI_PROMPT_AIRBNB.md")
    try:
        with open(prompt_path, "r", encoding="utf-8") as f:
            template = f.read()
    except FileNotFoundError:
        template = "Please analyze the following data:\n[INSERT_DATA_HERE]"
    return template.replace("[INSERT_DATA_HERE]", markdown_data)


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
        model="gemini-3.8-flash",
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
        model="gemini-3.8-flash",
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
        return [], []


@app.post("/scrape")
async def scrape_airbnb(req: ScrapeRequest):
    """
    1. Firecrawl scrapes the Airbnb listing → raw markdown.
    2. Gemini structures the markdown into the canonical format.
    3. Upserts scraped_markdown to Ingestor Supabase directly (REQ-27).
    4. Returns structured output to caller.
    """
    url = req.url
    print(f"Starting scrape for URL: {url}")

    # 1. Firecrawl extraction
    try:
        fc = get_firecrawl_client()
        scrape_result = fc.scrape(url, formats=["markdown"])
    except Exception as e:
        # Surface the actual error in Render logs (HTTPException details
        # don't end up in stdout — they only go in the response body).
        print(f"ERROR: Firecrawl extraction failed: {e}")
        raise HTTPException(status_code=500, detail=f"Firecrawl extraction failed: {str(e)}")

    extracted_markdown = getattr(scrape_result, "markdown", "")
    if not extracted_markdown:
        print("ERROR: Firecrawl returned empty markdown content")
        raise HTTPException(status_code=500, detail="Firecrawl returned empty markdown content")

    # 2. Gemini structuring
    try:
        client = get_gemini_client()
        final_prompt = get_gemini_prompt(extracted_markdown)
        response = _generate_with_retry(
            client,
            model="gemini-3.8-flash",
            contents=final_prompt,
            config=genai.types.GenerateContentConfig(
                system_instruction=(
                    "You are an expert Data Architect for vacation rental systems. "
                    "You strictly follow instructions to output structured Markdown."
                ),
                temperature=0.0,
            ),
        )
        structured_output = response.text
    except Exception as e:
        print(f"ERROR: Gemini API processing failed: {e}")
        raise HTTPException(status_code=500, detail=f"Gemini API processing failed: {str(e)}")

    # 2.5. Photo triage — non-fatal, never blocks the scrape (see _triage_photos)
    curated_photos, rejected_photos = await _triage_photos(client, extracted_markdown, structured_output)

    # 3. Write to Ingestor Supabase (REQ-27) — failures are non-fatal and logged
    upsert_to_ingestor_supabase(url, structured_output, curated_photos, rejected_photos)

    # 4. Return to caller
    return {
        "status": "success",
        "data": structured_output,
        "curated_photos": curated_photos,
        "rejected_photos": rejected_photos,
    }


@app.api_route("/health", methods=["GET", "HEAD"])
def health_check():
    return {"status": "ok"}
