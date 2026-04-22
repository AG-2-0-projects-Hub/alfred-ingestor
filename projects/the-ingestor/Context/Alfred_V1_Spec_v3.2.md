# PROJECT ALFRED: V1 PRODUCT SPECIFICATION

## Document: v3.2 (Final) | Product Version: V1 (MVP)

**Purpose:** Complete specification for the first shippable version of Alfred. Designed for AI-assisted building (Cursor, Claude Code). Every module includes exact build order, dependencies, and test criteria.

**Test scope:** 20-30 properties (family & partners), ~2 weeks.
**Channels:** Telegram + Guest Web App.

---

# PART I: ARCHITECTURE

---

## 1. CORE IDENTITY

**Alfred** is a multi-agent orchestration engine for short-term vacation rental properties (Airbnb, VRBO). V1 delivers the core product: AI-powered guest communication with human escalation and self-learning.

**V1 capabilities:**
- Scrape Airbnb listings and build a structured "Brain" (Master JSON)
- Ingest host-uploaded files (PDFs, images, voice notes) into the Brain
- Detect and resolve data conflicts between sources
- Vectorize the Brain for intelligent semantic retrieval (RAG)
- Receive guest messages via Telegram and Guest Web App
- Generate AI responses using RAG + learned knowledge
- Detect negative sentiment and escalate to host
- Enable bi-directional Host ↔ Guest live chat (Live Tunnel)
- Automatically distill human interventions into new knowledge
- Host Dashboard (Flutter) for managing everything
- Admin Dashboard for internal team oversight

**Not in V1:**
- WhatsApp Business API (requires Meta Business verification — deferred to V2)
- Job queue / Redis caching (not needed at 20-30 properties)
- Error monitoring / structured logging (Sentry, Axiom — V2)
- Transactional email (Resend — V2)
- Product analytics (PostHog — V2)
- Channex.io / OTA integration (V3)
- Cleaning schedule automation (V3+)

---

## 2. V1 TECH STACK

| Layer | Technology | Purpose |
|---|---|---|
| **Database** | Supabase (PostgreSQL + Storage + Auth + Realtime) | All persistent state, file storage, auth, real-time subscriptions |
| **Backend API** | Render (Node.js / TypeScript) | All business logic, webhook handlers, AI orchestration |
| **Host Dashboard** | Flutter (Web + iOS + Android) | Property management, chat monitoring, escalation, system chat |
| **Guest Web App** | Next.js on Vercel | Browser-based guest chat (alternative to Telegram) |
| **Admin Dashboard** | Next.js on Vercel (same project, role-gated routes) | Internal team oversight, tenant management |
| **AI Engine** | Google Gemini (Vertex AI SDK, called from Render) | NLP, structuring, sentiment analysis, knowledge distillation |
| **Vector Database** | Pinecone | Semantic retrieval of Master JSON chunks (RAG) |
| **Scraping** | Apify (API calls from Render) | Airbnb listing extraction |
| **Guest Messaging** | Telegram Bot API (webhook to Render) | Primary guest communication channel |
| **Host Alerts** | Telegram Bot API | Escalation alerts, quick responses |

### Architecture Diagram

```
                    ┌─────────────────────────────────────────┐
                    │              SUPABASE                    │
                    │  ┌──────────┐ ┌────────┐ ┌───────────┐ │
                    │  │PostgreSQL│ │Storage │ │Auth + RLS │ │
                    │  │(all data)│ │(files) │ │(hosts,    │ │
                    │  │          │ │        │ │ guests,   │ │
                    │  │          │ │        │ │ admins)   │ │
                    │  └────┬─────┘ └───┬────┘ └─────┬─────┘ │
                    │       │Realtime   │            │       │
                    └───────┼───────────┼────────────┼───────┘
                            │           │            │
           ┌────────────────┼───────────┼────────────┼────────────────┐
           │                │           │            │                │
           ▼                ▼           ▼            ▼                ▼
  ┌──────────────┐  ┌──────────┐ ┌──────────┐ ┌──────────────┐ ┌──────────┐
  │   RENDER     │  │ FLUTTER  │ │ VERCEL   │ │   VERCEL     │ │ PINECONE │
  │   Backend    │  │  Host    │ │  Guest   │ │   Admin      │ │ (Vectors)│
  │              │  │Dashboard │ │ Web App  │ │  Dashboard   │ │          │
  │ - Webhooks   │  │(Web/iOS/ │ │(Next.js) │ │  (Next.js)   │ │ Master   │
  │ - AI logic   │  │ Android) │ │          │ │              │ │ JSON     │
  │ - Pipeline   │  │          │ │          │ │              │ │ chunks   │
  │ - Routing    │  │          │ │          │ │              │ │          │
  └──────┬───────┘  └──────────┘ └──────────┘ └──────────────┘ └──────────┘
         │
  ┌──────┴──────────────────┐
  │                         │
  ▼                         ▼
┌──────────────┐    ┌──────────────┐
│  Telegram    │    │   Apify      │
│  Bot API     │    │  (Scraper)   │
│              │    │              │
│ - Guest msgs │    │              │
│ - Host alerts│    │              │
└──────────────┘    └──────────────┘
```

---

## 3. DATABASE SCHEMA (Supabase / PostgreSQL)

### 3.1 `properties`

| Column | Type | Description |
|---|---|---|
| `id` | uuid (PK) | Property identifier |
| `created_at` | timestamptz | Record creation time |
| `owner_id` | uuid (FK → hosts) | The host who owns this property |
| `name` | text | Property display name (e.g., "Casa Fernanda") |
| `airbnb_url` | text | Source listing URL for the scraper |
| `status` | text | Pipeline state: `Ready_to_Build` / `Scraped` / `Ingested` / `Waiting` / `Resolved` / `Trained` |
| `master_json` | jsonb | **SINGLE SOURCE OF TRUTH.** Merged structured property knowledge. Also vectorized into Pinecone. |
| `scraped_markdown` | text | Output from Scraper (Apify → Gemini → Markdown) |
| `ingested_markdown` | text | Output from Ingestor (uploads → Gemini → Markdown) |
| `conflict_status` | text | Conflict detection result |
| `conflict_report` | jsonb | Detailed conflict analysis from Gemini |
| `resolution_history` | json | Log of conflict resolutions |
| `resolution_history_json` | json | Structured resolution history |
| `host_id` | uuid (FK → hosts) | FK to hosts table |

### 3.2 `hosts`

| Column | Type | Description |
|---|---|---|
| `id` | uuid (PK) | Host identifier (matches Supabase Auth UID) |
| `name` | text | Host display name |
| `telegram_chat_id` | text | Host's Telegram chat ID for alerts + Live Tunnel |
| `whatsapp_number` | text | Host's WhatsApp (V2) |
| `email` | text | Host's email |
| `created_at` | timestamptz | Record creation time |
| `TG_verification_code` | text | Telegram verification code for onboarding |
| `active_conversation_id` | text | **THE LOCK.** NULL = Lobby Mode. Non-null = locked to booking_id. |

### 3.3 `guests`

| Column | Type | Description |
|---|---|---|
| `id` | uuid (PK) | Guest identifier |
| `created_at` | timestamptz | Record creation time |
| `property_id` | uuid (FK → properties) | Associated property |
| `name` | text | Guest display name |
| `booking_code` | text | Unique code embedded in Magic Link |
| `contact_info` | jsonb | Flexible contact data |
| `thread_summary` | text | Running conversation summary |

### 3.4 `conversations`

| Column | Type | Description |
|---|---|---|
| `booking_id` | text (PK) | Unique booking identifier |
| `property_id` | uuid (FK → properties) | Associated property |
| `guest_name` | text | Denormalized guest name |
| `platform` | text | `telegram` / `web` (V1). `whatsapp` added in V2. |
| `ai_status` | text | AI handling status |
| `requires_attention` | bool | Dashboard flag |
| `last_message_at` | timestamptz | Most recent message |
| `created_at` | timestamptz | Conversation start |
| `check_out_date` | date | For "Expired Booking" validation |
| `preferred_language` | text | Guest language |
| `is_escalated` | bool | **ESCALATION FLAG.** TRUE = AI bypassed. |
| `escalation_reason` | text | Why escalation triggered |
| `telegram_chat_id` | text | Guest's Telegram chat ID |

### 3.5 `messages`

| Column | Type | Description |
|---|---|---|
| `id` | uuid (PK) | Message identifier |
| `booking_id` | text (FK → conversations) | Links to conversation |
| `sender_type` | text | `guest` / `ai` / `host` / `system` |
| `content` | text | Message body |
| `media_url` | text | Attached media URL |
| `sentiment` | text | Gemini sentiment result |
| `status` | text | `unread` / `sent` / `delivered` / `read` |
| `created_at` | timestamptz | Creation time |
| `is_escalated_interaction` | bool | TRUE if during escalation |
| `property_id` | uuid (FK → properties) | Denormalized |
| `resolution_status` | text | NULL or `'resolved'` (Batch Stamp) |
| `is_learned` | bool | TRUE if distilled into knowledge_base |

### 3.6 `knowledge_base`

| Column | Type | Description |
|---|---|---|
| `id` | uuid (PK) | Knowledge entry ID |
| `created_at` | timestamptz | When distilled |
| `property_id` | uuid (FK → properties) | Associated property |
| `problem_summary` | text | What went wrong |
| `solution_summary` | text | How human fixed it |
| `category` | text | Classification tag |
| `source_message_ids` | jsonb | Audit trail (message UUIDs) |
| `original_transcript` | jsonb | Raw conversation JSON |
| `is_verified` | bool | Default TRUE. Host can deny/modify via Dashboard. |

### 3.7 `conflicts`

| Column | Type | Description |
|---|---|---|
| `id` | uuid (PK) | Conflict ID |
| `created_at` | timestamptz | When detected |
| `property_id` | uuid (FK → properties) | Associated property |
| `status` | text | `pending` / `resolved` |
| `question` | text | Conflict phrased as question |
| `option_a` | text | First option (scraped data) |
| `option_b` | text | Second option (ingested data) |
| `resolution` | text | Host's chosen answer |

### 3.8 Row-Level Security (Multi-Tenant)

```sql
-- Hosts see only their own properties
CREATE POLICY "hosts_own_properties" ON properties
  FOR ALL USING (owner_id = auth.uid());

-- Hosts see only conversations for their properties
CREATE POLICY "hosts_own_conversations" ON conversations
  FOR ALL USING (
    property_id IN (SELECT id FROM properties WHERE owner_id = auth.uid())
  );

-- Hosts see only messages for their properties
CREATE POLICY "hosts_own_messages" ON messages
  FOR ALL USING (
    property_id IN (SELECT id FROM properties WHERE owner_id = auth.uid())
  );

-- Knowledge base scoped to host's properties
CREATE POLICY "hosts_own_knowledge" ON knowledge_base
  FOR ALL USING (
    property_id IN (SELECT id FROM properties WHERE owner_id = auth.uid())
  );

-- Conflicts scoped to host's properties
CREATE POLICY "hosts_own_conflicts" ON conflicts
  FOR ALL USING (
    property_id IN (SELECT id FROM properties WHERE owner_id = auth.uid())
  );

-- Admin team sees everything
CREATE POLICY "admin_full_access" ON properties
  FOR ALL USING (
    (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
  );
-- (Repeat admin policy for each table)
```

### 3.9 Entity Relationships

```
hosts (1) ──────────────── (N) properties
  │                              │
  │ active_conversation_id       ├──── (N) conflicts
  │ (The Lock)                   │
  │                              │
  ▼                              ▼
conversations ◄──── property_id ─┘
  │ booking_id (PK)
  │
  ├──── (N) messages
  │           │
  │           └── is_learned ──→ knowledge_base
  │
  └──── guests (via property_id + booking_code)
```

---

## 4. RENDER API ENDPOINTS (Complete V1 Surface)

All backend logic lives in a single Render Node.js/TypeScript service.

### 4.1 Data Pipeline Endpoints

| Method | Endpoint | Purpose | Trigger |
|---|---|---|---|
| POST | `/api/pipeline/scrape` | Scrape Airbnb URL → structure → save | Dashboard: "Add Property" |
| POST | `/api/pipeline/ingest` | Process uploaded file → structure → save | Dashboard: file upload |
| POST | `/api/pipeline/merge` | Compare scraped + ingested → merge or flag conflicts | Auto-triggered after ingest |
| POST | `/api/pipeline/resolve` | Apply host's conflict resolutions → final Master JSON | Dashboard: questionnaire submit |
| POST | `/api/pipeline/vectorize` | Chunk Master JSON → embed → upsert to Pinecone | Auto-triggered after merge/resolve/system-chat |
| POST | `/api/system-chat` | Host-System Chat: update Master JSON via natural language or voice | Dashboard: system chat |

### 4.2 Messaging Endpoints

| Method | Endpoint | Purpose | Trigger |
|---|---|---|---|
| POST | `/api/links/generate` | Generate Magic Links (Telegram + Web) | Dashboard or automated message |
| POST | `/api/webhooks/telegram` | Receive incoming Telegram messages (guests + hosts) | Telegram Bot API |
| POST | `/api/messages/web-incoming` | Receive messages from Guest Web App | Guest Web App |
| POST | `/api/messages/send` | Send outbound message to guest (used internally) | Internal (after AI generation) |

### 4.3 Escalation Endpoints

| Method | Endpoint | Purpose | Trigger |
|---|---|---|---|
| POST | `/api/escalation/connect` | Host connects to guest (sets The Lock) | Telegram callback / Dashboard button |
| POST | `/api/escalation/resolve` | Kill Switch — atomic close + trigger Learning Loop | Telegram callback / Dashboard button |
| POST | `/api/escalation/ghost-send` | Ghost Mode: host sends message as "Alfred" | Dashboard |

### 4.4 Dashboard API Endpoints

| Method | Endpoint | Purpose |
|---|---|---|
| GET | `/api/properties` | List host's properties (RLS-filtered) |
| GET | `/api/properties/:id` | Property detail + master_json |
| GET | `/api/conversations` | List conversations (filterable by property, status, attention) |
| GET | `/api/conversations/:booking_id/messages` | Message history for a conversation |
| GET | `/api/knowledge-base` | List knowledge entries for host's properties |
| PATCH | `/api/knowledge-base/:id` | Confirm / deny / modify knowledge entry |
| GET | `/api/conflicts` | List pending conflicts |

### 4.5 Admin Endpoints

| Method | Endpoint | Purpose |
|---|---|---|
| GET | `/api/admin/overview` | System-wide stats (conversations, escalations, response times) |
| GET | `/api/admin/tenants` | All hosts + properties + usage |
| GET | `/api/admin/conversations` | Global conversation monitor |
| GET | `/api/admin/knowledge-base` | Cross-property knowledge view |

---

## 5. MODULE 1: THE DATA PIPELINE

### 5.1 The Scraper

**Endpoint:** `POST /api/pipeline/scrape`
**Input:** `{ property_id, airbnb_url }`
**Status transition:** `Ready_to_Build` → `Scraped`

```
FUNCTION scrape(property_id, airbnb_url):

  // 1. Trigger Apify
  run = CALL Apify.runActor("airbnb-scraper", { url: airbnb_url })
  raw_data = CALL Apify.getResults(run.id)

  // 2. Structure with Gemini
  markdown = CALL Gemini({
    task: "Structure this raw Airbnb listing data into clean Markdown.
           Sections: Property Overview, Amenities, House Rules,
           Check-in/Check-out, Location, Photos Description.",
    input: raw_data
  })

  // 3. Save to Supabase
  UPDATE properties SET
    scraped_markdown = markdown,
    status = 'Scraped'
  WHERE id = property_id

  RETURN { success: true, status: 'Scraped' }
```

### 5.2 The Ingestor

**Endpoint:** `POST /api/pipeline/ingest`
**Input:** `{ property_id, file_url, file_type }`
**Status transition:** `Scraped` → `Ingested`

```
FUNCTION ingest(property_id, file_url, file_type):

  // 1. Download file from Supabase Storage
  file = DOWNLOAD file_url

  // 2. Process by type
  IF file_type == 'pdf':
    text = EXTRACT_TEXT(file)
  ELSE IF file_type IN ('png', 'jpg', 'jpeg'):
    text = CALL Gemini.vision("Extract all text and information from this image", file)
  ELSE IF file_type IN ('mp3', 'ogg', 'wav', 'm4a'):
    text = CALL Gemini("Transcribe this audio", file)
  ELSE:
    text = READ_AS_TEXT(file)

  // 3. Structure with Gemini
  markdown = CALL Gemini({
    task: "Structure this property information into Markdown.
           Extract: WiFi passwords, access codes, house rules,
           check-in instructions, emergency contacts, amenity details.",
    input: text
  })

  // 4. Save (append to existing ingested_markdown if multiple files)
  existing = SELECT ingested_markdown FROM properties WHERE id = property_id
  combined = existing + "\n\n---\n\n" + markdown

  UPDATE properties SET
    ingested_markdown = combined,
    status = 'Ingested'
  WHERE id = property_id

  // 5. Auto-trigger merge
  CALL merge(property_id)

  RETURN { success: true, status: 'Ingested' }
```

### 5.3 The Merger & Conflict Detector

**Endpoint:** `POST /api/pipeline/merge`
**Input:** `{ property_id }`
**Status transition:** `Ingested` → `Trained` or `Waiting`

```
FUNCTION merge(property_id):

  // 1. Fetch both sources
  property = SELECT scraped_markdown, ingested_markdown FROM properties
    WHERE id = property_id

  // 2. Gemini merge + conflict detection
  result = CALL Gemini({
    task: "You are merging two data sources for a vacation rental property.
           Source A (Scraped from Airbnb): {scraped_markdown}
           Source B (Host-provided documents): {ingested_markdown}

           RULES:
           1. If both sources agree, merge into a single entry.
           2. If sources conflict (e.g., different check-in times), flag as conflict.
           3. Host-provided data (Source B) is generally more authoritative,
              but flag it anyway so the host can confirm.

           OUTPUT FORMAT (Strict JSON):
           {
             'master_json': { ... complete merged property data ... },
             'has_conflicts': true/false,
             'conflicts': [
               {
                 'question': 'Check-in time: listing says 2pm, your PDF says 3pm. Which is correct?',
                 'option_a': '2:00 PM (from Airbnb listing)',
                 'option_b': '3:00 PM (from your uploaded PDF)',
                 'field_path': 'check_in.time'
               }
             ]
           }",
    input: { scraped: property.scraped_markdown, ingested: property.ingested_markdown }
  })

  // 3. Route based on conflicts
  IF result.has_conflicts == FALSE:
    // No conflicts — save Master JSON and vectorize
    UPDATE properties SET
      master_json = result.master_json,
      status = 'Trained',
      conflict_status = 'none'
    WHERE id = property_id

    CALL vectorize(property_id)

  ELSE:
    // Conflicts found — save report and create conflict records
    UPDATE properties SET
      master_json = result.master_json,  // Save partial merge
      status = 'Waiting',
      conflict_status = 'pending',
      conflict_report = result.conflicts
    WHERE id = property_id

    FOR EACH conflict IN result.conflicts:
      INSERT INTO conflicts {
        property_id: property_id,
        status: 'pending',
        question: conflict.question,
        option_a: conflict.option_a,
        option_b: conflict.option_b
      }

  RETURN { success: true, has_conflicts: result.has_conflicts }
```

### 5.4 The Resolver

**Endpoint:** `POST /api/pipeline/resolve`
**Input:** `{ property_id, resolutions: [{ conflict_id, chosen: 'a' | 'b' }] }`

```
FUNCTION resolve(property_id, resolutions):

  // 1. Fetch current data
  property = SELECT * FROM properties WHERE id = property_id
  conflicts = SELECT * FROM conflicts WHERE property_id = property_id AND status = 'pending'

  // 2. Apply resolutions
  FOR EACH resolution IN resolutions:
    conflict = FIND conflict WHERE id = resolution.conflict_id
    UPDATE conflicts SET
      status = 'resolved',
      resolution = IF resolution.chosen == 'a' THEN conflict.option_a ELSE conflict.option_b
    WHERE id = conflict.id

  // 3. Re-merge with resolutions
  resolved_conflicts = SELECT * FROM conflicts WHERE property_id = property_id AND status = 'resolved'

  final_json = CALL Gemini({
    task: "Re-merge this property data applying these conflict resolutions.",
    input: {
      base_master_json: property.master_json,
      resolutions: resolved_conflicts
    }
  })

  // 4. Save final Master JSON
  UPDATE properties SET
    master_json = final_json,
    status = 'Trained',
    conflict_status = 'resolved',
    resolution_history_json = APPEND(property.resolution_history_json, resolutions)
  WHERE id = property_id

  // 5. Vectorize
  CALL vectorize(property_id)

  RETURN { success: true, status: 'Trained' }
```

### 5.5 Pinecone Vectorization

**Endpoint:** `POST /api/pipeline/vectorize`
**Input:** `{ property_id }`

```
FUNCTION vectorize(property_id):

  // 1. Fetch Master JSON
  property = SELECT master_json, name FROM properties WHERE id = property_id

  // 2. Chunk into semantic sections
  chunks = CALL Gemini({
    task: "Split this property data into semantic chunks suitable for retrieval.
           Each chunk should be a self-contained topic (e.g., 'WiFi & Connectivity',
           'Check-in Instructions', 'House Rules', 'Amenities', 'Neighborhood',
           'Emergency Contacts', 'Parking', 'Kitchen', etc.).
           Return as JSON array of { section: string, content: string }.",
    input: property.master_json
  })

  // 3. Generate embeddings
  FOR EACH chunk IN chunks:
    embedding = CALL Gemini.embed(chunk.content)

    // 4. Upsert to Pinecone
    CALL Pinecone.upsert({
      namespace: property_id,
      vectors: [{
        id: property_id + "_" + chunk.section,
        values: embedding,
        metadata: {
          property_id: property_id,
          property_name: property.name,
          section: chunk.section,
          content: chunk.content
        }
      }]
    })

  // 5. Delete any old vectors not in current chunk set
  // (handles cases where sections were removed or renamed)
  CALL Pinecone.deleteByFilter({
    namespace: property_id,
    filter: { section: { $nin: chunks.map(c => c.section) } }
  })

  RETURN { success: true, chunks_count: chunks.length }
```

### 5.6 Host-System Chat

**Endpoint:** `POST /api/system-chat`
**Input:** `{ property_id, message, media_url? }`

```
FUNCTION systemChat(property_id, message, media_url):

  // 1. If voice note, transcribe first
  IF media_url AND is_audio(media_url):
    message = CALL Gemini("Transcribe this audio", DOWNLOAD(media_url))

  // 2. Fetch current Master JSON
  property = SELECT master_json FROM properties WHERE id = property_id

  // 3. Ask Gemini to identify and apply the update
  result = CALL Gemini({
    task: "You are an assistant managing a vacation rental property's knowledge base.
           The host wants to update the property information.
           Current Master JSON: {master_json}
           Host's instruction: {message}

           Identify what field(s) to update, apply the change, and return:
           {
             'updated_master_json': { ... complete updated JSON ... },
             'change_summary': 'Updated WiFi password from OldPass to Beach2024',
             'fields_changed': ['connectivity.wifi_password']
           }",
    input: { master_json: property.master_json, message: message }
  })

  // 4. Save updated Master JSON
  UPDATE properties SET master_json = result.updated_master_json
    WHERE id = property_id

  // 5. Re-vectorize
  CALL vectorize(property_id)

  RETURN {
    success: true,
    change_summary: result.change_summary,
    response: "Got it! I've updated: " + result.change_summary
  }
```

---

## 6. MODULE 2: THE MESSAGING ENGINE

### 6.1 The Trojan Horse Strategy

- **Trigger:** 5 minutes after booking confirmation.
- **Mechanism:** Airbnb Automated Message (native Airbnb feature, configured manually for V1) sends the guest a unique Magic Link.
- **Physical Backup:** Printable QR Code in the house manual.
- **V1 Channels:** Telegram + Guest Web App.

### 6.2 Link Formats

```
Telegram:  t.me/AlfredBot?start=Booking_123
Web App:   app.yourdomain.com/chat?booking=Booking_123
```

### 6.3 The Link Generator

**Endpoint:** `POST /api/links/generate`
**Input:** `{ type: 'guest' | 'host', booking_id?, host_id? }`

```
FUNCTION generateLinks(type, booking_id, host_id):

  IF type == 'guest':
    conversation = SELECT * FROM conversations WHERE booking_id = booking_id
    IF NOT conversation: RETURN { error: 'Booking not found' }

    RETURN {
      telegram_url: "https://t.me/AlfredBot?start=" + booking_id,
      web_url: "https://app.yourdomain.com/chat?booking=" + booking_id
    }

  IF type == 'host':
    host = SELECT * FROM hosts WHERE id = host_id
    IF NOT host.TG_verification_code:
      code = GENERATE_RANDOM_CODE(6)
      UPDATE hosts SET TG_verification_code = code WHERE id = host_id
    ELSE:
      code = host.TG_verification_code

    RETURN {
      telegram_url: "https://t.me/AlfredBot?start=host_" + code
    }
```

### 6.4 Telegram Webhook Handler (Main Message Router)

**Endpoint:** `POST /api/webhooks/telegram`

This is the central routing function. Every Telegram message hits this endpoint.

```
FUNCTION handleTelegramWebhook(update):

  chat_id = update.message.chat.id
  text = update.message.text
  callback = update.callback_query  // For inline button clicks

  // ─── HANDLE BUTTON CALLBACKS ───
  IF callback:
    IF callback.data STARTS WITH "select_":
      booking_id = EXTRACT booking_id from callback.data
      CALL connectHost(booking_id, chat_id)
      RETURN

    IF callback.data STARTS WITH "resolved_":
      booking_id = EXTRACT booking_id from callback.data
      CALL resolveEscalation(booking_id)
      RETURN

  // ─── HANDLE /start COMMAND (Magic Link activation) ───
  IF text STARTS WITH "/start":
    payload = EXTRACT text after "/start "

    // Host activation
    IF payload STARTS WITH "host_":
      code = EXTRACT code after "host_"
      host = SELECT * FROM hosts WHERE TG_verification_code = code
      IF host:
        UPDATE hosts SET telegram_chat_id = chat_id WHERE id = host.id
        SEND "✅ Connected! You'll receive alerts here." TO chat_id
        RETURN
      ELSE:
        SEND "Invalid verification code." TO chat_id
        RETURN

    // Guest activation — Path D check (Incomplete Start)
    IF payload IS EMPTY:
      SEND "Por favor usa el enlace completo de tu mensaje de Airbnb. No escribas /start manualmente." TO chat_id
      RETURN

    // Guest activation — look up booking
    booking_id = payload
    conversation = SELECT * FROM conversations WHERE booking_id = booking_id

    IF NOT conversation:
      SEND "No te reconozco. Por favor usa el enlace que recibiste en tu mensaje de Airbnb." TO chat_id
      RETURN

    // Path E check (Expired)
    IF conversation.check_out_date < (TODAY - 1):
      host = GET host for this property
      SEND "Tu estancia ha terminado. He enviado tu mensaje a " + host.name + "." TO chat_id
      FORWARD text TO host.telegram_chat_id
      RETURN

    // Valid activation — store chat ID and welcome
    UPDATE conversations SET
      telegram_chat_id = chat_id,
      platform = 'telegram'
    WHERE booking_id = booking_id

    property = SELECT name FROM properties WHERE id = conversation.property_id
    SEND "Welcome to " + property.name + ", " + conversation.guest_name + "! 🌴 I'm Alfred. I have your check-in details ready. What would you like to know first?" TO chat_id
    RETURN

  // ─── HANDLE REGULAR MESSAGES ───

  // Check if this is a HOST sending a message
  host = SELECT * FROM hosts WHERE telegram_chat_id = chat_id
  IF host AND host.active_conversation_id IS NOT NULL:
    CALL routeHostToGuest(host, text)
    RETURN

  // Check if this is a GUEST with an active conversation
  conversation = SELECT * FROM conversations WHERE telegram_chat_id = chat_id
  IF NOT conversation:
    // Path C: "The Stranger"
    SEND "No te reconozco. Por favor usa el enlace que recibiste en tu mensaje de Airbnb." TO chat_id
    RETURN  // Do NOT log

  // Path E recheck (Expired)
  IF conversation.check_out_date < (TODAY - 1):
    host = GET host for this property
    SEND "Tu estancia ha terminado. He enviado tu mensaje a " + host.name + "." TO chat_id
    FORWARD text TO host.telegram_chat_id
    RETURN

  // Valid guest message — process it
  CALL handleGuestMessage(conversation, text, update.message.media_url)
```

### 6.5 Guest Web App Message Handler

**Endpoint:** `POST /api/messages/web-incoming`
**Input:** `{ booking_id, content, session_token }`

```
FUNCTION handleWebMessage(booking_id, content, session_token):

  // 1. Validate session
  conversation = SELECT * FROM conversations WHERE booking_id = booking_id
  IF NOT conversation: RETURN { error: 'Invalid booking' }

  // Path E check
  IF conversation.check_out_date < (TODAY - 1):
    RETURN { error: 'expired', message: 'Tu estancia ha terminado.' }

  // 2. Update platform if first web message
  IF conversation.platform IS NULL:
    UPDATE conversations SET platform = 'web' WHERE booking_id = booking_id

  // 3. Route to same handler as Telegram
  CALL handleGuestMessage(conversation, content, null)
```

### 6.6 Core Message Processing (Shared by Telegram + Web)

```
FUNCTION handleGuestMessage(conversation, text, media_url):

  // ─── STEP 1: INPUT LOG (Immediate) ───
  new_message = INSERT INTO messages {
    booking_id: conversation.booking_id,
    sender_type: 'guest',
    content: text,
    media_url: media_url,
    status: 'unread',
    property_id: conversation.property_id,
    is_escalated_interaction: conversation.is_escalated,
    created_at: NOW()
  }

  // ─── STEP 2: CHECK ESCALATION STATE ───
  IF conversation.is_escalated == TRUE:
    CALL routeGuestToHost(conversation, text, new_message.id)
    RETURN  // Do NOT generate AI response

  // ─── STEP 3: SENTIMENT ANALYSIS ───
  sentiment = CALL Gemini({
    task: "Classify this guest message sentiment.
           Return ONE of: positive, neutral, negative, hostility, emergency",
    input: text
  })
  UPDATE messages SET sentiment = sentiment WHERE id = new_message.id

  IF sentiment IN ('hostility', 'emergency'):
    CALL triggerEscalation(conversation, sentiment)
    // Continue to generate a holding response

  // ─── STEP 4: RAG RETRIEVAL (Pinecone) ───
  question_embedding = CALL Gemini.embed(text)
  relevant_chunks = CALL Pinecone.query({
    namespace: conversation.property_id,
    vector: question_embedding,
    topK: 5,
    includeMetadata: true
  })

  // ─── STEP 5: KNOWLEDGE BASE RETRIEVAL ───
  learned_lessons = SELECT * FROM knowledge_base
    WHERE property_id = conversation.property_id
    AND is_verified = TRUE

  // ─── STEP 6: CONVERSATION HISTORY ───
  recent_messages = SELECT * FROM messages
    WHERE booking_id = conversation.booking_id
    ORDER BY created_at DESC
    LIMIT 20

  // ─── STEP 7: GENERATE AI RESPONSE ───
  ai_response = CALL Gemini({
    system: "You are Alfred, a helpful vacation rental assistant for " + property.name + ".
             You are friendly, concise, and always helpful.
             Respond in the guest's language: " + conversation.preferred_language + ".
             Use ONLY the provided property information and knowledge base to answer.
             If you don't know something, say so and offer to connect the guest with the host.",
    context: {
      property_info: relevant_chunks.map(c => c.metadata.content).join("\n\n"),
      learned_knowledge: learned_lessons,
      conversation_history: recent_messages
    },
    input: text
  })

  // ─── STEP 8: OUTPUT LOG ───
  INSERT INTO messages {
    booking_id: conversation.booking_id,
    sender_type: 'ai',
    content: ai_response,
    status: 'sent',
    property_id: conversation.property_id,
    created_at: NOW()
  }

  // ─── STEP 9: SEND TO GUEST ───
  IF conversation.platform == 'telegram':
    SEND ai_response TO conversation.telegram_chat_id VIA Telegram API
  // Web App receives response via Supabase Realtime subscription (no explicit send needed)

  // ─── STEP 10: UPDATE CONVERSATION ───
  UPDATE conversations SET
    last_message_at = NOW(),
    ai_status = 'responded'
  WHERE booking_id = conversation.booking_id
```

---

## 7. MODULE 3: THE LIVE TUNNEL

### 7.1 The Lock

| State | `hosts.active_conversation_id` | Meaning |
|---|---|---|
| Lobby Mode | `NULL` | Receiving alerts, not chatting |
| Locked | `{booking_id}` | Connected to specific guest |

Single lock per host. Overwrite on new connection. Zero cross-talk.

### 7.2 Intervention Modes

**Ghost Mode:** Host types in Dashboard → sent as "Alfred" → `sender_type = 'ai'` → guest unaware.

**Handover:** Host clicks "Take Over" → system message to guest → `is_escalated = TRUE` → `active_conversation_id = booking_id` → stays human-to-human until "Mark Resolved."

### 7.3 Routing

```
FUNCTION routeGuestToHost(conversation, text, message_id):
  // Pre-condition: conversation.is_escalated == TRUE

  property = SELECT * FROM properties WHERE id = conversation.property_id
  host = SELECT * FROM hosts WHERE id = property.owner_id

  IF host.active_conversation_id != conversation.booking_id:
    // Host hasn't connected yet — message queues in Dashboard
    RETURN

  // Forward to Host
  formatted = "[Guest] from [" + property.name + "]: " + text
  SEND formatted TO host.telegram_chat_id VIA Telegram API
    WITH inline_keyboard: [{ text: "✅ Mark Resolved", callback_data: "resolved_" + conversation.booking_id }]


FUNCTION routeHostToGuest(host, text):
  conversation = SELECT * FROM conversations
    WHERE booking_id = host.active_conversation_id

  // Log with escalation flag
  INSERT INTO messages {
    booking_id: conversation.booking_id,
    sender_type: 'host',
    content: text,
    is_escalated_interaction: TRUE,
    property_id: conversation.property_id,
    created_at: NOW()
  }

  // Forward to Guest (raw text, no prefix)
  IF conversation.platform == 'telegram':
    SEND text TO conversation.telegram_chat_id VIA Telegram API
  // Web guests receive via Supabase Realtime


FUNCTION ghostSend(property_id, booking_id, text):
  // Ghost Mode — appears as AI to guest
  conversation = SELECT * FROM conversations WHERE booking_id = booking_id

  INSERT INTO messages {
    booking_id: booking_id,
    sender_type: 'ai',  // Appears as Alfred
    content: text,
    property_id: property_id,
    created_at: NOW()
  }

  IF conversation.platform == 'telegram':
    SEND text TO conversation.telegram_chat_id VIA Telegram API
```

### 7.4 Escalation Trigger

```
FUNCTION triggerEscalation(conversation, reason):
  UPDATE conversations SET
    is_escalated = TRUE,
    escalation_reason = reason,
    requires_attention = TRUE
  WHERE booking_id = conversation.booking_id

  property = SELECT name FROM properties WHERE id = conversation.property_id
  host = SELECT * FROM hosts WHERE id = property.owner_id

  alert = "🚨 ALFRED ESCALATION ALERT\n━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        + conversation.guest_name + " at " + property.name + "\n"
        + "Reason: " + reason

  SEND alert TO host.telegram_chat_id VIA Telegram API
    WITH inline_keyboard: [
      { text: "🔗 Connect", callback_data: "select_" + conversation.booking_id },
      { text: "✅ Mark Resolved", callback_data: "resolved_" + conversation.booking_id }
    ]
  // Also push to Dashboard via Supabase Realtime (requires_attention = TRUE triggers UI)
```

### 7.5 The Kill Switch

```
FUNCTION resolveEscalation(booking_id):
  conversation = SELECT * FROM conversations WHERE booking_id = booking_id
  property = SELECT * FROM properties WHERE id = conversation.property_id
  host = SELECT * FROM hosts WHERE id = property.owner_id

  // ATOMIC SEQUENCE

  // 1. Close escalation
  UPDATE conversations SET
    is_escalated = FALSE,
    requires_attention = FALSE
  WHERE booking_id = booking_id

  // 2. Free host
  UPDATE hosts SET active_conversation_id = NULL WHERE id = host.id

  // 3. Notify guest
  system_msg = "Issue Resolved. Alfred has resumed control."
  INSERT INTO messages {
    booking_id: booking_id,
    sender_type: 'system',
    content: system_msg,
    property_id: conversation.property_id,
    created_at: NOW()
  }
  IF conversation.platform == 'telegram':
    SEND system_msg TO conversation.telegram_chat_id

  // 4. Trigger Learning Loop
  CALL learningLoop(booking_id)
```

---

## 8. MODULE 4: THE LEARNING LOOP

```
FUNCTION learningLoop(booking_id):

  // ─── STEP 1: BATCH STAMP ───
  stamped_count = UPDATE messages SET resolution_status = 'resolved'
    WHERE booking_id = booking_id
    AND is_escalated_interaction = TRUE
    AND resolution_status IS NULL
    RETURNING count(*)

  IF stamped_count == 0:
    RETURN  // Host resolved without chatting — nothing to learn

  // ─── STEP 2: DATA RETRIEVAL ───
  transcript = SELECT * FROM messages
    WHERE booking_id = booking_id
    AND is_escalated_interaction = TRUE
    AND resolution_status = 'resolved'
    ORDER BY created_at ASC

  // ─── STEP 3: AI DISTILLATION ───
  distilled = CALL Gemini({
    role: "Expert Data Analyst",
    task: "Analyze this escalated conversation between a vacation rental
           guest and the property host. Identify:
           1. The core root cause problem the guest experienced.
           2. The successful solution the host provided.
           Discard ALL phatic communication (greetings, apologies, filler).
           Extract only actionable knowledge.",
    output_format: {
      problem_summary: "string",
      solution_summary: "string",
      category: "one of: connectivity, access, appliances, amenities,
                 cleaning, noise, safety, checkout, other"
    },
    input: transcript
  })

  // ─── STEP 4: KNOWLEDGE PERSISTENCE ───
  conversation = SELECT property_id FROM conversations WHERE booking_id = booking_id
  message_ids = transcript.map(m => m.id)

  INSERT INTO knowledge_base {
    property_id: conversation.property_id,
    problem_summary: distilled.problem_summary,
    solution_summary: distilled.solution_summary,
    category: distilled.category,
    source_message_ids: message_ids,
    original_transcript: transcript,
    is_verified: TRUE
  }

  // ─── STEP 5: MARK AS LEARNED ───
  UPDATE messages SET is_learned = TRUE
    WHERE id IN (message_ids)
```

**Host Review (Dashboard):**

| Action | Result |
|---|---|
| Confirm | `is_verified` stays TRUE |
| Deny | `is_verified = FALSE` — Alfred stops using this |
| Modify + Confirm | Host edits text → `is_verified = TRUE` with updated content |

---

## 9. INTERFACES

### 9.1 Host Dashboard (Flutter)

| Screen | Key Features |
|---|---|
| **Properties List** | All properties with color-coded status badges. Green = Trained, Red = Waiting (conflicts). |
| **Property Detail** | Master JSON viewer, pipeline status, file upload, conflict questionnaire |
| **Conversations** | All active chats sorted by `last_message_at`. Orange badge = `requires_attention`. |
| **Chat View** | Real-time messages. Ghost Mode button. Take Over button. Mark Resolved button. |
| **System Chat** | Chat with Alfred System. Text + voice notes. Updates Master JSON in real-time. |
| **Escalation Alerts** | List of `requires_attention = TRUE` conversations with Connect / Resolve buttons. |
| **Lessons Learned** | Knowledge base entries. Confirm / Deny / Modify controls. |
| **Settings** | Profile, notifications, Telegram connection. |

### 9.2 Guest Web App (Next.js on Vercel)

| Feature | Detail |
|---|---|
| **URL** | `app.yourdomain.com/chat?booking=Booking_123` |
| **Auth** | Anonymous Supabase Auth, session secured by booking code |
| **Chat** | Real-time via Supabase Realtime subscriptions |
| **Media** | Photo upload for reporting issues |
| **Language** | Matches `preferred_language` |

### 9.3 Admin Dashboard (Next.js on Vercel)

| Screen | Purpose |
|---|---|
| **Overview** | Active conversations, escalation rate, avg response time, knowledge growth |
| **Tenants** | All hosts + properties + usage stats |
| **Conversations** | Global monitor with filters (property, host, escalation, date) |
| **Knowledge Base** | Cross-property view. Spot patterns. |
| **Team** | Manage admin users + roles (admin / operator / viewer) |

---

# PART II: BUILD ORDER (Dependency Chain)

---

## Build Dependency Map

```
PHASE 0: Foundation
    │
    ▼
PHASE 1: Data Pipeline + Pinecone ─────────────────────┐
    │                                                   │
    ▼                                                   │
PHASE 2: Messaging Core (Telegram) ◄────── requires ────┘
    │                                    Master JSON +
    │                                    Pinecone vectors
    ▼
PHASE 3: Guest Web App ◄────── requires Messaging Core backend
    │
    ▼
PHASE 4: Escalation + Live Tunnel ◄────── requires Message Router
    │
    ▼
PHASE 5: Learning Loop ◄────── requires Escalation (Kill Switch trigger)
    │
    ▼
PHASE 6: Host-System Chat + Dashboard Polish ◄────── can run after Phase 1,
    │                                                 but benefits from full flow
    ▼
PHASE 7: Admin Dashboard + Launch Prep ◄────── requires all above
```

**Critical path:** 0 → 1 → 2 → 4 → 5 (each phase blocks the next)
**Parallel paths:** Phase 3 (Guest Web App) can start after Phase 2 begins. Phase 6 can start after Phase 1.

---

## PHASE 0: FOUNDATION

**Goal:** Infrastructure setup. No features.
**Duration:** 1 week
**Blocks:** Everything

| # | Task | Detail | Test |
|---|---|---|---|
| 0.1 | Supabase project | Create project on supabase.com | Can connect from local machine |
| 0.2 | Apply schema | Run SQL to create all 7 tables (Section 3) | Tables visible in Supabase dashboard |
| 0.3 | Apply RLS policies | Run SQL for all policies (Section 3.8) | Query as test host → only sees own data |
| 0.4 | Supabase Auth | Enable email/password + Google OAuth. Create test host account. Set up admin role claim. | Can log in as host. Can log in as admin. |
| 0.5 | Render project | Initialize Node.js/TypeScript project. Install: `@supabase/supabase-js`, `express`, `@google-cloud/vertexai`, `@pinecone-database/pinecone`. Deploy. | Health check endpoint returns 200 |
| 0.6 | Environment variables | Set all API keys in Render: Supabase URL + anon key + service key, Gemini API key, Pinecone API key, Telegram Bot Token | Render can connect to Supabase, Gemini, Pinecone |
| 0.7 | Vercel project | Initialize Next.js project. Configure custom domain. Deploy. | Landing page loads at yourdomain.com |
| 0.8 | Flutter project | Initialize Flutter project. Add `supabase_flutter` package. Configure for web + iOS + Android. | Can authenticate test host via Supabase Auth |
| 0.9 | Pinecone setup | Create index (dimension matching Gemini embedding model). | Can upsert and query a test vector |
| 0.10 | Telegram Bot | Create bot via @BotFather. Set webhook URL to Render endpoint. | Send /start to bot → Render receives webhook |
| 0.11 | Supabase Storage | Create bucket for property files (PDFs, images, audio). Set upload policies. | Can upload a test file from Flutter |

---

## PHASE 1: THE BRAIN (Data Pipeline + Pinecone)

**Goal:** Host can add a property and Alfred builds its brain.
**Duration:** 2 weeks
**Depends on:** Phase 0
**Blocks:** Phase 2 (Messaging needs Master JSON + vectors)

| # | Task | Detail | Test |
|---|---|---|---|
| 1.1 | `POST /api/pipeline/scrape` | Implement Section 5.1 | Add Airbnb URL → `scraped_markdown` in DB, `status = Scraped` |
| 1.2 | `POST /api/pipeline/ingest` | Implement Section 5.2. Handle PDF, image, audio. | Upload PDF → `ingested_markdown` in DB, `status = Ingested` |
| 1.3 | `POST /api/pipeline/merge` | Implement Section 5.3. Including conflict detection. | Trigger merge → either `master_json` saved OR conflicts created |
| 1.4 | `POST /api/pipeline/resolve` | Implement Section 5.4 | Submit resolutions → final `master_json`, conflicts resolved |
| 1.5 | `POST /api/pipeline/vectorize` | Implement Section 5.5 | After merge → vectors in Pinecone. Query "WiFi" → relevant chunk. |
| 1.6 | Flutter: Properties List screen | List properties with status badges (green/red) | Host sees test properties |
| 1.7 | Flutter: Add Property flow | Form for name + Airbnb URL → calls scrape endpoint | New property appears, scraping starts |
| 1.8 | Flutter: File Upload screen | Upload PDFs/images/audio → Supabase Storage → calls ingest | Files process, `ingested_markdown` appears |
| 1.9 | Flutter: Conflict Questionnaire | Show conflicts with option_a/option_b → submit resolutions | Conflicts resolve, Master JSON generated |

**Phase 1 deliverable:** A host can onboard a property completely. The brain exists and is vectorized. No guest communication yet.

---

## PHASE 2: MESSAGING CORE (Telegram)

**Goal:** Guests can chat with Alfred via Telegram. The core product.
**Duration:** 2-3 weeks
**Depends on:** Phase 1 (needs Master JSON + Pinecone vectors)
**Blocks:** Phase 4 (Escalation needs message router)

| # | Task | Detail | Test |
|---|---|---|---|
| 2.1 | `POST /api/links/generate` | Implement Section 6.3 (guest + host paths) | Generate link → valid Telegram deep link |
| 2.2 | `POST /api/webhooks/telegram` (skeleton) | Implement the /start handler + Path C/D/E checks (Section 6.4) | Click link → send /start → "Welcome" response. Try stranger → reject. Try expired → forward. |
| 2.3 | Core message handler | Implement `handleGuestMessage` (Section 6.6): input log, RAG retrieval, Gemini response, output log | Ask "What's the WiFi?" → correct answer using Pinecone + Gemini |
| 2.4 | Sentiment analysis | Add sentiment step to message handler | Send angry message → `sentiment = hostility` in DB |
| 2.5 | Double-Write verification | Verify both input + output logged correctly | Check `messages` table → 2 rows per exchange |
| 2.6 | Host Telegram onboarding | /start host_{code} flow | Host clicks verification link → `telegram_chat_id` stored |
| 2.7 | Flutter: Conversations List | Show all conversations sorted by `last_message_at` with attention badges | Host sees active conversations |
| 2.8 | Flutter: Chat View (read-only) | Real-time message feed via Supabase Realtime | Messages appear as guest chats |
| 2.9 | Create test bookings | Insert test `conversations` + `guests` rows for test properties | Magic Links work for test bookings |

**Phase 2 deliverable:** The core product works. Guests chat with Alfred via Telegram. Hosts monitor via Dashboard. This is demo-able.

---

## PHASE 3: GUEST WEB APP

**Goal:** Guests can also chat via browser (alternative to Telegram).
**Duration:** 1-2 weeks
**Depends on:** Phase 2 (uses same backend message handling)

| # | Task | Detail | Test |
|---|---|---|---|
| 3.1 | Guest chat page | Next.js page at `/chat?booking=Booking_123` | Page loads with chat interface |
| 3.2 | Anonymous auth | Supabase anonymous auth, session tied to booking code | Guest gets session, can send messages |
| 3.3 | `POST /api/messages/web-incoming` | Implement Section 6.5 | Send message from web → same response quality as Telegram |
| 3.4 | Supabase Realtime subscription | Chat updates in real-time without polling | AI response appears instantly in browser |
| 3.5 | Media upload | Guest can upload photos (for reporting issues) | Photo uploads to Supabase Storage, `media_url` saved |
| 3.6 | Path validations | Expired booking → error page. Invalid booking → error. | Test all error paths in browser |
| 3.7 | Responsive design | Mobile-first (most guests will use phone) | Works well on iPhone, Android, desktop |

**Phase 3 deliverable:** Full guest experience on both Telegram and Web.

---

## PHASE 4: ESCALATION + LIVE TUNNEL

**Goal:** When AI fails, hosts can seamlessly take over.
**Duration:** 2 weeks
**Depends on:** Phase 2 (needs message router for bi-directional routing)
**Blocks:** Phase 5 (Learning Loop triggered by Kill Switch)

| # | Task | Detail | Test |
|---|---|---|---|
| 4.1 | Escalation trigger | Integrate with sentiment analysis from Phase 2.4 → set `is_escalated`, send alert | Hostile message → Host receives 🚨 alert on Telegram + Dashboard |
| 4.2 | Connect callback handler | `select_{booking_id}` → sets `active_conversation_id` | Host clicks 🔗 Connect → Lock is set |
| 4.3 | Guest → Host routing | Implement `routeGuestToHost` (Section 7.3) | Guest sends message during escalation → Host receives on Telegram with [Guest] prefix |
| 4.4 | Host → Guest routing | Implement `routeHostToGuest` (Section 7.3) | Host replies → Guest receives raw text |
| 4.5 | Kill Switch | Implement `resolveEscalation` (Section 7.5): atomic close sequence | Host clicks ✅ → escalation closed, Lock freed, guest notified |
| 4.6 | Persistent Mark Resolved button | Every forwarded message includes ✅ button | Button appears on every forwarded message |
| 4.7 | Ghost Mode endpoint | `POST /api/escalation/ghost-send` (Section 7.3) | Host sends via Dashboard → guest sees as "Alfred" |
| 4.8 | Take Over button | Dashboard button → system message + sets Lock | Guest sees "Connecting you with [Host Name]" |
| 4.9 | Flutter: Escalation alerts screen | List `requires_attention = TRUE` with Connect / Resolve buttons | Alerts appear in real-time |
| 4.10 | Flutter: Chat View (interactive) | Add Ghost Mode, Take Over, Mark Resolved to Chat View | Full escalation flow from Dashboard |

**Phase 4 deliverable:** Complete Human-in-the-Loop system.

---

## PHASE 5: LEARNING LOOP

**Goal:** Alfred learns from every human intervention.
**Duration:** 1-2 weeks
**Depends on:** Phase 4 (Kill Switch triggers Learning Loop)

| # | Task | Detail | Test |
|---|---|---|---|
| 5.1 | Batch Stamp | Part of `resolveEscalation` — tag escalation messages as `resolved` | After Mark Resolved → messages tagged |
| 5.2 | Data retrieval | Fetch stamped messages chronologically | Correct transcript reconstructed |
| 5.3 | Distillation Agent | Gemini prompt → structured JSON output | Returns problem/solution/category |
| 5.4 | Knowledge persistence | Insert to `knowledge_base` with `is_verified = TRUE` | Row appears in DB |
| 5.5 | `is_learned` flag | Update source messages | Messages marked `is_learned = TRUE` |
| 5.6 | Verify AI uses knowledge | Next guest asks same question → AI includes learned knowledge | Response quality improved |
| 5.7 | Flutter: Lessons Learned screen | List knowledge entries with Confirm/Deny/Modify controls | Host can review and manage knowledge |
| 5.8 | `PATCH /api/knowledge-base/:id` | Confirm / Deny / Modify endpoint | Denied entry → AI stops using it |

**Phase 5 deliverable:** Self-improving AI. Core product loop complete.

---

## PHASE 6: HOST-SYSTEM CHAT + POLISH

**Goal:** Host can talk to Alfred to update the brain. Everything polished.
**Duration:** 2 weeks
**Depends on:** Phase 1 (needs Master JSON), best after Phase 5

| # | Task | Detail | Test |
|---|---|---|---|
| 6.1 | `POST /api/system-chat` | Implement Section 5.6 (text + voice) | "WiFi is now Beach2025" → master_json updated, Pinecone re-vectorized |
| 6.2 | Voice note handling | Audio upload → transcription → structured update | Record voice note → AI extracts info → master_json updated |
| 6.3 | Flutter: System Chat screen | Chat interface with Alfred System. Text + voice. | Full natural-language brain updates |
| 6.4 | Push notifications | Supabase Realtime → Flutter notifications for escalation alerts | Phone vibrates when escalation happens |
| 6.5 | Dashboard polish | Loading states, error handling, empty states, responsive design | Professional feel across all screens |
| 6.6 | Guest Web App polish | Error pages, offline handling, loading animations | Smooth guest experience |

**Phase 6 deliverable:** Polished host experience. Brain updates via conversation.

---

## PHASE 7: ADMIN DASHBOARD + LAUNCH PREP

**Goal:** Internal team can manage Alfred as a platform. Ready for test users.
**Duration:** 2 weeks
**Depends on:** All above

| # | Task | Detail | Test |
|---|---|---|---|
| 7.1 | Admin auth + roles | Supabase Auth with `role = 'admin'` claim. Role-gated Vercel routes. | Admin sees all. Operator sees limited. |
| 7.2 | System Overview page | Active conversations, escalation rate, response times, knowledge growth | Dashboard shows real metrics |
| 7.3 | Tenant management page | All hosts, their properties, conversation counts | Can browse all tenants |
| 7.4 | Global conversation monitor | All conversations with filters | Can filter by property, host, escalation status |
| 7.5 | Global knowledge base | Cross-property knowledge view | Can spot patterns |
| 7.6 | Team management | Invite team members, assign roles | Team member can log in with correct permissions |
| 7.7 | Landing page | Marketing page on Vercel | Looks professional |
| 7.8 | Onboarding flow | New host sign-up → create first property → guided setup | Smooth self-service onboarding |

**Phase 7 deliverable:** Launch-ready for 20-30 test properties.

---

## BUILD TIMELINE SUMMARY

| Phase | Name | Duration | Cumulative | Deliverable |
|---|---|---|---|---|
| 0 | Foundation | 1 week | 1 week | Infrastructure ready |
| 1 | The Brain | 2 weeks | 3 weeks | Properties onboarding works |
| 2 | Messaging Core | 2-3 weeks | 5-6 weeks | **First demo: guests can chat** |
| 3 | Guest Web App | 1-2 weeks | 6-8 weeks | Both channels working |
| 4 | Escalation | 2 weeks | 8-10 weeks | Human-in-the-Loop complete |
| 5 | Learning Loop | 1-2 weeks | 9-12 weeks | **Self-improving AI** |
| 6 | System Chat + Polish | 2 weeks | 11-14 weeks | Production quality |
| 7 | Admin + Launch | 2 weeks | 13-16 weeks | **Ready for test users** |

---

## GLOSSARY

| Term | Definition |
|---|---|
| **Master JSON** | `properties.master_json` — all structured property knowledge. Vectorized into Pinecone. |
| **Magic Link** | URL with embedded booking ID. Entry point to Alfred. |
| **Trojan Horse** | Strategy: use Airbnb's messaging to redirect guests to Alfred channels. |
| **The Lock** | `hosts.active_conversation_id`. Non-null = locked to a conversation. |
| **Live Tunnel** | Bi-directional Host ↔ Guest connection bypassing AI. |
| **Kill Switch** | ✅ Mark Resolved + atomic close sequence. |
| **Batch Stamp** | Retroactive `resolution_status = 'resolved'` on escalation messages. |
| **Ghost Mode** | Host sends via Dashboard, appears as Alfred. |
| **Handover** | Host takes over directly. Guest informed. Until Mark Resolved. |
| **Double-Write** | Every interaction = 2 message rows (input + output). |
| **RAG** | Retrieval-Augmented Generation. Question → Pinecone → relevant chunks → Gemini. |
| **Distillation Agent** | Gemini prompt extracting problem/solution from escalation transcripts. |

---

*Document v3.2 (Final) — V1 Product Specification*
*Tech stack: Supabase + Render + Vercel + Flutter + Pinecone + Gemini + Telegram*
