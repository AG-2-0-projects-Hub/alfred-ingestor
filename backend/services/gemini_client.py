"""
Gemini client using the google-genai SDK.

Prompts A and B are copied VERBATIM (grounding rules aside, see below) from the
Make.com blueprint (Supabase Alfred Airbnb - B2 - The Ingestor.blueprint.json).
Prompts C and D are derived from the same blueprint's document pattern
and adapted for audio and tabular data — originals not present in any
spec document (flagged as MISSING_DEPENDENCY: no verbatim source found).

All four now carry an explicit GROUNDING RULES block (added 2026-09-28, see
_Context/Merge_And_Ingested_Pipeline_Enhancement_Plan_2026-09-28.md and
C:\\Users\\San_8\\.claude\\plans\\fluffy-riding-feigenbaum.md) — a full audit
found none of them forbade filling gaps from world knowledge or required
grounding a stated fact in the actual source, the same failure mode already
fixed in the scraper (scraper/main.py) and the merge step
(gemini_merge_resolve.py). Measured baseline (real Gemini calls, 2 rounds,
N=5 each, see _Context/ingestion_pipeline_harness/): Prompt D's "capture the
intent behind the data" line reliably caused a false "weekday vs weekend"
pricing-policy claim from just 2 unrelated dates -- 7/10 runs. That's the
grounding rules' primary target; the other three prompts' fixtures didn't
reproduce a comparable failure at baseline, but the rules are added to all
four to match the shared pattern defensively.

NOTE: file bytes are sent INLINE (types.Part.from_bytes), not via the Gemini
File API -- Vertex rejects that API outright ("This method is only supported
in the Gemini Developer client"). An earlier version of this docstring's
routing table said "Gemini File API"; that was never true for this codebase
and is corrected here.
"""

from google import genai
from google.genai import types

from services import genai_factory

MODEL = "gemini-3.6-flash"

# ─── Prompt A — PDF / DOCX (verbatim from blueprint Route 0) ─────────────────
SYSTEM_INSTRUCTION_A = "You are a Data Extractor. Your job is to read documents and extract key facts for a rental property."

USER_PROMPT_A = """\
You are an expert Knowledge Base Architect for vacation rentals. Your job is to extract and organize ALL information from this document in a way that makes it queryable and useful.

CRITICAL INSTRUCTION: Do NOT force information into predefined buckets. Read the document, identify what topics it actually covers, then create appropriate sections for those topics.

ANALYSIS PROCESS:
1. Determine document type and purpose
2. Identify all distinct topics/subjects covered
3. Extract specific, actionable information for each topic
4. If it's a conversation, analyze communication style separately

OUTPUT FORMAT (Hybrid Frontmatter + Adaptive Markdown):

---
document_type: [e.g., "Host-Guest Conversation", "House Manual", "Property Instructions", "Policy Document", "Mixed Content"]
primary_language: [e.g., "English", "Spanish", "Mixed"]
information_density: [High/Medium/Low - How much useful info per page?]
contains_host_voice: [Yes/No - Can we learn communication style from this?]
---

[IF DOCUMENT CONTAINS HOST COMMUNICATION - Include this section:]
### Communication Style Profile
**Tone:** [Formal/Casual/Friendly/Strict/etc.]
**Message Structure:** [Short texts/Long paragraphs/Bullet points]
**Language Patterns:**
- Greeting style: [How do they start messages?]
- Sign-off style: [How do they end messages?]
- Emoji usage: [Frequency and which ones?]
- Capitalization patterns: [Normal/ALL CAPS emphasis/all lowercase]
- Punctuation quirks: [Multiple exclamation marks? Ellipses?]

**Example Phrases:** [Quote 2-3 actual phrases that capture their voice]

---

### Information Categories Discovered
[Create sections based on what topics are ACTUALLY covered in this document. Do not use predefined categories. Examples might be:]

**[Name each section based on content, such as:]**
- "Early Check-in Procedures"
- "Boat Dock Access and Rules"
- "Pool Heater Operation"
- "Noise Policy and Quiet Hours"
- "Parking and Vehicle Information"
- "WiFi and Technology Setup"
- "Emergency Contact Protocol"
- "Local Recommendations"
- "Special Equipment Instructions"
- etc.

For each topic you identify, extract:
- Specific facts (codes, times, names, phone numbers)
- Step-by-step instructions where present
- Conditions or exceptions ("only on weekends", "if needed")
- Any contradictions or unclear points that might need clarification

### Document Gaps & Questions
[List any topics that seem incomplete or might generate follow-up questions. E.g., "Mentions pool heating but no cost mentioned" or "References 'the usual procedure' without explaining it"]

GROUNDING RULES (apply throughout):
- State only what the document actually says. When recording a specific fact (a code, price, name, time, or place), stick to the exact wording or number given — do not fill a gap using outside/general knowledge about the subject, even something you're confident is true (e.g. if the document mentions a landmark or partial address without naming the city, do not add the city yourself).
- If something is genuinely unclear, ambiguous, or not stated, say so in the Document Gaps & Questions section — never write "N/A", "Not specified", or a guessed value in its place anywhere else in the output.

REMEMBER: Let the document tell you what categories it needs. A conversation about pool maintenance shouldn't be forced into "House Rules" - create a "Pool Maintenance and Heating" section instead. Be thorough and capture EVERYTHING that is actually stated.\
"""

# ─── Prompt B — Images (verbatim from blueprint Route 1) ─────────────────────
SYSTEM_INSTRUCTION_B = "You are a Vision Analyst for Airbnb listings. Be factual and precise."

USER_PROMPT_B = """\
You are an expert Property Documentation AI. Your job is to extract ALL relevant information from this image for a vacation rental knowledge base.

CRITICAL INSTRUCTION: Do NOT force information into predefined categories. Instead, identify what information is ACTUALLY present and create appropriate sections for it.

ANALYSIS PROCESS:
1. Examine the image carefully
2. Identify what type of space/content this is
3. Extract ALL details a guest might need to know
4. Organize findings into logical, descriptive sections

OUTPUT FORMAT (Hybrid Frontmatter + Adaptive Markdown):

---
content_type: [e.g., "Interior Room", "Outdoor Area", "Instructional Sign", "Amenity Close-up"]
primary_subject: [e.g., "Kitchen", "Pool Area", "WiFi Instructions"]
visual_quality: [e.g., "Clear and well-lit", "Partially obscured", "Professional photo"]
guest_relevance: [High/Medium/Low - How useful is this for answering guest questions?]
---

### Identified Information Categories
[Let the content guide you. Create sections based on what's actually visible. Examples might include:]

**[Create your own section names based on content, such as:]**
- "Appliances and Equipment"
- "Access Codes and Instructions"
- "Safety Features"
- "View and Ambiance"
- "Potential Guest Concerns"
- "Operational Instructions"
- etc.

For each section you create, provide:
- Specific details (brands, quantities, locations)
- Any visible text (transcribed verbatim)
- Context that helps understand how to use/access items

### Additional Observations
[Anything noteworthy that doesn't fit elsewhere: damage, unique features, maintenance issues, exceptional qualities]

GROUNDING RULES (apply throughout):
- Only report what is actually visible and clearly legible in the image. If text is blurry, cropped, or otherwise not confidently readable, say it's illegible rather than guessing a specific value.
- Do not add facts from outside knowledge (a brand you recognize from a partial logo, a location you infer from a landmark) unless it is clearly and legibly shown in the image itself.

REMEMBER: Your goal is to capture EVERYTHING that is actually visible and legible. Create as many sections as needed. Be specific and thorough, but never guess at something you can't clearly make out.\
"""

# ─── Prompt C — Audio / Voice (MISSING_DEPENDENCY: no verbatim source) ───────
# Derived from blueprint's document-extraction pattern, adapted for audio.
SYSTEM_INSTRUCTION_C = "You are a Transcription and Knowledge Extraction Specialist for vacation rentals. Be accurate and thorough."

USER_PROMPT_C = """\
You are an expert Knowledge Base Architect for vacation rentals. This audio recording is from a property host. Your job is to transcribe it fully and extract ALL actionable information for the property knowledge base.

CRITICAL: First determine whether this audio actually contains audible human speech.
If the audio is silent, contains no discernible speech, or is too noisy/unclear to make
out actual words, DO NOT invent or guess a transcript. Instead output ONLY:

---
document_type: "Host Audio Note"
contains_host_voice: No
---

### Full Transcript
[NO_SPEECH_DETECTED — audio was silent, unintelligible, or contained no discernible speech]

Do this instead of the normal output below whenever you are not confident real words are
present. Never fabricate plausible-sounding content to fill in gaps.

ANALYSIS PROCESS (only if real speech IS present):
1. Transcribe the audio verbatim
2. Identify all distinct topics/subjects mentioned
3. Extract specific, actionable information for each topic
4. Capture the host's communication tone and style

OUTPUT FORMAT (Hybrid Frontmatter + Adaptive Markdown):

---
document_type: "Host Audio Note"
primary_language: [e.g., "English", "Spanish", "Mixed"]
information_density: [High/Medium/Low]
contains_host_voice: [Yes/No]
---

### Full Transcript
[Verbatim transcription of the audio]

### Communication Style Profile
**Tone:** [Formal/Casual/Friendly/Strict/etc.]
**Language Patterns:**
- Key phrases used: [2-3 characteristic phrases]
- Emoji/filler words: [any notable speech patterns]

---

### Information Categories Discovered
[Create sections based on what topics are ACTUALLY mentioned. Do not use predefined categories.]

For each topic extract:
- Specific facts (codes, times, names, phone numbers)
- Step-by-step instructions where present
- Conditions or exceptions mentioned

### Document Gaps & Questions
[List any topics that seem incomplete or need follow-up]

GROUNDING RULES (apply throughout, in addition to the silence check above):
- If a specific detail within the audio — a phone number, code, password, or similar — is spoken but not clearly/confidently audible, write "[unclear]" in its place in the transcript rather than your best guess. This is different from the whole-clip silence check above: it applies even when most of the audio is clearly understandable.
- Do not fill in a detail using outside knowledge or a plausible-sounding guess — only transcribe what you can confidently make out.

REMEMBER: Capture EVERYTHING mentioned that you can actually make out. Even casual asides about the property can be valuable for guest experience — but never guess at a specific detail you didn't clearly hear.\
"""

# ─── Prompt D — Sheets / CSV (MISSING_DEPENDENCY: no verbatim source) ────────
# Derived from blueprint's document-extraction pattern, adapted for tabular data.
SYSTEM_INSTRUCTION_D = "You are a Data Extractor. Your job is to read structured tabular data and extract key facts for a rental property."

USER_PROMPT_D = """\
You are an expert Knowledge Base Architect for vacation rentals. This spreadsheet or CSV contains structured data about a property. Your job is to extract and organize ALL information in a way that makes it queryable and useful.

CRITICAL INSTRUCTION: Do NOT force information into predefined buckets. Read the data, identify what it represents, then create appropriate sections.

ANALYSIS PROCESS:
1. Determine what the spreadsheet tracks (pricing, inventory, contacts, rules, etc.)
2. Identify all distinct data categories
3. Extract specific, actionable information for each category
4. Note any patterns, ranges, or conditions in the data

OUTPUT FORMAT (Hybrid Frontmatter + Adaptive Markdown):

---
document_type: "Spreadsheet / Structured Data"
data_subject: [e.g., "Pricing Calendar", "Inventory List", "Contact Directory", "House Rules"]
information_density: [High/Medium/Low]
contains_host_voice: [Yes/No]
---

### Information Categories Discovered
[Create sections based on what data is ACTUALLY present. Examples might be:]

**[Name each section based on content, such as:]**
- "Seasonal Pricing Rules"
- "Inventory and Quantities"
- "Vendor and Maintenance Contacts"
- "Booking Policies"
- etc.

For each category extract:
- Specific values (prices, quantities, phone numbers, dates)
- Rules or conditions in the data
- Any anomalies or important thresholds

### Data Gaps & Questions
[Note any incomplete columns, missing values, or ambiguous entries that might need clarification]

GROUNDING RULES (apply throughout):
- Only state a "rule" or "policy" (e.g. a weekday vs weekend pricing pattern) if enough rows actually support it — a handful of unrelated dates or values is not evidence of a general rule. When in doubt, report the specific values as-is instead of naming a policy, and note the limited sample size in Data Gaps & Questions.
- Do not fill in or "correct" a value using outside knowledge (e.g. do not pad a short number back to what you assume is a standard format). Report exactly what the data shows, and flag it in Data Gaps & Questions if it looks incomplete or malformed.

REMEMBER: Structured data can contain implicit rules, but only when the data actually supports one — a pricing table with enough weekend vs weekday rows to show the pattern is a policy; two unrelated dates are just two numbers. Capture the intent behind the data only when the evidence is really there.\
"""


def _get_client() -> genai.Client:
    return genai_factory.make_client()


# The Gemini File API (client.files.upload) exists ONLY on the Developer API —
# Vertex rejects it with "This method is only supported in the Gemini Developer
# client" — so file bytes go inline instead, which both transports accept.
# Inline data rides in the request body, so keep it clear of the ~20 MB cap.
_MAX_INLINE_BYTES = 15 * 1024 * 1024

def _inline_part(data: bytes, mime_type: str) -> types.Part:
    if len(data) > _MAX_INLINE_BYTES:
        raise ValueError(
            f"File is {len(data) // (1024 * 1024)} MB — the limit is "
            f"{_MAX_INLINE_BYTES // (1024 * 1024)} MB."
        )
    return types.Part.from_bytes(data=data, mime_type=mime_type)


# Revised 2026-09-16, corrected same day after a code review caught the first
# pass going too far. Original `_INGEST_CALL_TIMEOUT_S = 20` was too tight — real
# measurement showed gemini-3.6-flash's normal successful call latency (14.9-19.1s
# across sequential/concurrent-2/concurrent-4 patterns, real Vertex, real content)
# already ate nearly all of that budget with near-zero margin, so the stall
# detector was cancelling-and-restarting calls that were on track to succeed.
#
# The first fix removed call_timeout entirely (matching prod, which has never had
# one here and works reliably) — but genai_factory.generate_with_retry()'s stall
# detection (the retry-on-hang path built to fix the confirmed-live 2026-09-09
# silent-stall incident) only engages when call_timeout is set. Removing it
# outright didn't just widen the margin, it deleted that protection for every
# caller of _generate() app-wide, including query_knowledge_base and the voice
# add-knowledge path — neither of which has any other timeout at all.
#
# Fix: a real ceiling with real margin (35s, ~1.8x the observed 19.1s max) but
# fewer attempts (2, not the default 4) so the worst case — 2 x 35s + ~0.5s
# backoff ≈ 70.5s — stays comfortably under ingest.py's 90s outer per-file
# watchdog instead of eating most of it.
_INGEST_CALL_TIMEOUT_S = 35
_INGEST_CALL_ATTEMPTS = 2


async def _generate(system_instruction: str, user_prompt: str, parts: list) -> str:
    client = _get_client()
    response = await genai_factory.generate_with_retry(
        client,
        model=MODEL,
        contents=[types.Content(role="user", parts=parts)],
        config=types.GenerateContentConfig(
            system_instruction=system_instruction,
        ),
        call_timeout=_INGEST_CALL_TIMEOUT_S,
        attempts=_INGEST_CALL_ATTEMPTS,
    )
    return response.text


async def process_with_prompt_a(data: bytes, mime_type: str) -> str:
    """Prompt A: PDF / document, sent inline."""
    parts = [types.Part(text=USER_PROMPT_A), _inline_part(data, mime_type)]
    return await _generate(SYSTEM_INSTRUCTION_A, USER_PROMPT_A, parts)


async def process_with_prompt_a_text(extracted_text: str) -> str:
    """Prompt A: DOCX/DOC text extracted natively, sent as plain text."""
    parts = [types.Part(text=USER_PROMPT_A + "\n\n" + extracted_text)]
    return await _generate(SYSTEM_INSTRUCTION_A, USER_PROMPT_A, parts)


async def process_with_prompt_b(data: bytes, mime_type: str) -> str:
    """Prompt B: image, sent inline."""
    parts = [types.Part(text=USER_PROMPT_B), _inline_part(data, mime_type)]
    return await _generate(SYSTEM_INSTRUCTION_B, USER_PROMPT_B, parts)


async def process_with_prompt_c(data: bytes, mime_type: str) -> str:
    """Prompt C: audio, sent inline."""
    parts = [types.Part(text=USER_PROMPT_C), _inline_part(data, mime_type)]
    return await _generate(SYSTEM_INSTRUCTION_C, USER_PROMPT_C, parts)


async def process_with_prompt_d(table_text: str) -> str:
    """Prompt D: Sheets/CSV data read natively, sent as plain text."""
    parts = [types.Part(text=USER_PROMPT_D + "\n\n" + table_text)]
    return await _generate(SYSTEM_INSTRUCTION_D, USER_PROMPT_D, parts)


# ── Smoke test: verifies all 4 ingestion prompts' GROUNDING RULES, real
# Gemini calls ─────────────────────────────────────────────────────────────
# Mirrors scraper/main.py's _SCRAPER_STRUCTURED_TEST and
# gemini_merge_resolve.py's _UNIVERSAL_FIELDS_TEST -- this project has no
# pytest suite, and a mocked response would prove nothing here (the point is
# verifying Gemini itself respects the rules, not this module's plumbing).
# Full measured baseline (2 rounds, N=5, before/after) lives in
# _Context/ingestion_pipeline_harness/ -- this is the permanent, minimal
# regression guard, not a replacement for that harness. Requires local
# Vertex ADC. Run:
#   backend/venv/bin/python -m services.gemini_client

_INGEST_TEXT_FIXTURE = """\
Welcome to Casa Alegre!
Wifi network: CasaAlegre_5G
Wifi password: sunshine88
Check-in time is 3:00 PM.
Our house sits two blocks from the Zocalo, so you can walk to restaurants.
"""

_INGEST_SHEET_FIXTURE = """\
| date       | nightly_rate | contact_zip |
|:-----------|-------------:|:------------|
| 2026-11-03 |          180 | 00501       |
| 2026-12-24 |          450 | 00501       |
"""


def _make_noise_wav_bytes() -> bytes:
    """Pure random noise, no speech -- stdlib only."""
    import io as _io
    import random as _random
    import struct as _struct
    import wave as _wave
    framerate, duration_s = 16000, 2
    n_frames = framerate * duration_s
    rng = _random.Random(7)
    buf = _io.BytesIO()
    with _wave.open(buf, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(framerate)
        samples = [rng.randint(-32768, 32767) for _ in range(n_frames)]
        w.writeframes(_struct.pack("<%dh" % n_frames, *samples))
    return buf.getvalue()


def _make_wifi_card_png_bytes() -> bytes:
    """Clear wifi network/password text + one heavily blurred phone number --
    generated at test-run-time (Pillow already a backend dependency) rather
    than stored as a binary fixture in source."""
    import io as _io
    from PIL import Image, ImageDraw, ImageFilter

    card = Image.new("RGB", (500, 220), (245, 245, 240))
    draw = ImageDraw.Draw(card)
    draw.text((20, 20), "WIFI NETWORK: CasaAlegre_5G", fill=(20, 20, 20))
    draw.text((20, 50), "PASSWORD: sunshine88", fill=(20, 20, 20))
    draw.text((20, 90), "Host mobile:", fill=(20, 20, 20))
    phone_layer = Image.new("RGB", (500, 220), (245, 245, 240))
    ImageDraw.Draw(phone_layer).text((20, 115), "555-201-9988", fill=(20, 20, 20))
    blurred = phone_layer.filter(ImageFilter.GaussianBlur(radius=8))
    card.paste(blurred.crop((0, 105, 500, 150)), (0, 105))
    buf = _io.BytesIO()
    card.save(buf, format="PNG")
    return buf.getvalue()


async def _INGESTION_GROUNDING_TEST() -> None:
    """Real Gemini calls against all 4 prompt paths, checking the same
    grounding contract added 2026-09-28: facts actually present get
    extracted, world-knowledge/unsupported facts don't get invented."""
    try:
        import google.auth
        google.auth.default()
    except Exception as exc:
        print(f"_INGESTION_GROUNDING_TEST: SKIP (no local ADC -- run "
              f"'gcloud auth application-default login') -- {exc}")
        return
    import os
    os.environ.setdefault("GOOGLE_GENAI_USE_VERTEXAI", "true")
    os.environ.setdefault("GOOGLE_CLOUD_PROJECT", "alfred-prod-502215")
    os.environ.setdefault("GOOGLE_CLOUD_LOCATION", "global")

    failures = []

    # Prompt A: facts extracted, no city invented for the ambiguous "Zocalo" mention.
    a_out = await process_with_prompt_a_text(_INGEST_TEXT_FIXTURE)
    a_lower = a_out.lower()
    if "casaalegre_5g" not in a_lower or "sunshine88" not in a_lower:
        failures.append(f"Prompt A: expected wifi network/password in output, got: {a_out[:300]!r}")
    for forbidden in ("mexico city", "cdmx", "oaxaca", "cuernavaca", "puebla"):
        if forbidden in a_lower:
            failures.append(f"Prompt A: world-knowledge leakage -- {forbidden!r} in output "
                             f"(source never names a city)")

    # Prompt B: clear text extracted, blurred phone number not guessed.
    b_out = await process_with_prompt_b(_make_wifi_card_png_bytes(), "image/png")
    b_lower = b_out.lower()
    if "casaalegre_5g" not in b_lower or "sunshine88" not in b_lower:
        failures.append(f"Prompt B: expected wifi network/password in output, got: {b_out[:300]!r}")
    if "555-201-9988" in b_out or "5552019988" in b_out.replace(" ", "").replace("-", ""):
        failures.append("Prompt B: vision confabulation -- invented the deliberately blurred phone number")

    # Prompt C: silence/noise correctly flagged, never fabricated a transcript.
    c_out = await process_with_prompt_c(_make_noise_wav_bytes(), "audio/wav")
    if "NO_SPEECH_DETECTED" not in c_out:
        failures.append(f"Prompt C: expected NO_SPEECH_DETECTED for pure noise, got: {c_out[:300]!r}")

    # Prompt D: values extracted, no weekday/weekend policy asserted from 2 sparse rows.
    d_out = await process_with_prompt_d(_INGEST_SHEET_FIXTURE)
    d_lower = d_out.lower()
    if "180" not in d_out or "450" not in d_out:
        failures.append(f"Prompt D: expected both rates in output, got: {d_out[:300]!r}")
    if "00501" not in d_out:
        failures.append(f"Prompt D: expected zip '00501' preserved in output, got: {d_out[:300]!r}")
    for phrase in ("weekday", "weekend"):
        idx = d_lower.find(phrase)
        if idx == -1:
            continue
        window = d_lower[max(0, idx - 90):idx + len(phrase) + 90]
        if not any(cue in window for cue in ("no ", "not ", "cannot", "can't", "insufficient",
                                              "limited sample", "too few", "n/a")):
            failures.append(f"Prompt D: unsupported {phrase!r} policy claim from 2 sparse rows "
                             f"(no nearby hedge/negation): ...{d_out[max(0,idx-60):idx+60]!r}...")

    if failures:
        print("_INGESTION_GROUNDING_TEST: FAIL")
        for f in failures:
            print(f"  - {f}")
    else:
        print("_INGESTION_GROUNDING_TEST: PASS")


if __name__ == "__main__":
    import asyncio as _asyncio
    _asyncio.run(_INGESTION_GROUNDING_TEST())


# ─── Knowledge Base Query (host audit tool) ──────────────────────────────────
# Alfred's voice, mirrored from the guest-facing SYSTEM_PROMPT in
# gemini_messenger.py, but framed as a trusted check for the HOST.
SYSTEM_INSTRUCTION_KB = (
    "You are Alfred — a warm, composed property concierge who speaks with quiet "
    "elegance and precision: helpful, considered, and never speculative. Here you "
    "are helping the HOST verify what you know about their property, so answer in "
    "the same natural, concierge voice you'd use with a guest — just framed as a "
    "trusted check. Acknowledge before answering, keep it conversational, and vary "
    "your phrasing so it never feels templated."
)


async def query_knowledge_base(
    master_json: dict,
    question: str,
    learned_knowledge: list[dict] | None = None,
) -> str:
    """Answer a host question using property master_json and any learned knowledge."""
    import json as _json
    master_json_str = _json.dumps(master_json, indent=2, ensure_ascii=False)

    learned_block = ""
    if learned_knowledge:
        lines = []
        for e in learned_knowledge:
            lines.append(
                f"- [{e.get('category', 'other')}] Q: {e.get('problem_summary', '')}\n"
                f"  A: {e.get('solution_summary', '')}"
            )
        learned_block = "\n\nPast Resolutions (from automated learning):\n" + "\n".join(lines)

    prompt = f"""You are Alfred, the property's concierge assistant, helping the HOST audit what you know. Speak in your natural voice — warm, precise, and composed, with a concierge's touch. When the Master JSON includes the host's communication style, mirror it. Vary your phrasing; never sound templated or robotic. Open with one beat of acknowledgement, then give the facts.

Your ONLY knowledge sources are the Master JSON and Past Resolutions below. You must NOT infer, assume, or add anything beyond what is explicitly present — this is a verification tool, so accuracy matters more than completeness. Never speculate.

When the host asks a question:
1. Search the Master JSON for the relevant field(s), and check the Past Resolutions for any relevant Q&A.
2. Answer concisely and conversationally, in plain language — no JSON syntax in the reply.
3. If the data is partial, give what you have and gently note what's missing.
4. If the information is in neither source, say plainly that it isn't in the knowledge base yet — then, if helpful, suggest what the host could add so you can answer it next time.
5. Reply in the language the host wrote in.

Master JSON:
{master_json_str}{learned_block}

Host question: {question}"""
    parts = [types.Part(text=prompt)]
    return await _generate(SYSTEM_INSTRUCTION_KB, prompt, parts)
