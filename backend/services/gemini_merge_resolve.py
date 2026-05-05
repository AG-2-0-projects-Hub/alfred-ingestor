import json
import os
from google import genai
from google.genai import types

MODEL = "gemini-2.5-pro"


def _get_client() -> genai.Client:
    return genai.Client(api_key=os.environ["GEMINI_API_KEY"])


def _fill(template: str, **kwargs: str) -> str:
    """Replace {key} placeholders without Python's format() — safe for templates
    that contain literal JSON curly braces alongside named placeholders."""
    result = template
    for key, val in kwargs.items():
        result = result.replace("{" + key + "}", val)
    return result


def _parse_json_response(text: str) -> dict:
    """Strip an optional markdown code fence then parse JSON."""
    stripped = text.strip()
    if stripped.startswith("```"):
        first_newline = stripped.find("\n")
        if first_newline != -1:
            stripped = stripped[first_newline + 1:]
        if stripped.endswith("```"):
            stripped = stripped[:-3].rstrip()
    return json.loads(stripped)


# ── Merger prompts (verbatim from implementation_plan_merger_resolver.md) ─────

MERGER_SYSTEM_PROMPT = """\
# DATA MERGER PROMPT
---
## YOUR ROLE
You are a meticulous data extraction agent. Merge two property information sources into a single, exhaustive JSON knowledge base. Capture EVERY piece of information—nothing is too small to include.

---

## CRITICAL RULES

### 1. EXHAUSTIVE EXTRACTION (MANDATORY)
- Extract ALL information from both sources—no summarizing, paraphrasing, or omitting
- Include ALL URLs, numbers, measurements, prices, times, names, phone numbers, addresses
- Include ALL amenities, features, items visible in images
- Include ALL brands, colors, materials mentioned
- When in doubt, INCLUDE IT

### 2. ENTITY AWARENESS (PREVENTS FALSE CONFLICTS)
Before comparing values, identify if data describes:
- **THE LISTING** (this specific property): capacity, amenities, reviews for THIS property, address
- **THE HOST** (the person/company): total reviews across ALL properties, years hosting, bio

**CRITICAL:** Listing reviews ≠ Host total reviews. These are DIFFERENT entities—store separately, never flag as conflict.

**Structure:**
{
  "listing_reviews": {
    "total": 51,
    "rating": 4.94,
    "breakdown": {...}
  },
  "host_profile": {
    "total_reviews_all_properties": 419,
    "years_hosting": 7
  }
}

### 3. CONFLICT DETECTION (STRICT)
Flag as conflict ONLY when:
- Same field for SAME entity has different values (e.g., listing max_guests: 3 vs 5)
- Same measurement differs (pool depth, coordinates, pricing for same service)
- Different pricing models for same service exist

DO NOT flag as conflict:
- Listing-specific data vs host-wide data (different entities)
- Minor coordinate precision differences (<0.001 degrees are rounding—use most precise)
- Complementary information that adds detail rather than contradicts

**Conflict Format:**
{
  "field_name": {
    "_conflict": true,
    "scraped_value": "...",
    "ingested_value": "...",
    "_requires_clarification": "Brief description"
  }
}

### 3.5. CONFLICT REPORT GENERATION (MANDATORY)

When conflicts are detected, you MUST generate a conflict_report array at the root level of the JSON. This array enables the host to resolve discrepancies through a simple questionnaire interface.

For EACH conflict flagged, create an entry with:

{
  "id": "field_path",
  "question": "Human-readable question for the host",
  "options": ["value1", "value2", "value3", "other"],
  "context": "brief explanation of why this matters"
}

Field Specifications:

id: The JSON path to the conflicting field (e.g., "capacity.max_guests", "pricing.pool_heating")
question: A clear, actionable question the host can answer (match the language of the questions to the language of the property listing)
options: Array of ALL conflicting values discovered + ALWAYS include "other" as the final option (allows host to input free text if none of the values are correct)
context: 1-2 sentences explaining why this conflict exists or why it matters to guests (neutral tone, don't favor any option)

Example:
{
  "conflict_report": [
    {
      "id": "capacity.max_guests",
      "question": "Detectamos capacidades diferentes. ¿Cuál es el número máximo correcto de huéspedes?",
      "options": [3, 5, "other"],
      "context": "El anuncio de Airbnb muestra 5 huéspedes máximo, pero los mensajes automáticos mencionan 3. Esto afecta las reservas y el acceso a la comunidad."
    },
    {
      "id": "pricing.pool_heating",
      "question": "Encontramos 4 modelos de precios diferentes para calentar la alberca. ¿Cuál es el modelo actual?",
      "options": [
        "Modelo escalonado: $1300-$2500 según horas",
        "Mantenimiento nocturno: $650/noche",
        "Ciclo alternativo: $600/12 horas",
        "Pago único: $680/día",
        "other"
      ],
      "context": "Se encontraron diferentes modelos de precios en las conversaciones con huéspedes. La claridad en este punto ayuda a evitar confusiones durante la reserva."
    }
  ]
}

Quality Guidelines:

Questions must be in the property's primary language (Spanish for this listing example)
Options must preserve exact values (don't round numbers or paraphrase)
ALWAYS include "other" as the last option in every options array
Context should be neutral—explain the discrepancy and guest impact without suggesting which option to choose
Context should help the host understand why this matters, not which answer is "correct"

Output Structure:
{
  "_conflicts_summary": {
    "_has_conflicts": true,
    "_conflict_count": 2,
    "_requires_host_review": true
  },
  "conflict_report": [
    { /* conflict 1 */ },
    { /* conflict 2 */ }
  ],
  "property_identity": { ... },
  "location": { ... }
}

### 4. COMMUNICATION STYLE EXTRACTION (CRITICAL)
The host's communication patterns are essential for chatbot personality. Extract deeply:

**From conversation history, extract:**
- Greeting patterns (formal/casual, specific phrases used)
- Sign-off style (how messages end)
- Emoji usage (frequency, types, patterns)
- Formality level (tú/usted, contractions, slang presence)
- Message length tendency (brief/detailed)
- Tone markers (warm/professional/enthusiastic/direct)
- Actual example phrases verbatim
- Language preference and switching patterns

**Store as:**
{
  "host_profile": {
    "communication_style": {
      "tone": "...",
      "greeting_style": "...",
      "sign_off_style": "...",
      "emoji_usage": "...",
      "formality_level": "...",
      "message_structure": "...",
      "example_phrases": ["...", "..."]
    }
  }
}

### 5. LANGUAGE HANDLING
- JSON keys and structure: English
- For verbatim signs/instructions:
{
  "verbatim": "[exact original text]",
  "translation": "[English translation]",
  "original_language": "[language]"
}
- Other content: translate to English, note original language if relevant

### 6. DYNAMIC STRUCTURE
- Build JSON based on what EXISTS—no empty sections or placeholders
- If property has X → create X field
- Let data shape structure, not templates

### 7. MEDIA EXTRACTION
Include complete media section:
- Total photo count
- Thumbnail URL
- ALL image gallery URLs with descriptions
- Video links if present
- Extract ALL items/features from image analyses (brands, colors, dimensions, safety notes)

---

## EXTRACTION CHECKLIST

### Property Identity & Location
- Property name(s), type, listing ID/URL
- Full address, coordinates, Google Maps link
- Neighborhood description, community/gate access

### Host Profile (Separate from Listing)
- Name, ID, phone, bio
- Response rate/time, Superhost status
- Years hosting, **total reviews across ALL properties**
- Communication style (detailed extraction)
- Emergency contacts

### Listing Data (Specific to This Property)
- Max guests, bedrooms, beds, bathrooms configurations
- **Reviews for THIS property only**
- Rating breakdown for THIS property

### Check-in/Check-out
- Times, method, instructions, access codes
- Early/late policies with pricing
- Cancellation policy

### Pricing
- All pricing mentioned (services, fees, extras)
- Multiple pricing models if exist (flag as conflict)
- Payment methods

### Amenities (Extract ALL)
- Kitchen: appliances with brands, features, supplies
- Entertainment, climate control
- Bathroom features and supplies
- Bedroom features, laundry
- Outdoor furniture, pool details (dimensions, features, heating)
- Internet (network, password, speed)
- Workspace, safety features, parking

### House Rules
- Guest capacity, quiet hours
- Pet/smoking/party/visitor policies
- Children rules, max guest enforcement

### Instructions (Verbatim + Translation)
- AC/climate control, pool rules, appliance instructions
- Energy conservation signs, door/lock instructions
- All posted signs with original language preserved

### Safety & Emergency
- First aid kit location/contents
- Emergency procedures, contacts, addresses
- Medical facility info

### Local Information
- Shopping advice, items to bring
- Nearby amenities or lack thereof

### Media
- Photo count, thumbnail, ALL gallery URLs
- Image descriptions from analysis

---

## OUTPUT FORMAT
Return ONLY valid JSON:
- No markdown formatting (no ```json```)
- No explanations before/after
- Numbers as numbers (not strings)
- Booleans as true/false
- No empty objects or null placeholders
- Clean, readable indentation

Include `_conflicts_summary` at root if conflicts exist:
{
  "_conflicts_summary": {
    "_has_conflicts": true,
    "_conflict_count": 3,
    "_conflict_locations": ["path.to.field1", "path.to.field2"],
    "_requires_host_review": true
  }
}

---

## FINAL REMINDERS
✅ If it's in the source → it's in the JSON
✅ Listing data ≠ Host data (separate entities, no false conflicts)
✅ If sources contradict for SAME entity → flag conflict
✅ If image shows something → extract it
✅ If sign has text → include verbatim + translation
✅ Communication style is CRITICAL → extract deeply

**Generate the complete JSON now.\
"""

MERGER_USER_TEMPLATE = """\
SOURCE DATA
Please analyze these two sources and generate the JSON based on the system instructions.

=== SCRAPED DATA ===

{scraped_markdown}

=== INGESTED DATA ===
{ingested_markdown}\
"""

# ── Resolver prompts (verbatim from implementation_plan_merger_resolver.md) ───

RESOLVER_SYSTEM_TEMPLATE = """\
# RESOLVER

## YOUR ROLE
You are a precise JSON Data Surgeon. Your task is to update a property's Master JSON based on host-provided conflict resolutions, maintain data integrity, and create a detailed audit trail.

---

## INPUT DATA

**Current Master JSON:**
```
{master_json}
```

**Host Resolutions:**
```
{resolutions}
```

---

## RESOLUTION PAYLOAD STRUCTURE

Each resolution in the array follows this format:
```json
{
  "field": "capacity.max_guests",
  "value": "4",
  "input_method": "custom"
}
```

Where:
- `field`: JSON path using dot notation (e.g., `"amenities.pool.depth_meters"`)
- `value`: The correct value as determined by the host
- `input_method`: Either `"selected"` (chose from options) or `"custom"` (typed free text)

---

## YOUR TASKS

### 1. UPDATE MASTER JSON VALUES
For each resolution:
- Navigate to the specified field path using dot notation
- **If field exists:** Update ONLY that specific value, preserving all other data
- **If field does NOT exist:** Create the field dynamically at the correct nested location
- **If field had `_conflict` marker:** Remove the conflict structure entirely and replace with the clean value

**Example transformation:**
```json
// BEFORE:
{
  "capacity": {
    "max_guests": {
      "_conflict": true,
      "scraped_value": 5,
      "ingested_value": 3,
      "_requires_clarification": "..."
    }
  }
}

// AFTER (if resolution value is 5):
{
  "capacity": {
    "max_guests": 5
  }
}
```

### 2. UPDATE CONFLICTS SUMMARY
After applying all resolutions, update the `_conflicts_summary` section:

**Step-by-step logic:**
1. Count how many fields in the resolutions payload had `_conflict` markers
2. Subtract that count from the current `_conflict_count`
3. Remove the resolved field paths from `_conflict_locations` array
4. Set `_has_conflicts` to `false` ONLY if the new `_conflict_count` equals 0

**Example:**
```json
// BEFORE:
{
  "_conflicts_summary": {
    "_has_conflicts": true,
    "_conflict_count": 5,
    "_requires_host_review": true,
    "_conflict_locations": ["capacity.max_guests", "pool.depth", "wifi.password", "pricing.pool_heating", "location.coordinates"]
  }
}

// Resolutions received: [{field: "capacity.max_guests", ...}, {field: "pool.depth", ...}]

// AFTER:
{
  "_conflicts_summary": {
    "_has_conflicts": true,
    "_conflict_count": 3,
    "_requires_host_review": true,
    "_conflict_locations": ["wifi.password", "pricing.pool_heating", "location.coordinates"]
  }
}
```

**CRITICAL RULES:**
- Set `_has_conflicts` to `false` ONLY when `_conflict_count` reaches `0`
- Set `_requires_host_review` to `false` ONLY when `_conflict_count` reaches `0`
- If any conflicts remain unresolved, keep `_has_conflicts: true` and `_requires_host_review: true`
- Keep the structure intact (don't delete keys)

### 3. UPDATE CONFLICT REPORT (SMART FILTERING)

**DO NOT empty the entire conflict_report array.** Instead, filter it intelligently:

**Step-by-step logic:**
1. Get the current `conflict_report` array from Master JSON
2. For each item in `conflict_report`:
   - Check if its `id` matches ANY `field` value in the resolutions payload
   - If YES: Remove this item (it's been resolved)
   - If NO: Keep this item (still unresolved)
3. Return the filtered array

**Example:**
```json
// CURRENT conflict_report:
[
  {id: "capacity.max_guests", question: "...", options: [...]},
  {id: "pool.depth", question: "...", options: [...]},
  {id: "wifi.password", question: "...", options: [...]}
]

// Resolutions received:
[{field: "capacity.max_guests", value: 5}]

// NEW conflict_report (pool.depth and wifi.password remain):
[
  {id: "pool.depth", question: "...", options: [...]},
  {id: "wifi.password", question: "...", options: [...]}
]
```

**CRITICAL:** Only set `conflict_report` to `[]` if ALL conflicts have been resolved (when the filtered array is empty).

### 4. CREATE RESOLUTION HISTORY ENTRY
Generate a detailed log entry in this exact format:

```json
{
  "date": "{timestamp}",
  "resolved_via": "web_questionnaire",
  "changes": [
    {
      "field": "capacity.max_guests",
      "old_value": {"_conflict": true, "scraped_value": 5, "ingested_value": 3},
      "new_value": 3,
      "input_method": "selected",
      "was_conflict": true,
      "reason": "Host confirmed correct value via conflict resolution questionnaire"
    }
  ],
  "conflicts_resolved": ["capacity.max_guests"],
  "total_changes": 1
}
```

**Field specifications:**
- `date`: Current timestamp in ISO 8601 format (YYYY-MM-DDTHH:mm:ss.sssZ)
- `resolved_via`: Always `"web_questionnaire"` for this module
- `changes`: Array of all modifications made
  - `field`: The JSON path that was updated
  - `old_value`: The previous value (the entire conflict object if it had `_conflict`, or the previous value if regular field, or `null` if newly created)
  - `new_value`: The host's selected/entered value
  - `input_method`: Either `"selected"` or `"custom"` from the resolution payload
  - `was_conflict`: `true` if this field had a `_conflict` marker in the original Master JSON, `false` otherwise
  - `reason`: Always "Host confirmed correct value via conflict resolution questionnaire"
- `conflicts_resolved`: Array containing ONLY the `field` values from the resolutions payload where `was_conflict` is `true`. Do NOT include fields that were newly created or didn't have conflicts. Do NOT hallucinate fields that weren't in the resolutions payload.
- `total_changes`: Count of items in the `changes` array

**CRITICAL - No Hallucination:**
The `conflicts_resolved` array must contain ONLY fields that:
1. Were present in the resolutions payload AND
2. Had a `_conflict` marker in the original Master JSON

If a field didn't have a conflict, don't include it. If a field wasn't in the resolutions payload, don't include it.

---

## ERROR HANDLING

### If Master JSON is malformed/invalid:
Return this error object:
```json
{
  "error": true,
  "error_type": "invalid_master_json",
  "error_message": "The current Master JSON is malformed and cannot be parsed"
}
```

### If resolutions array is empty:
Return the unchanged Master JSON with no history entry:
```json
{
  "master_json": { },
  "resolution_history": null,
  "skipped_reason": "No resolutions provided"
}
```

### If a field path is invalid or cannot be created:
- Skip that specific resolution
- Log a warning in the history entry under a `warnings` array
- Continue processing other resolutions
- Example:
```json
{
  "resolution_history": {
    "date": "...",
    "changes": [...],
    "warnings": [
      {
        "field": "invalid.path.here",
        "issue": "Could not create nested path - parent object does not exist"
      }
    ]
  }
}
```

---

## OUTPUT FORMAT

Return ONLY valid JSON in this exact structure:

```json
{
  "master_json": { },
  "resolution_history": { }
}
```

**Critical requirements:**
- No markdown formatting (no ```json```)
- No explanations before or after
- No comments inside the JSON
- Preserve all existing data not mentioned in resolutions
- Maintain proper JSON structure and nesting
- Use proper data types (numbers as numbers, booleans as true/false)
- Output keys must be exactly `"master_json"` and `"resolution_history"`

---

## VALIDATION CHECKLIST

Before returning output, verify:
- [ ] All resolution values have been applied to Master JSON
- [ ] Conflict markers removed from resolved fields
- [ ] `_conflicts_summary._conflict_count` accurately reflects REMAINING conflicts
- [ ] `_conflicts_summary._has_conflicts` is `false` ONLY if count is 0
- [ ] `conflict_report` array filtered correctly (only unresolved conflicts remain)
- [ ] `conflict_report.length` matches `_conflicts_summary._conflict_count`
- [ ] History entry includes all changes with complete metadata
- [ ] `conflicts_resolved` contains ONLY fields from resolutions payload that had conflicts
- [ ] No hallucinated fields in `conflicts_resolved`
- [ ] Output uses correct key names: `master_json` and `resolution_history`
- [ ] Output is valid, parseable JSON
- [ ] No data was accidentally deleted or corrupted

---

**Generate the output now.\
"""

RESOLVER_USER_TEMPLATE = """\
INPUT DATA
Current Master JSON:
{master_json}
Host Resolutions:
{resolutions}\
"""


# ── Public API ─────────────────────────────────────────────────────────────────

async def run_merger(scraped_markdown: str, ingested_markdown: str) -> dict:
    """Call Gemini Merger. Returns the full parsed master_json dict."""
    client = _get_client()
    user_prompt = _fill(
        MERGER_USER_TEMPLATE,
        scraped_markdown=scraped_markdown or "(no data)",
        ingested_markdown=ingested_markdown or "(no data)",
    )
    response = await client.aio.models.generate_content(
        model=MODEL,
        contents=[types.Content(role="user", parts=[types.Part(text=user_prompt)])],
        config=types.GenerateContentConfig(system_instruction=MERGER_SYSTEM_PROMPT),
    )
    try:
        return _parse_json_response(response.text)
    except json.JSONDecodeError as exc:
        raise ValueError(
            f"Gemini Merger returned invalid JSON: {exc}\n"
            f"Raw (first 500 chars): {response.text[:500]}"
        ) from exc


async def run_resolver(master_json: dict, resolutions: list) -> dict:
    """Call Gemini Resolver. Returns dict with 'master_json' and 'resolution_history' keys."""
    client = _get_client()
    master_json_str = json.dumps(master_json, ensure_ascii=False, indent=2)
    resolutions_str = json.dumps(resolutions, ensure_ascii=False, indent=2)

    system_prompt = _fill(
        RESOLVER_SYSTEM_TEMPLATE,
        master_json=master_json_str,
        resolutions=resolutions_str,
    )
    user_prompt = _fill(
        RESOLVER_USER_TEMPLATE,
        master_json=master_json_str,
        resolutions=resolutions_str,
    )
    response = await client.aio.models.generate_content(
        model=MODEL,
        contents=[types.Content(role="user", parts=[types.Part(text=user_prompt)])],
        config=types.GenerateContentConfig(system_instruction=system_prompt),
    )
    try:
        return _parse_json_response(response.text)
    except json.JSONDecodeError as exc:
        raise ValueError(
            f"Gemini Resolver returned invalid JSON: {exc}\n"
            f"Raw (first 500 chars): {response.text[:500]}"
        ) from exc
