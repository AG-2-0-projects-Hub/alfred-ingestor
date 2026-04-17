"""
Gemini client using the google-genai SDK.

Prompts A and B are copied VERBATIM from the Make.com blueprint
(Supabase Alfred Airbnb - B2 - The Ingestor.blueprint.json).
Prompts C and D are derived from the same blueprint's document pattern
and adapted for audio and tabular data — originals not present in any
spec document (flagged as MISSING_DEPENDENCY: no verbatim source found).
"""

import asyncio
import io
import os
from google import genai
from google.genai import types

MODEL = "gemini-2.5-pro"

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

REMEMBER: Let the document tell you what categories it needs. A conversation about pool maintenance shouldn't be forced into "House Rules" - create a "Pool Maintenance and Heating" section instead. Be thorough and capture EVERYTHING.\
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

REMEMBER: Your goal is to capture EVERYTHING a guest or host might need to reference. Create as many sections as needed. Be specific and thorough.\
"""

# ─── Prompt C — Audio / Voice (MISSING_DEPENDENCY: no verbatim source) ───────
# Derived from blueprint's document-extraction pattern, adapted for audio.
SYSTEM_INSTRUCTION_C = "You are a Transcription and Knowledge Extraction Specialist for vacation rentals. Be accurate and thorough."

USER_PROMPT_C = """\
You are an expert Knowledge Base Architect for vacation rentals. This audio recording is from a property host. Your job is to transcribe it fully and extract ALL actionable information for the property knowledge base.

ANALYSIS PROCESS:
1. Transcribe the audio verbatim
2. Identify all distinct topics/subjects mentioned
3. Extract specific, actionable information for each topic
4. Capture the host's communication tone and style

OUTPUT FORMAT (Hybrid Frontmatter + Adaptive Markdown):

---
document_type: "Host Audio Note"
primary_language: [e.g., "English", "Spanish", "Mixed"]
information_density: [High/Medium/Low]
contains_host_voice: Yes
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

REMEMBER: Capture EVERYTHING mentioned. Even casual asides about the property can be valuable for guest experience.\
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

REMEMBER: Structured data often contains implicit rules. A pricing table with weekend vs weekday rates is a policy, not just numbers. Capture the intent behind the data.\
"""


def _get_client() -> genai.Client:
    return genai.Client(api_key=os.environ["GEMINI_API_KEY"])


async def upload_file(data: bytes, filename: str, mime_type: str) -> str:
    """Upload bytes to the Gemini File API. Returns the file URI."""
    client = _get_client()
    response = await client.aio.files.upload(
        file=io.BytesIO(data),
        config=types.UploadFileConfig(
            display_name=filename,
            mime_type=mime_type,
        ),
    )
    # Wait until file is ACTIVE
    file_name = response.name
    for _ in range(30):
        file_info = await client.aio.files.get(name=file_name)
        if file_info.state == types.FileState.ACTIVE:
            return file_info.uri
        await asyncio.sleep(2)
    raise RuntimeError(f"Gemini file {file_name} did not become ACTIVE in time.")


async def delete_file(uri: str) -> None:
    """Delete a file from the Gemini File API by URI."""
    client = _get_client()
    # Extract name from URI e.g. "https://generativelanguage.googleapis.com/v1beta/files/abc123"
    name = uri.rstrip("/").split("/")[-1]
    try:
        await client.aio.files.delete(name=f"files/{name}")
    except Exception:
        pass  # Best-effort cleanup


async def _generate(system_instruction: str, user_prompt: str, parts: list) -> str:
    client = _get_client()
    response = await client.aio.models.generate_content(
        model=MODEL,
        contents=[types.Content(role="user", parts=parts)],
        config=types.GenerateContentConfig(
            system_instruction=system_instruction,
        ),
    )
    return response.text


async def process_with_prompt_a(file_uri: str, mime_type: str) -> str:
    """Prompt A: PDF uploaded to Gemini File API."""
    parts = [
        types.Part(text=USER_PROMPT_A),
        types.Part(file_data=types.FileData(file_uri=file_uri, mime_type=mime_type)),
    ]
    return await _generate(SYSTEM_INSTRUCTION_A, USER_PROMPT_A, parts)


async def process_with_prompt_a_text(extracted_text: str) -> str:
    """Prompt A: DOCX/DOC text extracted natively, sent as plain text."""
    parts = [types.Part(text=USER_PROMPT_A + "\n\n" + extracted_text)]
    return await _generate(SYSTEM_INSTRUCTION_A, USER_PROMPT_A, parts)


async def process_with_prompt_b(file_uri: str, mime_type: str) -> str:
    """Prompt B: Image uploaded to Gemini File API."""
    parts = [
        types.Part(text=USER_PROMPT_B),
        types.Part(file_data=types.FileData(file_uri=file_uri, mime_type=mime_type)),
    ]
    return await _generate(SYSTEM_INSTRUCTION_B, USER_PROMPT_B, parts)


async def process_with_prompt_c(file_uri: str, mime_type: str) -> str:
    """Prompt C: Audio uploaded to Gemini File API."""
    parts = [
        types.Part(text=USER_PROMPT_C),
        types.Part(file_data=types.FileData(file_uri=file_uri, mime_type=mime_type)),
    ]
    return await _generate(SYSTEM_INSTRUCTION_C, USER_PROMPT_C, parts)


async def process_with_prompt_d(table_text: str) -> str:
    """Prompt D: Sheets/CSV data read natively, sent as plain text."""
    parts = [types.Part(text=USER_PROMPT_D + "\n\n" + table_text)]
    return await _generate(SYSTEM_INSTRUCTION_D, USER_PROMPT_D, parts)
