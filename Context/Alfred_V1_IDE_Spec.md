# ALFRED V1 — IDE BUILD SPEC
# Feed this document to Cursor / Claude Code when building each module.

---

## GLOBAL CONTEXT

You are building **Alfred**, a SaaS AI chatbot for vacation rental property management.
Stack: Supabase (PostgreSQL) + Render (Node.js/TypeScript) + Vercel (Next.js) + Flutter + Pinecone + Gemini + Telegram Bot API.

This document contains the COMPLETE specification. Build each phase in order.
Each phase has: file structure, interfaces, function signatures, implementation pseudocode, and test criteria.

---

# ENVIRONMENT VARIABLES

```env
# Supabase
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=eyJ...
SUPABASE_SERVICE_ROLE_KEY=eyJ...  # Server-side only, never expose to client

# Gemini (Vertex AI)
GOOGLE_PROJECT_ID=your-gcp-project
GOOGLE_LOCATION=us-central1
GEMINI_API_KEY=your-gemini-api-key

# Pinecone
PINECONE_API_KEY=pc-...
PINECONE_INDEX=alfred-properties
PINECONE_ENVIRONMENT=us-east-1

# Telegram
TELEGRAM_BOT_TOKEN=123456:ABC-DEF...
TELEGRAM_WEBHOOK_URL=https://your-render-app.onrender.com/api/webhooks/telegram

# Apify
APIFY_API_TOKEN=apify_api_...
APIFY_ACTOR_ID=your-airbnb-scraper-actor

# App
APP_URL=https://app.yourdomain.com
RENDER_PORT=3000
```

---

# RENDER BACKEND — FILE STRUCTURE

```
alfred-backend/
├── package.json
├── tsconfig.json
├── src/
│   ├── index.ts                    # Express app entry point
│   ├── config/
│   │   ├── supabase.ts             # Supabase client (service role)
│   │   ├── gemini.ts               # Gemini client
│   │   ├── pinecone.ts             # Pinecone client
│   │   └── telegram.ts             # Telegram Bot API helper
│   ├── types/
│   │   ├── database.ts             # All DB row types
│   │   ├── api.ts                  # Request/response types
│   │   └── gemini.ts               # Gemini prompt/response types
│   ├── routes/
│   │   ├── pipeline.ts             # /api/pipeline/*
│   │   ├── messages.ts             # /api/messages/*
│   │   ├── webhooks.ts             # /api/webhooks/*
│   │   ├── escalation.ts           # /api/escalation/*
│   │   ├── links.ts                # /api/links/*
│   │   ├── knowledge.ts            # /api/knowledge-base/*
│   │   ├── properties.ts           # /api/properties/*
│   │   ├── conversations.ts        # /api/conversations/*
│   │   └── admin.ts                # /api/admin/*
│   ├── services/
│   │   ├── scraper.service.ts      # Apify + Gemini structuring
│   │   ├── ingestor.service.ts     # File processing + Gemini
│   │   ├── merger.service.ts       # Merge + conflict detection
│   │   ├── resolver.service.ts     # Apply resolutions
│   │   ├── vectorizer.service.ts   # Pinecone chunking + embedding
│   │   ├── chat.service.ts         # Core AI response generation (RAG)
│   │   ├── sentiment.service.ts    # Sentiment analysis
│   │   ├── escalation.service.ts   # Escalation trigger + routing
│   │   ├── learning.service.ts     # Learning Loop (Batch Stamp + Distillation)
│   │   ├── systemchat.service.ts   # Host-System Chat
│   │   ├── telegram.service.ts     # Telegram send/receive helpers
│   │   └── links.service.ts        # Magic Link generation
│   ├── middleware/
│   │   ├── auth.ts                 # Supabase JWT verification
│   │   └── admin.ts                # Admin role check
│   └── utils/
│       ├── logger.ts               # Console logger (V1), structured in V2
│       └── helpers.ts              # Shared utilities
```

---

# PHASE 0: FOUNDATION

## 0.1 Initialize Render Project

```bash
mkdir alfred-backend && cd alfred-backend
npm init -y
npm install express cors dotenv @supabase/supabase-js @google-cloud/vertexai @pinecone-database/pinecone node-fetch
npm install -D typescript @types/express @types/node @types/cors ts-node nodemon
npx tsc --init
```

**tsconfig.json** — set these:
```json
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "commonjs",
    "lib": ["ES2020"],
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "resolveJsonModule": true,
    "declaration": true,
    "sourceMap": true
  },
  "include": ["src/**/*"]
}
```

## 0.2 TypeScript Interfaces — `/src/types/database.ts`

```typescript
// ═══════════════════════════════════════════════════════════
// DATABASE ROW TYPES — Match Supabase schema exactly
// ═══════════════════════════════════════════════════════════

export interface Property {
  id: string;                        // uuid
  created_at: string;                // timestamptz
  owner_id: string;                  // uuid FK → hosts
  name: string;
  airbnb_url: string | null;
  status: PropertyStatus;
  master_json: Record<string, any> | null;  // jsonb
  scraped_markdown: string | null;
  ingested_markdown: string | null;
  conflict_status: string | null;
  conflict_report: ConflictReport[] | null; // jsonb
  resolution_history: any | null;
  resolution_history_json: any | null;
  host_id: string;                   // uuid FK → hosts
}

export type PropertyStatus =
  | 'Ready_to_Build'
  | 'Scraped'
  | 'Ingested'
  | 'Waiting'
  | 'Resolved'
  | 'Trained';

export interface Host {
  id: string;                        // uuid (matches auth.uid)
  name: string;
  telegram_chat_id: string | null;
  whatsapp_number: string | null;
  email: string;
  created_at: string;
  TG_verification_code: string | null;
  active_conversation_id: string | null;  // THE LOCK — null = Lobby Mode
}

export interface Guest {
  id: string;                        // uuid
  created_at: string;
  property_id: string;               // uuid FK → properties
  name: string;
  booking_code: string;
  contact_info: Record<string, any> | null;
  thread_summary: string | null;
}

export interface Conversation {
  booking_id: string;                // PK
  property_id: string;               // uuid FK → properties
  guest_name: string;
  platform: Platform;
  ai_status: string | null;
  requires_attention: boolean;
  last_message_at: string | null;
  created_at: string;
  check_out_date: string | null;     // date (YYYY-MM-DD)
  preferred_language: string | null;
  is_escalated: boolean;
  escalation_reason: string | null;
  telegram_chat_id: string | null;
}

export type Platform = 'telegram' | 'web' | 'whatsapp';

export interface Message {
  id: string;                        // uuid
  booking_id: string;                // FK → conversations
  sender_type: SenderType;
  content: string;
  media_url: string | null;
  sentiment: Sentiment | null;
  status: MessageStatus;
  created_at: string;
  is_escalated_interaction: boolean;
  property_id: string;               // uuid FK → properties
  resolution_status: 'resolved' | null;
  is_learned: boolean;
}

export type SenderType = 'guest' | 'ai' | 'host' | 'system';
export type Sentiment = 'positive' | 'neutral' | 'negative' | 'hostility' | 'emergency';
export type MessageStatus = 'unread' | 'sent' | 'delivered' | 'read';

export interface KnowledgeEntry {
  id: string;                        // uuid
  created_at: string;
  property_id: string;               // uuid FK → properties
  problem_summary: string;
  solution_summary: string;
  category: KnowledgeCategory;
  source_message_ids: string[];      // jsonb array of message UUIDs
  original_transcript: any;          // jsonb
  is_verified: boolean;
}

export type KnowledgeCategory =
  | 'connectivity'
  | 'access'
  | 'appliances'
  | 'amenities'
  | 'cleaning'
  | 'noise'
  | 'safety'
  | 'checkout'
  | 'other';

export interface Conflict {
  id: string;                        // uuid
  created_at: string;
  property_id: string;               // uuid FK → properties
  status: 'pending' | 'resolved';
  question: string;
  option_a: string;
  option_b: string;
  resolution: string | null;
}

export interface ConflictReport {
  question: string;
  option_a: string;
  option_b: string;
  field_path: string;
}
```

## 0.3 TypeScript Interfaces — `/src/types/api.ts`

```typescript
// ═══════════════════════════════════════════════════════════
// API REQUEST / RESPONSE TYPES
// ═══════════════════════════════════════════════════════════

// --- Pipeline ---
export interface ScrapeRequest {
  property_id: string;
  airbnb_url: string;
}

export interface IngestRequest {
  property_id: string;
  file_url: string;      // Supabase Storage URL
  file_type: 'pdf' | 'png' | 'jpg' | 'jpeg' | 'mp3' | 'ogg' | 'wav' | 'm4a' | 'txt' | 'doc' | 'docx';
}

export interface MergeRequest {
  property_id: string;
}

export interface ResolveRequest {
  property_id: string;
  resolutions: Array<{
    conflict_id: string;
    chosen: 'a' | 'b';
  }>;
}

export interface VectorizeRequest {
  property_id: string;
}

// --- Links ---
export interface GenerateLinkRequest {
  type: 'guest' | 'host';
  booking_id?: string;
  host_id?: string;
}

export interface GenerateLinkResponse {
  telegram_url?: string;
  web_url?: string;
  whatsapp_url?: string;  // V2
}

// --- Messages ---
export interface WebMessageRequest {
  booking_id: string;
  content: string;
  media_url?: string;
}

// --- Escalation ---
export interface GhostSendRequest {
  property_id: string;
  booking_id: string;
  content: string;
}

// --- System Chat ---
export interface SystemChatRequest {
  property_id: string;
  message: string;
  media_url?: string;
}

export interface SystemChatResponse {
  success: boolean;
  change_summary: string;
  response: string;
}

// --- Knowledge Base ---
export interface KnowledgeUpdateRequest {
  action: 'confirm' | 'deny' | 'modify';
  problem_summary?: string;   // Required if action == 'modify'
  solution_summary?: string;  // Required if action == 'modify'
}

// --- Gemini ---
export interface GeminiChunk {
  section: string;
  content: string;
}

export interface DistillationResult {
  problem_summary: string;
  solution_summary: string;
  category: string;
}

export interface MergeResult {
  master_json: Record<string, any>;
  has_conflicts: boolean;
  conflicts: ConflictReport[];
}

// --- Pinecone ---
export interface PineconeMatch {
  id: string;
  score: number;
  metadata: {
    property_id: string;
    property_name: string;
    section: string;
    content: string;
  };
}
```

## 0.4 Config Files

### `/src/config/supabase.ts`

```typescript
import { createClient } from '@supabase/supabase-js';

// Service role client — bypasses RLS, use ONLY on server
export const supabaseAdmin = createClient(
  process.env.SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
);

// Anon client — respects RLS, use for user-scoped queries
export const supabaseAnon = createClient(
  process.env.SUPABASE_URL!,
  process.env.SUPABASE_ANON_KEY!
);
```

### `/src/config/pinecone.ts`

```typescript
import { Pinecone } from '@pinecone-database/pinecone';

export const pinecone = new Pinecone({
  apiKey: process.env.PINECONE_API_KEY!,
});

export const getIndex = () => pinecone.index(process.env.PINECONE_INDEX!);
```

### `/src/config/telegram.ts`

```typescript
const TELEGRAM_API = `https://api.telegram.org/bot${process.env.TELEGRAM_BOT_TOKEN}`;

export async function sendTelegramMessage(
  chatId: string,
  text: string,
  replyMarkup?: any
): Promise<void> {
  await fetch(`${TELEGRAM_API}/sendMessage`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      chat_id: chatId,
      text: text,
      parse_mode: 'HTML',
      ...(replyMarkup && { reply_markup: JSON.stringify(replyMarkup) }),
    }),
  });
}

export async function setWebhook(url: string): Promise<void> {
  await fetch(`${TELEGRAM_API}/setWebhook`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ url }),
  });
}
```

### `/src/config/gemini.ts`

```typescript
// Use Gemini REST API or Vertex AI SDK
// Adapt based on which access method you use

const GEMINI_API_URL = 'https://generativelanguage.googleapis.com/v1beta';

export async function callGemini(prompt: string, systemInstruction?: string): Promise<string> {
  const response = await fetch(
    `${GEMINI_API_URL}/models/gemini-2.0-flash:generateContent?key=${process.env.GEMINI_API_KEY}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        contents: [{ role: 'user', parts: [{ text: prompt }] }],
        ...(systemInstruction && {
          systemInstruction: { parts: [{ text: systemInstruction }] },
        }),
      }),
    }
  );
  const data = await response.json();
  return data.candidates[0].content.parts[0].text;
}

export async function callGeminiJSON<T>(prompt: string, systemInstruction?: string): Promise<T> {
  const raw = await callGemini(prompt, systemInstruction);
  // Strip markdown code fences if present
  const cleaned = raw.replace(/```json\n?/g, '').replace(/```\n?/g, '').trim();
  return JSON.parse(cleaned) as T;
}

export async function embedText(text: string): Promise<number[]> {
  const response = await fetch(
    `${GEMINI_API_URL}/models/text-embedding-004:embedContent?key=${process.env.GEMINI_API_KEY}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        content: { parts: [{ text }] },
      }),
    }
  );
  const data = await response.json();
  return data.embedding.values;
}
```

## 0.5 Express App Entry — `/src/index.ts`

```typescript
import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
dotenv.config();

import pipelineRoutes from './routes/pipeline';
import webhookRoutes from './routes/webhooks';
import messageRoutes from './routes/messages';
import escalationRoutes from './routes/escalation';
import linkRoutes from './routes/links';
import knowledgeRoutes from './routes/knowledge';
import propertyRoutes from './routes/properties';
import conversationRoutes from './routes/conversations';
import adminRoutes from './routes/admin';

const app = express();
app.use(cors());
app.use(express.json());

// Health check
app.get('/health', (req, res) => res.json({ status: 'ok', version: 'v1' }));

// Routes
app.use('/api/pipeline', pipelineRoutes);
app.use('/api/webhooks', webhookRoutes);
app.use('/api/messages', messageRoutes);
app.use('/api/escalation', escalationRoutes);
app.use('/api/links', linkRoutes);
app.use('/api/knowledge-base', knowledgeRoutes);
app.use('/api/properties', propertyRoutes);
app.use('/api/conversations', conversationRoutes);
app.use('/api/admin', adminRoutes);

const PORT = process.env.RENDER_PORT || 3000;
app.listen(PORT, () => console.log(`Alfred backend running on port ${PORT}`));
```

## 0.6 Supabase Schema SQL

Run this in Supabase SQL Editor:

```sql
-- ═══════════════════════════════════════════════════
-- ALFRED V1 SCHEMA
-- Run in order. All tables, RLS, indexes.
-- ═══════════════════════════════════════════════════

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ─── HOSTS ───
CREATE TABLE hosts (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  name text NOT NULL,
  telegram_chat_id text,
  whatsapp_number text,
  email text UNIQUE NOT NULL,
  created_at timestamptz DEFAULT now(),
  "TG_verification_code" text,
  active_conversation_id text  -- THE LOCK: null = Lobby, non-null = locked to booking_id
);

-- ─── PROPERTIES ───
CREATE TABLE properties (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  created_at timestamptz DEFAULT now(),
  owner_id uuid REFERENCES hosts(id) ON DELETE CASCADE,
  name text NOT NULL,
  airbnb_url text,
  status text DEFAULT 'Ready_to_Build'
    CHECK (status IN ('Ready_to_Build','Scraped','Ingested','Waiting','Resolved','Trained')),
  master_json jsonb,
  scraped_markdown text,
  ingested_markdown text,
  conflict_status text,
  conflict_report jsonb,
  resolution_history json,
  resolution_history_json json,
  host_id uuid REFERENCES hosts(id)
);

-- ─── GUESTS ───
CREATE TABLE guests (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  created_at timestamptz DEFAULT now(),
  property_id uuid REFERENCES properties(id) ON DELETE CASCADE,
  name text NOT NULL,
  booking_code text NOT NULL,
  contact_info jsonb,
  thread_summary text
);

-- ─── CONVERSATIONS ───
CREATE TABLE conversations (
  booking_id text PRIMARY KEY,
  property_id uuid REFERENCES properties(id) ON DELETE CASCADE,
  guest_name text NOT NULL,
  platform text CHECK (platform IN ('telegram','web','whatsapp')),
  ai_status text,
  requires_attention boolean DEFAULT false,
  last_message_at timestamptz,
  created_at timestamptz DEFAULT now(),
  check_out_date date,
  preferred_language text DEFAULT 'en',
  is_escalated boolean DEFAULT false,
  escalation_reason text,
  telegram_chat_id text
);

-- ─── MESSAGES ───
CREATE TABLE messages (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  booking_id text REFERENCES conversations(booking_id) ON DELETE CASCADE,
  sender_type text NOT NULL CHECK (sender_type IN ('guest','ai','host','system')),
  content text NOT NULL,
  media_url text,
  sentiment text CHECK (sentiment IN ('positive','neutral','negative','hostility','emergency')),
  status text DEFAULT 'sent' CHECK (status IN ('unread','sent','delivered','read')),
  created_at timestamptz DEFAULT now(),
  is_escalated_interaction boolean DEFAULT false,
  property_id uuid REFERENCES properties(id),
  resolution_status text CHECK (resolution_status IN ('resolved')),
  is_learned boolean DEFAULT false
);

-- ─── KNOWLEDGE BASE ───
CREATE TABLE knowledge_base (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  created_at timestamptz DEFAULT now(),
  property_id uuid REFERENCES properties(id) ON DELETE CASCADE,
  problem_summary text NOT NULL,
  solution_summary text NOT NULL,
  category text NOT NULL CHECK (category IN (
    'connectivity','access','appliances','amenities',
    'cleaning','noise','safety','checkout','other'
  )),
  source_message_ids jsonb DEFAULT '[]',
  original_transcript jsonb,
  is_verified boolean DEFAULT true
);

-- ─── CONFLICTS ───
CREATE TABLE conflicts (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  created_at timestamptz DEFAULT now(),
  property_id uuid REFERENCES properties(id) ON DELETE CASCADE,
  status text DEFAULT 'pending' CHECK (status IN ('pending','resolved')),
  question text NOT NULL,
  option_a text NOT NULL,
  option_b text NOT NULL,
  resolution text
);

-- ═══════════════════════════════════════════════════
-- INDEXES (Performance)
-- ═══════════════════════════════════════════════════

CREATE INDEX idx_properties_owner ON properties(owner_id);
CREATE INDEX idx_properties_status ON properties(status);
CREATE INDEX idx_conversations_property ON conversations(property_id);
CREATE INDEX idx_conversations_attention ON conversations(requires_attention) WHERE requires_attention = true;
CREATE INDEX idx_conversations_escalated ON conversations(is_escalated) WHERE is_escalated = true;
CREATE INDEX idx_messages_booking ON messages(booking_id);
CREATE INDEX idx_messages_booking_created ON messages(booking_id, created_at DESC);
CREATE INDEX idx_messages_escalated ON messages(booking_id, is_escalated_interaction) WHERE is_escalated_interaction = true;
CREATE INDEX idx_knowledge_property ON knowledge_base(property_id);
CREATE INDEX idx_knowledge_verified ON knowledge_base(property_id, is_verified) WHERE is_verified = true;
CREATE INDEX idx_conflicts_property ON conflicts(property_id);
CREATE INDEX idx_conflicts_pending ON conflicts(property_id, status) WHERE status = 'pending';

-- ═══════════════════════════════════════════════════
-- ROW LEVEL SECURITY
-- ═══════════════════════════════════════════════════

ALTER TABLE hosts ENABLE ROW LEVEL SECURITY;
ALTER TABLE properties ENABLE ROW LEVEL SECURITY;
ALTER TABLE guests ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE knowledge_base ENABLE ROW LEVEL SECURITY;
ALTER TABLE conflicts ENABLE ROW LEVEL SECURITY;

-- Hosts see only their own record
CREATE POLICY "hosts_self" ON hosts
  FOR ALL USING (id = auth.uid());

-- Hosts see only their own properties
CREATE POLICY "hosts_own_properties" ON properties
  FOR ALL USING (owner_id = auth.uid());

-- Hosts see guests for their properties
CREATE POLICY "hosts_own_guests" ON guests
  FOR ALL USING (
    property_id IN (SELECT id FROM properties WHERE owner_id = auth.uid())
  );

-- Hosts see conversations for their properties
CREATE POLICY "hosts_own_conversations" ON conversations
  FOR ALL USING (
    property_id IN (SELECT id FROM properties WHERE owner_id = auth.uid())
  );

-- Hosts see messages for their properties
CREATE POLICY "hosts_own_messages" ON messages
  FOR ALL USING (
    property_id IN (SELECT id FROM properties WHERE owner_id = auth.uid())
  );

-- Hosts see knowledge for their properties
CREATE POLICY "hosts_own_knowledge" ON knowledge_base
  FOR ALL USING (
    property_id IN (SELECT id FROM properties WHERE owner_id = auth.uid())
  );

-- Hosts see conflicts for their properties
CREATE POLICY "hosts_own_conflicts" ON conflicts
  FOR ALL USING (
    property_id IN (SELECT id FROM properties WHERE owner_id = auth.uid())
  );

-- Admin full access (all tables)
CREATE POLICY "admin_hosts" ON hosts
  FOR ALL USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');
CREATE POLICY "admin_properties" ON properties
  FOR ALL USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');
CREATE POLICY "admin_guests" ON guests
  FOR ALL USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');
CREATE POLICY "admin_conversations" ON conversations
  FOR ALL USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');
CREATE POLICY "admin_messages" ON messages
  FOR ALL USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');
CREATE POLICY "admin_knowledge" ON knowledge_base
  FOR ALL USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');
CREATE POLICY "admin_conflicts" ON conflicts
  FOR ALL USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

-- Service role bypass (for Render backend using service_role key)
-- Note: Supabase service_role key bypasses RLS automatically.
-- The policies above apply to anon/authenticated clients (Dashboard, Web App).

-- ═══════════════════════════════════════════════════
-- REALTIME (Enable for Dashboard live updates)
-- ═══════════════════════════════════════════════════

ALTER PUBLICATION supabase_realtime ADD TABLE conversations;
ALTER PUBLICATION supabase_realtime ADD TABLE messages;
ALTER PUBLICATION supabase_realtime ADD TABLE properties;
ALTER PUBLICATION supabase_realtime ADD TABLE conflicts;
ALTER PUBLICATION supabase_realtime ADD TABLE knowledge_base;
```

## 0.7 Pinecone Index Setup

Create index via Pinecone dashboard or API:
- **Name:** `alfred-properties`
- **Dimensions:** 768 (Gemini text-embedding-004 outputs 768-dim vectors)
- **Metric:** cosine
- **Cloud/Region:** Match your Render region

---

# PHASE 1: THE BRAIN (Data Pipeline + Pinecone)

## File: `/src/services/scraper.service.ts`

```typescript
import { supabaseAdmin } from '../config/supabase';
import { callGemini } from '../config/gemini';
import { Property } from '../types/database';
import { vectorize } from './vectorizer.service';

const APIFY_API = 'https://api.apify.com/v2';

export async function scrapeProperty(propertyId: string, airbnbUrl: string): Promise<void> {
  // STEP 1: Trigger Apify actor
  const runResponse = await fetch(
    `${APIFY_API}/acts/${process.env.APIFY_ACTOR_ID}/runs?token=${process.env.APIFY_API_TOKEN}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        startUrls: [{ url: airbnbUrl }],
        maxListings: 1,
      }),
    }
  );
  const run = await runResponse.json();

  // STEP 2: Wait for completion and get results
  // Poll until run finishes (or use webhook)
  let status = 'RUNNING';
  while (status === 'RUNNING' || status === 'READY') {
    await new Promise(resolve => setTimeout(resolve, 5000)); // 5s poll
    const statusResponse = await fetch(
      `${APIFY_API}/actor-runs/${run.data.id}?token=${process.env.APIFY_API_TOKEN}`
    );
    const statusData = await statusResponse.json();
    status = statusData.data.status;
  }

  const resultsResponse = await fetch(
    `${APIFY_API}/datasets/${run.data.defaultDatasetId}/items?token=${process.env.APIFY_API_TOKEN}`
  );
  const results = await resultsResponse.json();

  // STEP 3: Structure with Gemini
  const markdown = await callGemini(
    `Structure this raw Airbnb listing data into clean Markdown.

Sections to include:
- Property Overview (name, type, location, capacity, bedrooms, bathrooms)
- Amenities (full list, grouped by category)
- House Rules (check-in/check-out times, pet policy, smoking, parties, quiet hours)
- Check-in / Check-out Instructions
- Location & Neighborhood
- Host Information
- Photos Description (describe what's visible)
- Pricing Information (if available)

Raw data:
${JSON.stringify(results, null, 2)}`,
    'You are a data structuring assistant. Output clean, well-organized Markdown. Be thorough — capture every detail.'
  );

  // STEP 4: Save to Supabase
  const { error } = await supabaseAdmin
    .from('properties')
    .update({
      scraped_markdown: markdown,
      status: 'Scraped',
    })
    .eq('id', propertyId);

  if (error) throw new Error(`Failed to save scraped data: ${error.message}`);
}
```

## File: `/src/services/ingestor.service.ts`

```typescript
import { supabaseAdmin } from '../config/supabase';
import { callGemini } from '../config/gemini';
import { merge } from './merger.service';

export async function ingestFile(
  propertyId: string,
  fileUrl: string,
  fileType: string
): Promise<void> {
  // STEP 1: Download file from Supabase Storage
  const { data: fileData, error: downloadError } = await supabaseAdmin.storage
    .from('property-files')
    .download(fileUrl);

  if (downloadError) throw new Error(`Download failed: ${downloadError.message}`);

  // STEP 2: Extract text based on file type
  let extractedText: string;

  if (['png', 'jpg', 'jpeg'].includes(fileType)) {
    // Vision — send as base64
    const buffer = Buffer.from(await fileData.arrayBuffer());
    const base64 = buffer.toString('base64');
    // Use Gemini vision endpoint
    extractedText = await callGemini(
      `Extract ALL text and information visible in this image. Include:
       - Any WiFi passwords, access codes, phone numbers
       - Instructions, rules, or guidelines
       - Addresses, directions, contact information
       - Any other useful property information

       Image data (base64): ${base64}`,
      'You are an OCR and information extraction specialist.'
    );
  } else if (['mp3', 'ogg', 'wav', 'm4a'].includes(fileType)) {
    // Audio transcription
    // NOTE: Gemini audio support — check current API capabilities
    // Alternative: Use Google Speech-to-Text or Whisper API
    extractedText = await callGemini(
      'Transcribe this audio recording. Extract all property information mentioned.',
      'You are a transcription specialist.'
      // TODO: Attach audio data per Gemini multimodal API spec
    );
  } else {
    // Text-based files (pdf, txt, doc)
    // For PDF: use a library like pdf-parse
    // npm install pdf-parse
    const text = await fileData.text();
    extractedText = text;
  }

  // STEP 3: Structure with Gemini
  const markdown = await callGemini(
    `Structure this property information into clean Markdown.

Extract and organize:
- WiFi passwords and network names
- Access codes (door, gate, garage, safe)
- House rules and policies
- Check-in / check-out instructions
- Emergency contacts and phone numbers
- Amenity details and locations
- Appliance instructions
- Parking information
- Neighborhood tips and recommendations
- Any other guest-relevant information

Raw extracted text:
${extractedText}`,
    'You are a property information specialist. Be thorough — every detail matters for guest experience.'
  );

  // STEP 4: Append to existing ingested_markdown
  const { data: property } = await supabaseAdmin
    .from('properties')
    .select('ingested_markdown')
    .eq('id', propertyId)
    .single();

  const combined = property?.ingested_markdown
    ? property.ingested_markdown + '\n\n---\n\n' + markdown
    : markdown;

  const { error } = await supabaseAdmin
    .from('properties')
    .update({
      ingested_markdown: combined,
      status: 'Ingested',
    })
    .eq('id', propertyId);

  if (error) throw new Error(`Failed to save ingested data: ${error.message}`);

  // STEP 5: Auto-trigger merge
  await merge(propertyId);
}
```

## File: `/src/services/merger.service.ts`

```typescript
import { supabaseAdmin } from '../config/supabase';
import { callGeminiJSON } from '../config/gemini';
import { MergeResult } from '../types/api';
import { vectorize } from './vectorizer.service';

export async function merge(propertyId: string): Promise<{ has_conflicts: boolean }> {
  // STEP 1: Fetch both sources
  const { data: property, error } = await supabaseAdmin
    .from('properties')
    .select('scraped_markdown, ingested_markdown')
    .eq('id', propertyId)
    .single();

  if (error || !property) throw new Error(`Property not found: ${propertyId}`);

  // STEP 2: Gemini merge + conflict detection
  const result = await callGeminiJSON<MergeResult>(
    `You are merging two data sources for a vacation rental property.

Source A (Scraped from Airbnb listing):
${property.scraped_markdown || '(No scraped data available)'}

Source B (Host-provided documents):
${property.ingested_markdown || '(No ingested data available)'}

MERGE RULES:
1. If both sources agree on a fact, merge into single entry.
2. If sources conflict (different check-in times, different WiFi passwords, etc.), flag as conflict.
3. Host-provided data (Source B) is generally more authoritative, but still flag conflicts for host confirmation.
4. Include ALL information from both sources — do not drop any details.

RESPOND WITH STRICT JSON (no markdown, no code fences):
{
  "master_json": {
    "property_name": "...",
    "property_type": "...",
    "location": { "address": "...", "city": "...", "neighborhood": "..." },
    "capacity": { "guests": 0, "bedrooms": 0, "beds": 0, "bathrooms": 0 },
    "check_in": { "time": "...", "instructions": "..." },
    "check_out": { "time": "...", "instructions": "..." },
    "connectivity": { "wifi_name": "...", "wifi_password": "..." },
    "access": { "door_code": "...", "gate_code": "...", "key_location": "..." },
    "amenities": { ... },
    "house_rules": { ... },
    "emergency_contacts": [ ... ],
    "parking": { ... },
    "neighborhood": { ... },
    "appliance_instructions": { ... },
    "additional_info": { ... }
  },
  "has_conflicts": true/false,
  "conflicts": [
    {
      "question": "Check-in time: listing says 2pm, your PDF says 3pm. Which is correct?",
      "option_a": "2:00 PM (from Airbnb listing)",
      "option_b": "3:00 PM (from your uploaded PDF)",
      "field_path": "check_in.time"
    }
  ]
}`,
    'You are a precise data merger. Output ONLY valid JSON. No markdown formatting, no explanation text.'
  );

  // STEP 3: Route
  if (!result.has_conflicts) {
    await supabaseAdmin
      .from('properties')
      .update({
        master_json: result.master_json,
        status: 'Trained',
        conflict_status: 'none',
      })
      .eq('id', propertyId);

    // Vectorize
    await vectorize(propertyId);
  } else {
    await supabaseAdmin
      .from('properties')
      .update({
        master_json: result.master_json, // Partial merge
        status: 'Waiting',
        conflict_status: 'pending',
        conflict_report: result.conflicts,
      })
      .eq('id', propertyId);

    // Insert conflict records
    for (const conflict of result.conflicts) {
      await supabaseAdmin.from('conflicts').insert({
        property_id: propertyId,
        status: 'pending',
        question: conflict.question,
        option_a: conflict.option_a,
        option_b: conflict.option_b,
      });
    }
  }

  return { has_conflicts: result.has_conflicts };
}
```

## File: `/src/services/resolver.service.ts`

```typescript
import { supabaseAdmin } from '../config/supabase';
import { callGeminiJSON } from '../config/gemini';
import { vectorize } from './vectorizer.service';

export async function resolveConflicts(
  propertyId: string,
  resolutions: Array<{ conflict_id: string; chosen: 'a' | 'b' }>
): Promise<void> {
  // STEP 1: Fetch property + conflicts
  const { data: property } = await supabaseAdmin
    .from('properties')
    .select('master_json')
    .eq('id', propertyId)
    .single();

  // STEP 2: Apply resolutions to conflicts table
  const resolvedConflicts = [];
  for (const resolution of resolutions) {
    const { data: conflict } = await supabaseAdmin
      .from('conflicts')
      .select('*')
      .eq('id', resolution.conflict_id)
      .single();

    if (!conflict) continue;

    const chosenValue = resolution.chosen === 'a' ? conflict.option_a : conflict.option_b;

    await supabaseAdmin
      .from('conflicts')
      .update({ status: 'resolved', resolution: chosenValue })
      .eq('id', resolution.conflict_id);

    resolvedConflicts.push({
      question: conflict.question,
      resolution: chosenValue,
      field_path: conflict.field_path || '',
    });
  }

  // STEP 3: Re-merge with Gemini
  const finalJson = await callGeminiJSON<Record<string, any>>(
    `You have a partially merged property JSON and a set of conflict resolutions.
Apply each resolution to the JSON and return the complete, final master_json.

Current Master JSON:
${JSON.stringify(property?.master_json, null, 2)}

Conflict Resolutions:
${JSON.stringify(resolvedConflicts, null, 2)}

Return ONLY the updated master_json as valid JSON. No explanation.`,
    'You are a data resolution specialist. Apply resolutions precisely. Output only valid JSON.'
  );

  // STEP 4: Save
  await supabaseAdmin
    .from('properties')
    .update({
      master_json: finalJson,
      status: 'Trained',
      conflict_status: 'resolved',
    })
    .eq('id', propertyId);

  // STEP 5: Vectorize
  await vectorize(propertyId);
}
```

## File: `/src/services/vectorizer.service.ts`

```typescript
import { supabaseAdmin } from '../config/supabase';
import { callGeminiJSON, embedText } from '../config/gemini';
import { getIndex } from '../config/pinecone';
import { GeminiChunk } from '../types/api';

export async function vectorize(propertyId: string): Promise<number> {
  // STEP 1: Fetch Master JSON
  const { data: property } = await supabaseAdmin
    .from('properties')
    .select('master_json, name')
    .eq('id', propertyId)
    .single();

  if (!property?.master_json) throw new Error('No master_json to vectorize');

  // STEP 2: Chunk into semantic sections
  const chunks = await callGeminiJSON<GeminiChunk[]>(
    `Split this property data into semantic chunks for a retrieval system.
Each chunk should be a self-contained topic that a guest might ask about.

Good chunks: "WiFi & Connectivity", "Check-in Instructions", "Check-out Instructions",
"House Rules", "Kitchen & Cooking", "Parking", "Pool & Outdoor", "Neighborhood & Restaurants",
"Emergency Contacts", "Bathroom", "Bedroom & Sleeping", "Entertainment & TV",
"Laundry", "Heating & Cooling", "Safety & Security", etc.

Only create chunks for topics that have actual content.

Property data:
${JSON.stringify(property.master_json, null, 2)}

Return as JSON array (no markdown, no code fences):
[
  { "section": "WiFi & Connectivity", "content": "The WiFi network is called GuestNet. Password is Beach2024. Router is in the living room behind the TV." },
  { "section": "Check-in Instructions", "content": "Check-in is at 3:00 PM. Door code is 4523#. Enter through the side gate." }
]`,
    'You are a content chunking specialist. Create chunks that are self-contained and useful for answering guest questions. Each chunk should be 50-300 words. Output only valid JSON array.'
  );

  // STEP 3: Delete old vectors for this property
  const index = getIndex();
  const ns = index.namespace(propertyId);

  try {
    await ns.deleteAll();
  } catch (e) {
    // Namespace might not exist yet — that's fine
  }

  // STEP 4: Embed and upsert each chunk
  const vectors = [];
  for (const chunk of chunks) {
    const embedding = await embedText(chunk.content);
    vectors.push({
      id: `${propertyId}_${chunk.section.replace(/\s+/g, '_').toLowerCase()}`,
      values: embedding,
      metadata: {
        property_id: propertyId,
        property_name: property.name,
        section: chunk.section,
        content: chunk.content,
      },
    });
  }

  // Upsert in batches of 100
  for (let i = 0; i < vectors.length; i += 100) {
    const batch = vectors.slice(i, i + 100);
    await ns.upsert(batch);
  }

  return chunks.length;
}
```

## File: `/src/routes/pipeline.ts`

```typescript
import { Router } from 'express';
import { scrapeProperty } from '../services/scraper.service';
import { ingestFile } from '../services/ingestor.service';
import { merge } from '../services/merger.service';
import { resolveConflicts } from '../services/resolver.service';
import { vectorize } from '../services/vectorizer.service';

const router = Router();

router.post('/scrape', async (req, res) => {
  try {
    const { property_id, airbnb_url } = req.body;
    await scrapeProperty(property_id, airbnb_url);
    res.json({ success: true, status: 'Scraped' });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

router.post('/ingest', async (req, res) => {
  try {
    const { property_id, file_url, file_type } = req.body;
    await ingestFile(property_id, file_url, file_type);
    res.json({ success: true, status: 'Ingested' });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

router.post('/merge', async (req, res) => {
  try {
    const { property_id } = req.body;
    const result = await merge(property_id);
    res.json({ success: true, ...result });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

router.post('/resolve', async (req, res) => {
  try {
    const { property_id, resolutions } = req.body;
    await resolveConflicts(property_id, resolutions);
    res.json({ success: true, status: 'Trained' });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

router.post('/vectorize', async (req, res) => {
  try {
    const { property_id } = req.body;
    const count = await vectorize(property_id);
    res.json({ success: true, chunks: count });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

export default router;
```

### PHASE 1 TEST CRITERIA

```
□ POST /api/pipeline/scrape with valid Airbnb URL
  → properties.scraped_markdown populated
  → properties.status = 'Scraped'

□ POST /api/pipeline/ingest with uploaded PDF URL
  → properties.ingested_markdown populated
  → properties.status = 'Ingested'
  → merge auto-triggered

□ Merge with no conflicts
  → properties.master_json populated
  → properties.status = 'Trained'
  → Pinecone namespace has vectors
  → Query "WiFi password" returns relevant chunk

□ Merge with conflicts
  → properties.status = 'Waiting'
  → conflicts table has pending rows
  → Each conflict has question, option_a, option_b

□ POST /api/pipeline/resolve with resolutions
  → properties.master_json updated with resolutions
  → properties.status = 'Trained'
  → conflicts.status = 'resolved'
  → Pinecone re-vectorized
```

---

# PHASE 2: MESSAGING CORE (Telegram)

## File: `/src/services/chat.service.ts`

```typescript
import { supabaseAdmin } from '../config/supabase';
import { callGemini, embedText } from '../config/gemini';
import { getIndex } from '../config/pinecone';
import { analyzeSentiment } from './sentiment.service';
import { triggerEscalation } from './escalation.service';
import { routeGuestToHost } from './escalation.service';
import { sendTelegramMessage } from '../config/telegram';
import { Conversation, Message, KnowledgeEntry, PineconeMatch } from '../types/database';

export async function handleGuestMessage(
  conversation: Conversation,
  text: string,
  mediaUrl: string | null
): Promise<void> {

  // ─── STEP 1: INPUT LOG ───
  const { data: newMessage } = await supabaseAdmin
    .from('messages')
    .insert({
      booking_id: conversation.booking_id,
      sender_type: 'guest',
      content: text,
      media_url: mediaUrl,
      status: 'unread',
      property_id: conversation.property_id,
      is_escalated_interaction: conversation.is_escalated,
    })
    .select()
    .single();

  // ─── STEP 2: CHECK ESCALATION ───
  if (conversation.is_escalated) {
    await routeGuestToHost(conversation, text, newMessage!.id);
    return; // Do NOT generate AI response
  }

  // ─── STEP 3: SENTIMENT ANALYSIS ───
  const sentiment = await analyzeSentiment(text);
  await supabaseAdmin
    .from('messages')
    .update({ sentiment })
    .eq('id', newMessage!.id);

  if (sentiment === 'hostility' || sentiment === 'emergency') {
    await triggerEscalation(conversation, sentiment);
    // Still generate a holding response below
  }

  // ─── STEP 4: RAG RETRIEVAL ───
  const embedding = await embedText(text);
  const index = getIndex();
  const ns = index.namespace(conversation.property_id);

  const queryResult = await ns.query({
    vector: embedding,
    topK: 5,
    includeMetadata: true,
  });

  const relevantContext = (queryResult.matches || [])
    .map((m: any) => m.metadata?.content || '')
    .filter(Boolean)
    .join('\n\n');

  // ─── STEP 5: KNOWLEDGE BASE ───
  const { data: knowledge } = await supabaseAdmin
    .from('knowledge_base')
    .select('*')
    .eq('property_id', conversation.property_id)
    .eq('is_verified', true);

  const knowledgeContext = (knowledge || [])
    .map((k: KnowledgeEntry) => `Problem: ${k.problem_summary}\nSolution: ${k.solution_summary}`)
    .join('\n\n');

  // ─── STEP 6: CONVERSATION HISTORY ───
  const { data: recentMessages } = await supabaseAdmin
    .from('messages')
    .select('sender_type, content, created_at')
    .eq('booking_id', conversation.booking_id)
    .order('created_at', { ascending: false })
    .limit(20);

  const historyContext = (recentMessages || [])
    .reverse()
    .map((m: any) => `${m.sender_type}: ${m.content}`)
    .join('\n');

  // ─── STEP 7: GENERATE RESPONSE ───
  const systemPrompt = `You are Alfred, a friendly and helpful AI assistant for the vacation rental property.
You help guests with their questions about the property, check-in, amenities, and local area.

RULES:
- Be warm, concise, and helpful.
- Respond in the guest's language: ${conversation.preferred_language || 'auto-detect from their message'}.
- Use ONLY the property information and learned knowledge provided below.
- If you don't know something, say so honestly and offer to connect the guest with the host.
- Never make up information about the property.
- Keep responses under 3 paragraphs unless the guest asks for detailed instructions.`;

  const userPrompt = `PROPERTY INFORMATION:
${relevantContext || '(No specific property information retrieved)'}

LEARNED KNOWLEDGE (from previous guest interactions):
${knowledgeContext || '(No learned knowledge available)'}

RECENT CONVERSATION:
${historyContext || '(This is the start of the conversation)'}

GUEST'S NEW MESSAGE:
${text}

Respond as Alfred:`;

  const aiResponse = await callGemini(userPrompt, systemPrompt);

  // ─── STEP 8: OUTPUT LOG ───
  await supabaseAdmin.from('messages').insert({
    booking_id: conversation.booking_id,
    sender_type: 'ai',
    content: aiResponse,
    status: 'sent',
    property_id: conversation.property_id,
  });

  // ─── STEP 9: SEND TO GUEST ───
  if (conversation.platform === 'telegram' && conversation.telegram_chat_id) {
    await sendTelegramMessage(conversation.telegram_chat_id, aiResponse);
  }
  // Web platform: guest receives via Supabase Realtime (no explicit send)

  // ─── STEP 10: UPDATE CONVERSATION ───
  await supabaseAdmin
    .from('conversations')
    .update({
      last_message_at: new Date().toISOString(),
      ai_status: 'responded',
    })
    .eq('booking_id', conversation.booking_id);
}
```

## File: `/src/services/sentiment.service.ts`

```typescript
import { callGemini } from '../config/gemini';
import { Sentiment } from '../types/database';

export async function analyzeSentiment(text: string): Promise<Sentiment> {
  const result = await callGemini(
    `Classify this vacation rental guest message into exactly ONE sentiment category.

Categories:
- positive: Happy, grateful, excited, complimentary
- neutral: Informational questions, general inquiries, factual statements
- negative: Mild complaints, minor dissatisfaction, polite concerns
- hostility: Angry, threatening, aggressive, abusive language, demanding refund aggressively
- emergency: Safety concerns, medical emergency, break-in, fire, flood, serious property damage

Message: "${text}"

Respond with ONLY the category word. Nothing else.`,
    'You are a sentiment classifier. Respond with a single word only.'
  );

  const cleaned = result.trim().toLowerCase() as Sentiment;
  const valid: Sentiment[] = ['positive', 'neutral', 'negative', 'hostility', 'emergency'];
  return valid.includes(cleaned) ? cleaned : 'neutral';
}
```

## File: `/src/routes/webhooks.ts`

```typescript
import { Router } from 'express';
import { supabaseAdmin } from '../config/supabase';
import { sendTelegramMessage } from '../config/telegram';
import { handleGuestMessage } from '../services/chat.service';
import { routeHostToGuest } from '../services/escalation.service';
import { resolveEscalation, connectHost } from '../services/escalation.service';

const router = Router();

router.post('/telegram', async (req, res) => {
  try {
    const update = req.body;

    // ─── CALLBACK QUERIES (Button presses) ───
    if (update.callback_query) {
      const callbackData = update.callback_query.data as string;
      const chatId = String(update.callback_query.message.chat.id);

      if (callbackData.startsWith('select_')) {
        const bookingId = callbackData.replace('select_', '');
        await connectHost(bookingId, chatId);
        await sendTelegramMessage(chatId, '🔗 Connected! Messages from this guest will now come here. Reply directly.');
      } else if (callbackData.startsWith('resolved_')) {
        const bookingId = callbackData.replace('resolved_', '');
        await resolveEscalation(bookingId);
        await sendTelegramMessage(chatId, '✅ Resolved. Alfred has resumed control.');
      }

      res.sendStatus(200);
      return;
    }

    // ─── TEXT MESSAGES ───
    if (!update.message?.text) {
      res.sendStatus(200);
      return;
    }

    const chatId = String(update.message.chat.id);
    const text = update.message.text;

    // ─── /start COMMAND ───
    if (text.startsWith('/start')) {
      const payload = text.replace('/start', '').trim();

      // Host activation
      if (payload.startsWith('host_')) {
        const code = payload.replace('host_', '');
        const { data: host } = await supabaseAdmin
          .from('hosts')
          .select('*')
          .eq('TG_verification_code', code)
          .single();

        if (host) {
          await supabaseAdmin
            .from('hosts')
            .update({ telegram_chat_id: chatId })
            .eq('id', host.id);
          await sendTelegramMessage(chatId, '✅ Connected! You will receive escalation alerts here.');
        } else {
          await sendTelegramMessage(chatId, '❌ Invalid verification code.');
        }
        res.sendStatus(200);
        return;
      }

      // Path D: Incomplete Start
      if (!payload) {
        await sendTelegramMessage(chatId,
          'Por favor usa el enlace completo de tu mensaje de Airbnb. No escribas /start manualmente.');
        res.sendStatus(200);
        return;
      }

      // Guest activation — look up booking
      const bookingId = payload;
      const { data: conversation } = await supabaseAdmin
        .from('conversations')
        .select('*')
        .eq('booking_id', bookingId)
        .single();

      // Path C: Stranger
      if (!conversation) {
        await sendTelegramMessage(chatId,
          'No te reconozco. Por favor usa el enlace que recibiste en tu mensaje de Airbnb.');
        res.sendStatus(200);
        return;
      }

      // Path E: Expired
      if (conversation.check_out_date) {
        const checkOutDate = new Date(conversation.check_out_date);
        const yesterday = new Date();
        yesterday.setDate(yesterday.getDate() - 1);
        if (checkOutDate < yesterday) {
          const { data: property } = await supabaseAdmin
            .from('properties')
            .select('owner_id')
            .eq('id', conversation.property_id)
            .single();
          const { data: host } = await supabaseAdmin
            .from('hosts')
            .select('telegram_chat_id, name')
            .eq('id', property!.owner_id)
            .single();

          await sendTelegramMessage(chatId,
            `Tu estancia ha terminado. He enviado tu mensaje a ${host!.name}.`);
          if (host!.telegram_chat_id) {
            await sendTelegramMessage(host!.telegram_chat_id,
              `[Post-checkout message from ${conversation.guest_name}]: ${text}`);
          }
          res.sendStatus(200);
          return;
        }
      }

      // Valid activation
      await supabaseAdmin
        .from('conversations')
        .update({ telegram_chat_id: chatId, platform: 'telegram' })
        .eq('booking_id', bookingId);

      const { data: property } = await supabaseAdmin
        .from('properties')
        .select('name')
        .eq('id', conversation.property_id)
        .single();

      await sendTelegramMessage(chatId,
        `Welcome to ${property!.name}, ${conversation.guest_name}! 🌴\n\nI'm Alfred, your AI assistant. I have your check-in details ready.\n\nWhat would you like to know?`);

      res.sendStatus(200);
      return;
    }

    // ─── REGULAR MESSAGES ───

    // Check if HOST
    const { data: host } = await supabaseAdmin
      .from('hosts')
      .select('*')
      .eq('telegram_chat_id', chatId)
      .single();

    if (host && host.active_conversation_id) {
      await routeHostToGuest(host, text);
      res.sendStatus(200);
      return;
    }

    // Check if GUEST
    const { data: conversation } = await supabaseAdmin
      .from('conversations')
      .select('*')
      .eq('telegram_chat_id', chatId)
      .single();

    if (!conversation) {
      // Path C: Stranger
      await sendTelegramMessage(chatId,
        'No te reconozco. Por favor usa el enlace que recibiste en tu mensaje de Airbnb.');
      res.sendStatus(200);
      return;
    }

    // Path E: Expired recheck
    if (conversation.check_out_date) {
      const checkOutDate = new Date(conversation.check_out_date);
      const yesterday = new Date();
      yesterday.setDate(yesterday.getDate() - 1);
      if (checkOutDate < yesterday) {
        const { data: property } = await supabaseAdmin
          .from('properties')
          .select('owner_id')
          .eq('id', conversation.property_id)
          .single();
        const { data: hostForExpired } = await supabaseAdmin
          .from('hosts')
          .select('telegram_chat_id, name')
          .eq('id', property!.owner_id)
          .single();

        await sendTelegramMessage(chatId,
          `Tu estancia ha terminado. He enviado tu mensaje a ${hostForExpired!.name}.`);
        if (hostForExpired!.telegram_chat_id) {
          await sendTelegramMessage(hostForExpired!.telegram_chat_id,
            `[Post-checkout from ${conversation.guest_name}]: ${text}`);
        }
        res.sendStatus(200);
        return;
      }
    }

    // Valid guest message
    await handleGuestMessage(conversation, text, null);
    res.sendStatus(200);

  } catch (error: any) {
    console.error('Telegram webhook error:', error);
    res.sendStatus(200); // Always return 200 to Telegram to prevent retries
  }
});

export default router;
```

## File: `/src/services/links.service.ts`

```typescript
import { supabaseAdmin } from '../config/supabase';
import { GenerateLinkResponse } from '../types/api';
import crypto from 'crypto';

export async function generateLinks(
  type: 'guest' | 'host',
  bookingId?: string,
  hostId?: string
): Promise<GenerateLinkResponse> {

  if (type === 'guest') {
    if (!bookingId) throw new Error('booking_id required for guest links');

    const { data: conversation } = await supabaseAdmin
      .from('conversations')
      .select('booking_id')
      .eq('booking_id', bookingId)
      .single();

    if (!conversation) throw new Error('Booking not found');

    return {
      telegram_url: `https://t.me/${process.env.TELEGRAM_BOT_USERNAME}?start=${bookingId}`,
      web_url: `${process.env.APP_URL}/chat?booking=${bookingId}`,
    };
  }

  if (type === 'host') {
    if (!hostId) throw new Error('host_id required for host links');

    const { data: host } = await supabaseAdmin
      .from('hosts')
      .select('TG_verification_code')
      .eq('id', hostId)
      .single();

    let code = host?.TG_verification_code;
    if (!code) {
      code = crypto.randomBytes(3).toString('hex').toUpperCase(); // 6 char hex
      await supabaseAdmin
        .from('hosts')
        .update({ TG_verification_code: code })
        .eq('id', hostId);
    }

    return {
      telegram_url: `https://t.me/${process.env.TELEGRAM_BOT_USERNAME}?start=host_${code}`,
    };
  }

  throw new Error('Invalid link type');
}
```

### PHASE 2 TEST CRITERIA

```
□ Generate Magic Link for test booking
  → Valid Telegram deep link returned

□ Guest clicks Telegram link, sends /start Booking_123
  → Conversation activated, telegram_chat_id stored
  → "Welcome to [Property]" message received

□ Guest sends "What's the WiFi password?"
  → Pinecone retrieves connectivity chunk
  → Gemini generates correct response
  → Response received on Telegram
  → 2 rows in messages table (guest + ai)

□ Guest sends hostile message
  → sentiment = 'hostility' in messages
  → conversation.is_escalated = TRUE
  → Host receives 🚨 alert on Telegram with Connect/Resolve buttons

□ Stranger sends message
  → "No te reconozco" response, no DB logging

□ Expired booking message
  → Forward to host, inform guest
```

---

# PHASE 3: GUEST WEB APP

## Vercel Project File Structure

```
alfred-web/
├── package.json
├── next.config.js
├── app/
│   ├── layout.tsx
│   ├── page.tsx                    # Landing/marketing page
│   ├── chat/
│   │   └── page.tsx                # Guest chat: /chat?booking=Booking_123
│   ├── admin/
│   │   ├── layout.tsx              # Admin layout with auth check
│   │   ├── page.tsx                # Overview dashboard
│   │   ├── tenants/page.tsx
│   │   ├── conversations/page.tsx
│   │   ├── knowledge/page.tsx
│   │   └── team/page.tsx
│   └── api/
│       └── (none — API lives on Render)
├── components/
│   ├── chat/
│   │   ├── ChatWindow.tsx
│   │   ├── MessageBubble.tsx
│   │   ├── ChatInput.tsx
│   │   └── MediaUpload.tsx
│   └── admin/
│       ├── StatCard.tsx
│       ├── ConversationList.tsx
│       └── KnowledgeTable.tsx
├── lib/
│   ├── supabase-browser.ts         # Supabase client for browser
│   └── api.ts                      # Fetch wrapper for Render API
└── styles/
    └── globals.css
```

### Key Implementation: `/app/chat/page.tsx`

```typescript
// Guest Web App chat page
// URL: /chat?booking=Booking_123

'use client';

import { useSearchParams } from 'next/navigation';
import { useEffect, useState, useRef } from 'react';
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
);

const RENDER_API = process.env.NEXT_PUBLIC_RENDER_API_URL;

interface Message {
  id: string;
  sender_type: 'guest' | 'ai' | 'host' | 'system';
  content: string;
  created_at: string;
}

export default function ChatPage() {
  const searchParams = useSearchParams();
  const bookingId = searchParams.get('booking');
  const [messages, setMessages] = useState<Message[]>([]);
  const [input, setInput] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const messagesEndRef = useRef<HTMLDivElement>(null);

  // Load existing messages
  useEffect(() => {
    if (!bookingId) { setError('Invalid booking link'); return; }

    const loadMessages = async () => {
      const { data, error } = await supabase
        .from('messages')
        .select('id, sender_type, content, created_at')
        .eq('booking_id', bookingId)
        .order('created_at', { ascending: true });

      if (error) { setError('Could not load messages'); return; }
      setMessages(data || []);
    };

    loadMessages();

    // Subscribe to new messages in real-time
    const channel = supabase
      .channel(`messages:${bookingId}`)
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'messages',
          filter: `booking_id=eq.${bookingId}`,
        },
        (payload) => {
          setMessages(prev => [...prev, payload.new as Message]);
        }
      )
      .subscribe();

    return () => { supabase.removeChannel(channel); };
  }, [bookingId]);

  // Auto-scroll
  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages]);

  const sendMessage = async () => {
    if (!input.trim() || !bookingId) return;
    setLoading(true);

    try {
      await fetch(`${RENDER_API}/api/messages/web-incoming`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          booking_id: bookingId,
          content: input.trim(),
        }),
      });
      setInput('');
    } catch (err) {
      setError('Failed to send message');
    }
    setLoading(false);
  };

  // Render: build your chat UI here
  // Use messages array, input state, sendMessage function
  // Style with Tailwind or your preferred CSS
}
```

---

# PHASE 4: ESCALATION + LIVE TUNNEL

## File: `/src/services/escalation.service.ts`

```typescript
import { supabaseAdmin } from '../config/supabase';
import { sendTelegramMessage } from '../config/telegram';
import { learningLoop } from './learning.service';
import { Conversation, Host, Property } from '../types/database';

export async function triggerEscalation(
  conversation: Conversation,
  reason: string
): Promise<void> {
  // Update conversation
  await supabaseAdmin
    .from('conversations')
    .update({
      is_escalated: true,
      escalation_reason: reason,
      requires_attention: true,
    })
    .eq('booking_id', conversation.booking_id);

  // Get host
  const { data: property } = await supabaseAdmin
    .from('properties')
    .select('name, owner_id')
    .eq('id', conversation.property_id)
    .single();

  const { data: host } = await supabaseAdmin
    .from('hosts')
    .select('telegram_chat_id')
    .eq('id', property!.owner_id)
    .single();

  if (!host?.telegram_chat_id) return;

  // Send alert with action buttons
  const alert = `🚨 <b>ALFRED ESCALATION</b>\n━━━━━━━━━━━━━━━━━━━━\n👤 ${conversation.guest_name}\n🏠 ${property!.name}\n⚠️ Reason: ${reason}`;

  await sendTelegramMessage(host.telegram_chat_id, alert, {
    inline_keyboard: [
      [
        { text: '🔗 Connect', callback_data: `select_${conversation.booking_id}` },
        { text: '✅ Mark Resolved', callback_data: `resolved_${conversation.booking_id}` },
      ],
    ],
  });
}

export async function connectHost(bookingId: string, hostChatId: string): Promise<void> {
  // Find host by chat ID
  const { data: host } = await supabaseAdmin
    .from('hosts')
    .select('id')
    .eq('telegram_chat_id', hostChatId)
    .single();

  if (!host) return;

  // Set The Lock
  await supabaseAdmin
    .from('hosts')
    .update({ active_conversation_id: bookingId })
    .eq('id', host.id);
}

export async function routeGuestToHost(
  conversation: Conversation,
  text: string,
  messageId: string
): Promise<void> {
  const { data: property } = await supabaseAdmin
    .from('properties')
    .select('name, owner_id')
    .eq('id', conversation.property_id)
    .single();

  const { data: host } = await supabaseAdmin
    .from('hosts')
    .select('*')
    .eq('id', property!.owner_id)
    .single();

  if (!host?.telegram_chat_id) return;
  if (host.active_conversation_id !== conversation.booking_id) return;

  // Forward to host with Mark Resolved button
  const formatted = `💬 <b>[${conversation.guest_name}]</b> at ${property!.name}:\n${text}`;

  await sendTelegramMessage(host.telegram_chat_id, formatted, {
    inline_keyboard: [
      [{ text: '✅ Mark Resolved', callback_data: `resolved_${conversation.booking_id}` }],
    ],
  });
}

export async function routeHostToGuest(host: Host, text: string): Promise<void> {
  if (!host.active_conversation_id) return;

  const { data: conversation } = await supabaseAdmin
    .from('conversations')
    .select('*')
    .eq('booking_id', host.active_conversation_id)
    .single();

  if (!conversation) return;

  // Log with escalation flag
  await supabaseAdmin.from('messages').insert({
    booking_id: conversation.booking_id,
    sender_type: 'host',
    content: text,
    is_escalated_interaction: true,
    property_id: conversation.property_id,
  });

  // Forward to guest (raw text)
  if (conversation.platform === 'telegram' && conversation.telegram_chat_id) {
    await sendTelegramMessage(conversation.telegram_chat_id, text);
  }
  // Web: Supabase Realtime delivers automatically via INSERT trigger
}

export async function resolveEscalation(bookingId: string): Promise<void> {
  // ATOMIC SEQUENCE

  // 1. Get conversation + property + host
  const { data: conversation } = await supabaseAdmin
    .from('conversations')
    .select('*, properties!inner(owner_id, name)')
    .eq('booking_id', bookingId)
    .single();

  if (!conversation) return;

  // 2. Close escalation
  await supabaseAdmin
    .from('conversations')
    .update({ is_escalated: false, requires_attention: false })
    .eq('booking_id', bookingId);

  // 3. Free host (clear The Lock)
  await supabaseAdmin
    .from('hosts')
    .update({ active_conversation_id: null })
    .eq('id', (conversation as any).properties.owner_id);

  // 4. Notify guest
  const systemMsg = 'Issue Resolved. Alfred has resumed control. How else can I help?';
  await supabaseAdmin.from('messages').insert({
    booking_id: bookingId,
    sender_type: 'system',
    content: systemMsg,
    property_id: conversation.property_id,
  });

  if (conversation.platform === 'telegram' && conversation.telegram_chat_id) {
    await sendTelegramMessage(conversation.telegram_chat_id, systemMsg);
  }

  // 5. Trigger Learning Loop
  await learningLoop(bookingId);
}

export async function ghostSend(
  propertyId: string,
  bookingId: string,
  content: string
): Promise<void> {
  const { data: conversation } = await supabaseAdmin
    .from('conversations')
    .select('*')
    .eq('booking_id', bookingId)
    .single();

  if (!conversation) return;

  // Log as 'ai' (ghost)
  await supabaseAdmin.from('messages').insert({
    booking_id: bookingId,
    sender_type: 'ai', // Appears as Alfred
    content: content,
    property_id: propertyId,
  });

  if (conversation.platform === 'telegram' && conversation.telegram_chat_id) {
    await sendTelegramMessage(conversation.telegram_chat_id, content);
  }
}
```

---

# PHASE 5: LEARNING LOOP

## File: `/src/services/learning.service.ts`

```typescript
import { supabaseAdmin } from '../config/supabase';
import { callGeminiJSON } from '../config/gemini';
import { DistillationResult } from '../types/api';

export async function learningLoop(bookingId: string): Promise<void> {
  // ─── STEP 1: BATCH STAMP ───
  const { data: stamped, count } = await supabaseAdmin
    .from('messages')
    .update({ resolution_status: 'resolved' })
    .eq('booking_id', bookingId)
    .eq('is_escalated_interaction', true)
    .is('resolution_status', null)
    .select('id');

  if (!stamped || stamped.length === 0) return; // Nothing to learn

  // ─── STEP 2: DATA RETRIEVAL ───
  const { data: transcript } = await supabaseAdmin
    .from('messages')
    .select('*')
    .eq('booking_id', bookingId)
    .eq('is_escalated_interaction', true)
    .eq('resolution_status', 'resolved')
    .order('created_at', { ascending: true });

  if (!transcript || transcript.length === 0) return;

  // ─── STEP 3: DISTILLATION ───
  const distilled = await callGeminiJSON<DistillationResult>(
    `Analyze this escalated conversation between a vacation rental guest and the property host.

CONVERSATION TRANSCRIPT:
${transcript.map(m => `[${m.sender_type}]: ${m.content}`).join('\n')}

TASK:
1. Identify the CORE root cause problem the guest experienced.
2. Identify the SUCCESSFUL solution the host provided.
3. Discard ALL phatic communication (greetings, apologies, filler).
4. Extract ONLY actionable knowledge that would help an AI handle this situation next time.

RESPOND WITH STRICT JSON (no markdown):
{
  "problem_summary": "concise description of what went wrong",
  "solution_summary": "concise description of how it was fixed, including any specific details (passwords, codes, locations, instructions)",
  "category": "one of: connectivity, access, appliances, amenities, cleaning, noise, safety, checkout, other"
}`,
    'You are an expert data analyst specializing in extracting actionable knowledge from conversations. Be precise and concise. Output only valid JSON.'
  );

  // ─── STEP 4: KNOWLEDGE PERSISTENCE ───
  const { data: conversation } = await supabaseAdmin
    .from('conversations')
    .select('property_id')
    .eq('booking_id', bookingId)
    .single();

  const messageIds = transcript.map(m => m.id);

  await supabaseAdmin.from('knowledge_base').insert({
    property_id: conversation!.property_id,
    problem_summary: distilled.problem_summary,
    solution_summary: distilled.solution_summary,
    category: distilled.category,
    source_message_ids: messageIds,
    original_transcript: transcript,
    is_verified: true,
  });

  // ─── STEP 5: MARK AS LEARNED ───
  await supabaseAdmin
    .from('messages')
    .update({ is_learned: true })
    .in('id', messageIds);
}
```

---

# PHASE 6: HOST-SYSTEM CHAT

## File: `/src/services/systemchat.service.ts`

```typescript
import { supabaseAdmin } from '../config/supabase';
import { callGeminiJSON } from '../config/gemini';
import { vectorize } from './vectorizer.service';
import { SystemChatResponse } from '../types/api';

interface SystemChatResult {
  updated_master_json: Record<string, any>;
  change_summary: string;
  fields_changed: string[];
}

export async function handleSystemChat(
  propertyId: string,
  message: string,
  mediaUrl?: string
): Promise<SystemChatResponse> {
  // STEP 1: If voice note, transcribe (TODO: implement audio transcription)
  let processedMessage = message;

  // STEP 2: Fetch current Master JSON
  const { data: property } = await supabaseAdmin
    .from('properties')
    .select('master_json')
    .eq('id', propertyId)
    .single();

  if (!property?.master_json) {
    return {
      success: false,
      change_summary: 'No Master JSON found for this property',
      response: 'This property hasn\'t been set up yet. Please complete the onboarding first.',
    };
  }

  // STEP 3: Gemini identifies and applies update
  const result = await callGeminiJSON<SystemChatResult>(
    `You manage a vacation rental property's knowledge base.
The host wants to update their property information.

CURRENT MASTER JSON:
${JSON.stringify(property.master_json, null, 2)}

HOST'S INSTRUCTION:
"${processedMessage}"

TASK:
1. Identify which field(s) the host wants to update.
2. Apply the change to the master_json.
3. Return the COMPLETE updated master_json (not just the changed fields).

RESPOND WITH STRICT JSON:
{
  "updated_master_json": { ...complete updated JSON... },
  "change_summary": "Updated WiFi password from OldPass to Beach2024",
  "fields_changed": ["connectivity.wifi_password"]
}`,
    'You are a precise property data manager. Apply changes exactly as instructed. Output only valid JSON.'
  );

  // STEP 4: Save
  await supabaseAdmin
    .from('properties')
    .update({ master_json: result.updated_master_json })
    .eq('id', propertyId);

  // STEP 5: Re-vectorize
  await vectorize(propertyId);

  return {
    success: true,
    change_summary: result.change_summary,
    response: `Got it! I've updated: ${result.change_summary}`,
  };
}
```

---

# PHASE 7: REMAINING ROUTES (Dashboard API + Admin)

## File: `/src/routes/properties.ts`

```typescript
import { Router } from 'express';
import { supabaseAdmin } from '../config/supabase';

const router = Router();

// List properties for authenticated host
router.get('/', async (req, res) => {
  // TODO: Extract host_id from auth token
  const hostId = req.headers['x-host-id'] as string; // Placeholder — use proper auth middleware

  const { data, error } = await supabaseAdmin
    .from('properties')
    .select('id, name, status, airbnb_url, created_at, conflict_status')
    .eq('owner_id', hostId)
    .order('created_at', { ascending: false });

  if (error) return res.status(500).json({ error: error.message });
  res.json({ data });
});

// Get property detail
router.get('/:id', async (req, res) => {
  const { data, error } = await supabaseAdmin
    .from('properties')
    .select('*')
    .eq('id', req.params.id)
    .single();

  if (error) return res.status(404).json({ error: 'Property not found' });
  res.json({ data });
});

export default router;
```

## File: `/src/routes/conversations.ts`

```typescript
import { Router } from 'express';
import { supabaseAdmin } from '../config/supabase';

const router = Router();

router.get('/', async (req, res) => {
  const hostId = req.headers['x-host-id'] as string;
  const { property_id, requires_attention } = req.query;

  let query = supabaseAdmin
    .from('conversations')
    .select('*, properties!inner(name, owner_id)')
    .eq('properties.owner_id', hostId)
    .order('last_message_at', { ascending: false });

  if (property_id) query = query.eq('property_id', property_id);
  if (requires_attention === 'true') query = query.eq('requires_attention', true);

  const { data, error } = await query;
  if (error) return res.status(500).json({ error: error.message });
  res.json({ data });
});

router.get('/:bookingId/messages', async (req, res) => {
  const { data, error } = await supabaseAdmin
    .from('messages')
    .select('*')
    .eq('booking_id', req.params.bookingId)
    .order('created_at', { ascending: true });

  if (error) return res.status(500).json({ error: error.message });
  res.json({ data });
});

export default router;
```

## File: `/src/routes/knowledge.ts`

```typescript
import { Router } from 'express';
import { supabaseAdmin } from '../config/supabase';

const router = Router();

router.get('/', async (req, res) => {
  const hostId = req.headers['x-host-id'] as string;

  const { data, error } = await supabaseAdmin
    .from('knowledge_base')
    .select('*, properties!inner(name, owner_id)')
    .eq('properties.owner_id', hostId)
    .order('created_at', { ascending: false });

  if (error) return res.status(500).json({ error: error.message });
  res.json({ data });
});

router.patch('/:id', async (req, res) => {
  const { action, problem_summary, solution_summary } = req.body;

  if (action === 'confirm') {
    await supabaseAdmin
      .from('knowledge_base')
      .update({ is_verified: true })
      .eq('id', req.params.id);
  } else if (action === 'deny') {
    await supabaseAdmin
      .from('knowledge_base')
      .update({ is_verified: false })
      .eq('id', req.params.id);
  } else if (action === 'modify') {
    await supabaseAdmin
      .from('knowledge_base')
      .update({
        problem_summary: problem_summary,
        solution_summary: solution_summary,
        is_verified: true,
      })
      .eq('id', req.params.id);
  }

  res.json({ success: true });
});

export default router;
```

## File: `/src/routes/admin.ts`

```typescript
import { Router } from 'express';
import { supabaseAdmin } from '../config/supabase';

const router = Router();

// TODO: Add admin auth middleware

router.get('/overview', async (req, res) => {
  const [conversations, escalated, knowledge, messages] = await Promise.all([
    supabaseAdmin.from('conversations').select('booking_id', { count: 'exact', head: true }),
    supabaseAdmin.from('conversations').select('booking_id', { count: 'exact', head: true }).eq('is_escalated', true),
    supabaseAdmin.from('knowledge_base').select('id', { count: 'exact', head: true }),
    supabaseAdmin.from('messages').select('id', { count: 'exact', head: true })
      .gte('created_at', new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString()),
  ]);

  res.json({
    total_conversations: conversations.count,
    active_escalations: escalated.count,
    knowledge_entries: knowledge.count,
    messages_last_24h: messages.count,
  });
});

router.get('/tenants', async (req, res) => {
  const { data } = await supabaseAdmin
    .from('hosts')
    .select('id, name, email, created_at, properties(id, name, status)');
  res.json({ data });
});

router.get('/conversations', async (req, res) => {
  const { data } = await supabaseAdmin
    .from('conversations')
    .select('*, properties(name)')
    .order('last_message_at', { ascending: false })
    .limit(100);
  res.json({ data });
});

router.get('/knowledge-base', async (req, res) => {
  const { data } = await supabaseAdmin
    .from('knowledge_base')
    .select('*, properties(name)')
    .order('created_at', { ascending: false });
  res.json({ data });
});

export default router;
```

---

# FINAL CHECKLIST

```
PHASE 0:
□ Supabase project created, schema applied, RLS active
□ Render deploys, /health returns 200
□ Vercel deploys, landing page loads
□ Flutter authenticates with Supabase
□ Pinecone index created (768 dimensions, cosine)
□ Telegram bot created, webhook set

PHASE 1:
□ Scraper: Airbnb URL → scraped_markdown → Scraped
□ Ingestor: File upload → ingested_markdown → Ingested → auto-merge
□ Merger: No conflicts → master_json + Pinecone vectors
□ Merger: Conflicts → conflicts table + Waiting status
□ Resolver: Resolutions → final master_json + Pinecone vectors
□ Flutter: Property list + Add + Upload + Questionnaire

PHASE 2:
□ Magic Link generation
□ Telegram /start → activation + welcome
□ Guest message → AI response via RAG
□ Sentiment analysis on every message
□ Error paths: Stranger, Incomplete, Expired
□ Flutter: Conversation list + read-only chat

PHASE 3:
□ Guest Web App: /chat?booking=X loads chat
□ Real-time messages via Supabase Realtime
□ Same response quality as Telegram

PHASE 4:
□ Hostile message → escalation alert to host
□ Connect → Lock set → Guest→Host routing
□ Host→Guest routing (raw text)
□ Kill Switch: atomic close + guest notified
□ Ghost Mode: host sends as Alfred
□ Flutter: Escalation alerts, Chat interactive

PHASE 5:
□ Kill Switch → Batch Stamp
□ Transcript → Gemini distillation → knowledge_base INSERT
□ is_learned flagged
□ New guest asks same question → AI uses learned knowledge
□ Flutter: Lessons Learned (confirm/deny/modify)

PHASE 6:
□ System Chat: "WiFi is now X" → master_json + Pinecone updated
□ Flutter: System Chat screen

PHASE 7:
□ Admin auth with role check
□ Overview, Tenants, Conversations, Knowledge screens
□ Team management
```

---

*END OF IDE BUILD SPEC v3.2*
