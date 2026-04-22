# ALFRED V2 — IDE UPGRADE SPEC
# Feed this document to Cursor / Claude Code when upgrading from V1.
# PREREQUISITE: V1 is fully deployed and tested (Document: Alfred_V1_IDE_Spec.md)

---

## CONTEXT

Alfred V1 is running with 20-30 properties. V2 scales it to 500+ properties and 200+ concurrent conversations. This document describes ONLY the changes and additions to the V1 codebase.

**What changes:**
1. All heavy processing moves to background jobs (BullMQ + Redis)
2. Hot data gets cached (Redis)
3. WhatsApp becomes a third messaging channel
4. Full observability (Sentry + Axiom)
5. Email notifications (Resend)
6. Product analytics (PostHog)

---

# NEW ENVIRONMENT VARIABLES

Add to existing `.env`:

```env
# Upstash Redis
UPSTASH_REDIS_URL=rediss://default:xxx@xxx.upstash.io:6379

# Sentry
SENTRY_DSN=https://xxx@xxx.ingest.sentry.io/xxx
SENTRY_ENVIRONMENT=production

# Axiom
AXIOM_TOKEN=xaat-xxx
AXIOM_DATASET=alfred-logs

# Resend
RESEND_API_KEY=re_xxx
RESEND_FROM_EMAIL=Alfred <alerts@yourdomain.com>

# PostHog
POSTHOG_API_KEY=phc_xxx
POSTHOG_HOST=https://app.posthog.com

# WhatsApp Business API
WHATSAPP_PHONE_NUMBER_ID=123456789
WHATSAPP_ACCESS_TOKEN=EAAx...
WHATSAPP_VERIFY_TOKEN=your-verify-token
WHATSAPP_WEBHOOK_URL=https://your-render-app.onrender.com/api/webhooks/whatsapp
```

---

# NEW DEPENDENCIES

```bash
npm install bullmq ioredis @sentry/node @axiomhq/js resend posthog-node
```

---

# UPDATED FILE STRUCTURE (additions to V1)

```
alfred-backend/
├── src/
│   ├── config/
│   │   ├── redis.ts                # NEW — Redis client
│   │   ├── sentry.ts               # NEW — Sentry init
│   │   ├── axiom.ts                # NEW — Axiom logger
│   │   ├── resend.ts               # NEW — Resend email client
│   │   ├── posthog.ts              # NEW — PostHog analytics
│   │   └── whatsapp.ts             # NEW — WhatsApp Business API helper
│   ├── queues/
│   │   ├── index.ts                # NEW — Queue definitions
│   │   ├── pipeline.worker.ts      # NEW — Pipeline background worker
│   │   ├── ai-response.worker.ts   # NEW — AI response background worker
│   │   ├── outbound.worker.ts      # NEW — Outbound message worker (rate-limited)
│   │   └── learning.worker.ts      # NEW — Learning Loop background worker
│   ├── cache/
│   │   └── index.ts                # NEW — Redis cache get/set/invalidate
│   ├── services/
│   │   ├── email.service.ts        # NEW — Email templates + sending
│   │   └── analytics.service.ts    # NEW — PostHog event tracking
│   ├── routes/
│   │   └── webhooks.ts             # MODIFIED — add WhatsApp webhook
```

---

# V2-PHASE 0: NEW CONFIG FILES

## File: `/src/config/redis.ts`

```typescript
import Redis from 'ioredis';

export const redis = new Redis(process.env.UPSTASH_REDIS_URL!, {
  maxRetriesPerRequest: 3,
  enableReadyCheck: false,
  tls: {}, // Required for Upstash
});

// Connection for BullMQ (needs separate instance)
export const createRedisConnection = () =>
  new Redis(process.env.UPSTASH_REDIS_URL!, {
    maxRetriesPerRequest: null, // BullMQ requirement
    enableReadyCheck: false,
    tls: {},
  });
```

## File: `/src/config/sentry.ts`

```typescript
import * as Sentry from '@sentry/node';

export function initSentry() {
  Sentry.init({
    dsn: process.env.SENTRY_DSN,
    environment: process.env.SENTRY_ENVIRONMENT || 'development',
    tracesSampleRate: 0.2, // 20% of transactions
    integrations: [
      Sentry.httpIntegration(),
      Sentry.expressIntegration(),
    ],
  });
}

export function setSentryContext(context: {
  property_id?: string;
  booking_id?: string;
  host_id?: string;
  platform?: string;
  is_escalated?: boolean;
}) {
  Sentry.setContext('alfred', context);
}

export { Sentry };
```

## File: `/src/config/axiom.ts`

```typescript
import { Axiom } from '@axiomhq/js';

const axiom = new Axiom({
  token: process.env.AXIOM_TOKEN!,
});

const DATASET = process.env.AXIOM_DATASET || 'alfred-logs';

interface LogData {
  [key: string]: any;
}

export const logger = {
  info: (event: string, data: LogData = {}) => {
    axiom.ingest(DATASET, [{ _time: new Date().toISOString(), level: 'info', event, ...data }]);
    console.log(`[INFO] ${event}`, JSON.stringify(data));
  },

  warn: (event: string, data: LogData = {}) => {
    axiom.ingest(DATASET, [{ _time: new Date().toISOString(), level: 'warn', event, ...data }]);
    console.warn(`[WARN] ${event}`, JSON.stringify(data));
  },

  error: (event: string, data: LogData = {}) => {
    axiom.ingest(DATASET, [{ _time: new Date().toISOString(), level: 'error', event, ...data }]);
    console.error(`[ERROR] ${event}`, JSON.stringify(data));
  },

  // Flush on shutdown
  flush: () => axiom.flush(),
};
```

## File: `/src/config/resend.ts`

```typescript
import { Resend } from 'resend';

export const resend = new Resend(process.env.RESEND_API_KEY);
export const FROM_EMAIL = process.env.RESEND_FROM_EMAIL || 'Alfred <noreply@yourdomain.com>';
```

## File: `/src/config/posthog.ts`

```typescript
import { PostHog } from 'posthog-node';

export const posthog = new PostHog(process.env.POSTHOG_API_KEY!, {
  host: process.env.POSTHOG_HOST || 'https://app.posthog.com',
});

// Flush on shutdown
process.on('beforeExit', () => posthog.shutdown());
```

## File: `/src/config/whatsapp.ts`

```typescript
const WA_API = `https://graph.facebook.com/v18.0/${process.env.WHATSAPP_PHONE_NUMBER_ID}`;

export async function sendWhatsAppMessage(
  phoneNumber: string,
  text: string
): Promise<void> {
  await fetch(`${WA_API}/messages`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${process.env.WHATSAPP_ACCESS_TOKEN}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      messaging_product: 'whatsapp',
      to: phoneNumber,
      type: 'text',
      text: { body: text },
    }),
  });
}

export async function sendWhatsAppInteractive(
  phoneNumber: string,
  bodyText: string,
  buttons: Array<{ id: string; title: string }>
): Promise<void> {
  await fetch(`${WA_API}/messages`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${process.env.WHATSAPP_ACCESS_TOKEN}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      messaging_product: 'whatsapp',
      to: phoneNumber,
      type: 'interactive',
      interactive: {
        type: 'button',
        body: { text: bodyText },
        action: {
          buttons: buttons.map(b => ({
            type: 'reply',
            reply: { id: b.id, title: b.title },
          })),
        },
      },
    }),
  });
}

export async function downloadWhatsAppMedia(mediaId: string): Promise<Buffer> {
  // Step 1: Get media URL
  const urlResponse = await fetch(`https://graph.facebook.com/v18.0/${mediaId}`, {
    headers: { 'Authorization': `Bearer ${process.env.WHATSAPP_ACCESS_TOKEN}` },
  });
  const { url } = await urlResponse.json();

  // Step 2: Download
  const mediaResponse = await fetch(url, {
    headers: { 'Authorization': `Bearer ${process.env.WHATSAPP_ACCESS_TOKEN}` },
  });
  return Buffer.from(await mediaResponse.arrayBuffer());
}
```

---

# V2-PHASE 1: REDIS CACHE + BULLMQ QUEUES

## File: `/src/cache/index.ts`

```typescript
import { redis } from '../config/redis';
import { supabaseAdmin } from '../config/supabase';
import { Conversation, Property, KnowledgeEntry } from '../types/database';

const TTL = 3600; // 1 hour in seconds

// ─── CONVERSATION CACHE ───

export async function getCachedConversation(bookingId: string): Promise<Conversation | null> {
  const cached = await redis.get(`conversation:${bookingId}`);
  if (cached) return JSON.parse(cached);

  const { data } = await supabaseAdmin
    .from('conversations')
    .select('*')
    .eq('booking_id', bookingId)
    .single();

  if (data) {
    await redis.setex(`conversation:${bookingId}`, TTL, JSON.stringify(data));
  }
  return data;
}

export async function invalidateConversation(bookingId: string): Promise<void> {
  await redis.del(`conversation:${bookingId}`);
}

// ─── MASTER JSON CACHE ───

export async function getCachedMasterJson(propertyId: string): Promise<Record<string, any> | null> {
  const cached = await redis.get(`property:${propertyId}:master_json`);
  if (cached) return JSON.parse(cached);

  const { data } = await supabaseAdmin
    .from('properties')
    .select('master_json')
    .eq('id', propertyId)
    .single();

  if (data?.master_json) {
    await redis.setex(`property:${propertyId}:master_json`, TTL, JSON.stringify(data.master_json));
  }
  return data?.master_json || null;
}

export async function invalidateMasterJson(propertyId: string): Promise<void> {
  await redis.del(`property:${propertyId}:master_json`);
}

// ─── KNOWLEDGE BASE CACHE ───

export async function getCachedKnowledge(propertyId: string): Promise<KnowledgeEntry[]> {
  const cached = await redis.get(`property:${propertyId}:knowledge`);
  if (cached) return JSON.parse(cached);

  const { data } = await supabaseAdmin
    .from('knowledge_base')
    .select('*')
    .eq('property_id', propertyId)
    .eq('is_verified', true);

  const entries = data || [];
  await redis.setex(`property:${propertyId}:knowledge`, TTL, JSON.stringify(entries));
  return entries;
}

export async function invalidateKnowledge(propertyId: string): Promise<void> {
  await redis.del(`property:${propertyId}:knowledge`);
}

// ─── HOST LOCK CACHE ───

export async function getCachedHostLock(hostId: string): Promise<string | null> {
  const cached = await redis.get(`host:${hostId}:lock`);
  if (cached !== null) return cached === 'null' ? null : cached;

  const { data } = await supabaseAdmin
    .from('hosts')
    .select('active_conversation_id')
    .eq('id', hostId)
    .single();

  const lockValue = data?.active_conversation_id || null;
  await redis.set(`host:${hostId}:lock`, lockValue || 'null');
  return lockValue;
}

export async function invalidateHostLock(hostId: string): Promise<void> {
  await redis.del(`host:${hostId}:lock`);
}
```

## File: `/src/queues/index.ts`

```typescript
import { Queue, Worker } from 'bullmq';
import { createRedisConnection } from '../config/redis';

const connection = createRedisConnection();

// ─── QUEUE DEFINITIONS ───

export const pipelineQueue = new Queue('pipeline', { connection });
export const aiResponseQueue = new Queue('ai-response', {
  connection,
  defaultJobOptions: {
    attempts: 3,
    backoff: { type: 'exponential', delay: 2000 },
  },
});
export const outboundQueue = new Queue('outbound', { connection });
export const learningQueue = new Queue('learning', { connection });

// ─── JOB TYPE DEFINITIONS ───

export interface PipelineJob {
  type: 'scrape' | 'ingest' | 'merge' | 'resolve' | 'vectorize';
  property_id: string;
  data: Record<string, any>;
}

export interface AiResponseJob {
  booking_id: string;
  property_id: string;
  message_id: string;
  text: string;
  platform: string;
  telegram_chat_id: string | null;
  whatsapp_phone: string | null;  // V2: WhatsApp
  is_escalated: boolean;
  preferred_language: string | null;
  priority: number;  // 1 = escalated (high), 5 = normal
}

export interface OutboundJob {
  platform: 'telegram' | 'whatsapp' | 'web';
  chat_id?: string;         // Telegram
  phone_number?: string;    // WhatsApp
  text: string;
  reply_markup?: any;       // Telegram inline keyboard
  buttons?: Array<{ id: string; title: string }>;  // WhatsApp interactive
}

export interface LearningJob {
  booking_id: string;
}
```

## File: `/src/queues/ai-response.worker.ts`

This is the **most important V2 change**. The V1 synchronous `handleGuestMessage` gets split: the webhook just logs + enqueues, and this worker does the heavy lifting.

```typescript
import { Worker, Job } from 'bullmq';
import { createRedisConnection } from '../config/redis';
import { supabaseAdmin } from '../config/supabase';
import { callGemini, embedText } from '../config/gemini';
import { getIndex } from '../config/pinecone';
import { analyzeSentiment } from '../services/sentiment.service';
import { triggerEscalation } from '../services/escalation.service';
import { getCachedKnowledge } from '../cache';
import { outboundQueue, OutboundJob } from './index';
import { AiResponseJob } from './index';
import { logger } from '../config/axiom';
import { Sentry, setSentryContext } from '../config/sentry';

const worker = new Worker<AiResponseJob>(
  'ai-response',
  async (job: Job<AiResponseJob>) => {
    const startTime = Date.now();
    const {
      booking_id, property_id, message_id, text,
      platform, telegram_chat_id, whatsapp_phone,
      is_escalated, preferred_language, priority
    } = job.data;

    setSentryContext({ booking_id, property_id, platform, is_escalated });

    try {
      // ─── SENTIMENT ───
      const sentiment = await analyzeSentiment(text);
      await supabaseAdmin
        .from('messages')
        .update({ sentiment })
        .eq('id', message_id);

      if (sentiment === 'hostility' || sentiment === 'emergency') {
        const { data: conversation } = await supabaseAdmin
          .from('conversations')
          .select('*')
          .eq('booking_id', booking_id)
          .single();

        if (conversation) {
          await triggerEscalation(conversation, sentiment);
        }
      }

      // ─── RAG RETRIEVAL ───
      const embedding = await embedText(text);
      const index = getIndex();
      const ns = index.namespace(property_id);

      const queryResult = await ns.query({
        vector: embedding,
        topK: 5,
        includeMetadata: true,
      });

      const relevantContext = (queryResult.matches || [])
        .map((m: any) => m.metadata?.content || '')
        .filter(Boolean)
        .join('\n\n');

      // ─── KNOWLEDGE (cached) ───
      const knowledge = await getCachedKnowledge(property_id);
      const knowledgeContext = knowledge
        .map(k => `Problem: ${k.problem_summary}\nSolution: ${k.solution_summary}`)
        .join('\n\n');

      // ─── HISTORY ───
      const { data: recentMessages } = await supabaseAdmin
        .from('messages')
        .select('sender_type, content')
        .eq('booking_id', booking_id)
        .order('created_at', { ascending: false })
        .limit(20);

      const historyContext = (recentMessages || [])
        .reverse()
        .map(m => `${m.sender_type}: ${m.content}`)
        .join('\n');

      // ─── GENERATE ───
      const geminiStart = Date.now();
      const aiResponse = await callGemini(
        `PROPERTY INFORMATION:\n${relevantContext}\n\nLEARNED KNOWLEDGE:\n${knowledgeContext}\n\nCONVERSATION:\n${historyContext}\n\nGUEST MESSAGE:\n${text}\n\nRespond as Alfred:`,
        `You are Alfred, a friendly AI assistant for a vacation rental. Respond in ${preferred_language || 'the guest\'s language'}. Use ONLY provided info. Be concise and helpful.`
      );
      const geminiLatency = Date.now() - geminiStart;

      // ─── OUTPUT LOG ───
      await supabaseAdmin.from('messages').insert({
        booking_id,
        sender_type: 'ai',
        content: aiResponse,
        status: 'sent',
        property_id,
      });

      // ─── ENQUEUE OUTBOUND ───
      const outboundJob: OutboundJob = {
        platform: platform as any,
        text: aiResponse,
        ...(platform === 'telegram' && { chat_id: telegram_chat_id! }),
        ...(platform === 'whatsapp' && { phone_number: whatsapp_phone! }),
      };
      await outboundQueue.add('send', outboundJob);

      // ─── UPDATE CONVERSATION ───
      await supabaseAdmin
        .from('conversations')
        .update({ last_message_at: new Date().toISOString(), ai_status: 'responded' })
        .eq('booking_id', booking_id);

      // ─── LOG ───
      const totalLatency = Date.now() - startTime;
      logger.info('message.processed', {
        booking_id, property_id, platform,
        sentiment,
        pinecone_chunks: queryResult.matches?.length || 0,
        knowledge_entries: knowledge.length,
        gemini_latency_ms: geminiLatency,
        total_latency_ms: totalLatency,
        priority,
      });

    } catch (error: any) {
      Sentry.captureException(error);
      logger.error('message.processing_failed', {
        booking_id, property_id, error: error.message,
      });
      throw error; // BullMQ will retry
    }
  },
  {
    connection: createRedisConnection(),
    concurrency: 10, // Process up to 10 messages in parallel
    limiter: {
      max: 50,       // Max 50 jobs per
      duration: 1000, // 1 second — prevents Gemini rate limits
    },
  }
);

export default worker;
```

## File: `/src/queues/outbound.worker.ts`

```typescript
import { Worker, Job } from 'bullmq';
import { createRedisConnection } from '../config/redis';
import { sendTelegramMessage } from '../config/telegram';
import { sendWhatsAppMessage, sendWhatsAppInteractive } from '../config/whatsapp';
import { OutboundJob } from './index';
import { logger } from '../config/axiom';
import { Sentry } from '../config/sentry';

const worker = new Worker<OutboundJob>(
  'outbound',
  async (job: Job<OutboundJob>) => {
    const { platform, text, chat_id, phone_number, reply_markup, buttons } = job.data;

    try {
      switch (platform) {
        case 'telegram':
          if (!chat_id) throw new Error('No chat_id for Telegram');
          await sendTelegramMessage(chat_id, text, reply_markup);
          break;

        case 'whatsapp':
          if (!phone_number) throw new Error('No phone_number for WhatsApp');
          if (buttons && buttons.length > 0) {
            await sendWhatsAppInteractive(phone_number, text, buttons);
          } else {
            await sendWhatsAppMessage(phone_number, text);
          }
          break;

        case 'web':
          // Web clients receive via Supabase Realtime — no outbound needed
          break;

        default:
          throw new Error(`Unknown platform: ${platform}`);
      }

      logger.info('message.sent', { platform, success: true });
    } catch (error: any) {
      Sentry.captureException(error);
      logger.error('message.send_failed', { platform, error: error.message });
      throw error; // Retry
    }
  },
  {
    connection: createRedisConnection(),
    concurrency: 5,
    limiter: {
      max: 30,        // 30 messages per second — respects Telegram limits
      duration: 1000,
    },
  }
);

export default worker;
```

## File: `/src/queues/pipeline.worker.ts`

```typescript
import { Worker, Job } from 'bullmq';
import { createRedisConnection } from '../config/redis';
import { scrapeProperty } from '../services/scraper.service';
import { ingestFile } from '../services/ingestor.service';
import { merge } from '../services/merger.service';
import { resolveConflicts } from '../services/resolver.service';
import { vectorize } from '../services/vectorizer.service';
import { invalidateMasterJson } from '../cache';
import { PipelineJob } from './index';
import { logger } from '../config/axiom';
import { Sentry } from '../config/sentry';

const worker = new Worker<PipelineJob>(
  'pipeline',
  async (job: Job<PipelineJob>) => {
    const { type, property_id, data } = job.data;

    try {
      switch (type) {
        case 'scrape':
          await scrapeProperty(property_id, data.airbnb_url);
          logger.info('pipeline.scrape_complete', { property_id });
          break;

        case 'ingest':
          await ingestFile(property_id, data.file_url, data.file_type);
          logger.info('pipeline.ingest_complete', { property_id });
          break;

        case 'merge':
          const result = await merge(property_id);
          logger.info('pipeline.merge_complete', { property_id, has_conflicts: result.has_conflicts });
          break;

        case 'resolve':
          await resolveConflicts(property_id, data.resolutions);
          logger.info('pipeline.resolve_complete', { property_id });
          break;

        case 'vectorize':
          const chunks = await vectorize(property_id);
          logger.info('pipeline.vectorize_complete', { property_id, chunks });
          break;
      }

      // Invalidate caches after any pipeline operation
      await invalidateMasterJson(property_id);

    } catch (error: any) {
      Sentry.captureException(error);
      logger.error(`pipeline.${type}_failed`, { property_id, error: error.message });
      throw error;
    }
  },
  {
    connection: createRedisConnection(),
    concurrency: 3, // Max 3 pipeline jobs in parallel
  }
);

export default worker;
```

## File: `/src/queues/learning.worker.ts`

```typescript
import { Worker, Job } from 'bullmq';
import { createRedisConnection } from '../config/redis';
import { learningLoop } from '../services/learning.service';
import { invalidateKnowledge } from '../cache';
import { LearningJob } from './index';
import { logger } from '../config/axiom';
import { Sentry } from '../config/sentry';

const worker = new Worker<LearningJob>(
  'learning',
  async (job: Job<LearningJob>) => {
    const { booking_id } = job.data;

    try {
      await learningLoop(booking_id);

      // Invalidate knowledge cache for the property
      // (learningLoop would need to return property_id, or we look it up)
      logger.info('learning.complete', { booking_id });
    } catch (error: any) {
      Sentry.captureException(error);
      logger.error('learning.failed', { booking_id, error: error.message });
      throw error;
    }
  },
  {
    connection: createRedisConnection(),
    concurrency: 2,
  }
);

export default worker;
```

## MODIFIED: Telegram Webhook (V2 — enqueue instead of process)

The key change in the webhook handler: replace direct calls to `handleGuestMessage()` with enqueuing to `aiResponseQueue`.

```typescript
// BEFORE (V1) — in /src/routes/webhooks.ts:
await handleGuestMessage(conversation, text, null);

// AFTER (V2) — replace with:
import { aiResponseQueue, AiResponseJob } from '../queues';

// ... inside the webhook handler, where you'd call handleGuestMessage:

// Log input immediately (fast)
const { data: newMessage } = await supabaseAdmin
  .from('messages')
  .insert({
    booking_id: conversation.booking_id,
    sender_type: 'guest',
    content: text,
    status: 'unread',
    property_id: conversation.property_id,
    is_escalated_interaction: conversation.is_escalated,
  })
  .select('id')
  .single();

// Check escalation (fast — use cache)
if (conversation.is_escalated) {
  await routeGuestToHost(conversation, text, newMessage!.id);
  res.sendStatus(200);
  return;
}

// Enqueue AI response job (returns immediately)
const job: AiResponseJob = {
  booking_id: conversation.booking_id,
  property_id: conversation.property_id,
  message_id: newMessage!.id,
  text: text,
  platform: conversation.platform,
  telegram_chat_id: conversation.telegram_chat_id,
  whatsapp_phone: null, // Set for WhatsApp conversations
  is_escalated: conversation.is_escalated,
  preferred_language: conversation.preferred_language,
  priority: conversation.is_escalated ? 1 : 5,
};

await aiResponseQueue.add('respond', job, {
  priority: job.priority,
});

res.sendStatus(200); // Instant return to Telegram
```

## MODIFIED: Pipeline Routes (V2 — enqueue instead of process)

```typescript
// BEFORE (V1):
router.post('/scrape', async (req, res) => {
  await scrapeProperty(req.body.property_id, req.body.airbnb_url);
  res.json({ success: true });
});

// AFTER (V2):
import { pipelineQueue } from '../queues';

router.post('/scrape', async (req, res) => {
  await pipelineQueue.add('pipeline', {
    type: 'scrape',
    property_id: req.body.property_id,
    data: { airbnb_url: req.body.airbnb_url },
  });
  res.json({ success: true, status: 'queued' });
  // Client polls property.status or uses Supabase Realtime for completion
});
```

## MODIFIED: Escalation Service (V2 — invalidate caches)

Add cache invalidation to all state-changing functions:

```typescript
// In resolveEscalation():
import { invalidateConversation, invalidateHostLock, invalidateKnowledge } from '../cache';
import { learningQueue } from '../queues';

// After updating conversation:
await invalidateConversation(bookingId);

// After clearing host lock:
await invalidateHostLock(hostId);

// Replace direct learningLoop call with queue:
await learningQueue.add('learn', { booking_id: bookingId });
```

## MODIFIED: `/src/index.ts` (V2 — init new services + start workers)

```typescript
import { initSentry, Sentry } from './config/sentry';
import { logger } from './config/axiom';

// Initialize Sentry FIRST
initSentry();

// ... existing Express setup ...

// Import workers (they auto-start on import)
import './queues/pipeline.worker';
import './queues/ai-response.worker';
import './queues/outbound.worker';
import './queues/learning.worker';

// Sentry error handler (must be LAST middleware)
app.use(Sentry.Handlers.errorHandler());

// Graceful shutdown
process.on('SIGTERM', async () => {
  logger.info('server.shutdown');
  await logger.flush();
  process.exit(0);
});
```

---

# V2-PHASE 2: WHATSAPP WEBHOOK

## Add to `/src/routes/webhooks.ts`

```typescript
// ─── WHATSAPP WEBHOOK ───

// Verification (Meta requires this)
router.get('/whatsapp', (req, res) => {
  const mode = req.query['hub.mode'];
  const token = req.query['hub.verify_token'];
  const challenge = req.query['hub.challenge'];

  if (mode === 'subscribe' && token === process.env.WHATSAPP_VERIFY_TOKEN) {
    res.status(200).send(challenge);
  } else {
    res.sendStatus(403);
  }
});

// Incoming messages
router.post('/whatsapp', async (req, res) => {
  try {
    const body = req.body;

    // WhatsApp sends various webhook types — filter for messages
    const entry = body.entry?.[0];
    const changes = entry?.changes?.[0];
    const value = changes?.value;

    if (!value?.messages?.[0]) {
      res.sendStatus(200);
      return;
    }

    const message = value.messages[0];
    const phone = message.from; // Sender's phone number
    const text = message.text?.body || '';

    // ─── Check if this is a Magic Link activation ───
    if (text.startsWith('Start_')) {
      const bookingId = text.replace('Start_', '');

      const { data: conversation } = await supabaseAdmin
        .from('conversations')
        .select('*')
        .eq('booking_id', bookingId)
        .single();

      if (!conversation) {
        await sendWhatsAppMessage(phone,
          'No te reconozco. Por favor usa el enlace que recibiste.');
        res.sendStatus(200);
        return;
      }

      // Expired check
      if (conversation.check_out_date) {
        const checkOut = new Date(conversation.check_out_date);
        const yesterday = new Date();
        yesterday.setDate(yesterday.getDate() - 1);
        if (checkOut < yesterday) {
          await sendWhatsAppMessage(phone, 'Tu estancia ha terminado.');
          res.sendStatus(200);
          return;
        }
      }

      // Activate
      await supabaseAdmin
        .from('conversations')
        .update({
          telegram_chat_id: phone, // Reuse field or add whatsapp_phone column
          platform: 'whatsapp',
        })
        .eq('booking_id', bookingId);

      const { data: property } = await supabaseAdmin
        .from('properties')
        .select('name')
        .eq('id', conversation.property_id)
        .single();

      await sendWhatsAppMessage(phone,
        `Welcome to ${property!.name}, ${conversation.guest_name}! 🌴\nI'm Alfred, your AI assistant. What would you like to know?`
      );

      res.sendStatus(200);
      return;
    }

    // ─── Regular message — look up conversation by phone ───
    const { data: conversation } = await supabaseAdmin
      .from('conversations')
      .select('*')
      .eq('telegram_chat_id', phone) // Using same field — or add dedicated whatsapp_phone
      .eq('platform', 'whatsapp')
      .single();

    if (!conversation) {
      await sendWhatsAppMessage(phone,
        'No te reconozco. Por favor usa el enlace que recibiste.');
      res.sendStatus(200);
      return;
    }

    // Log + enqueue (same as Telegram V2 flow)
    const { data: newMessage } = await supabaseAdmin
      .from('messages')
      .insert({
        booking_id: conversation.booking_id,
        sender_type: 'guest',
        content: text,
        status: 'unread',
        property_id: conversation.property_id,
        is_escalated_interaction: conversation.is_escalated,
      })
      .select('id')
      .single();

    if (conversation.is_escalated) {
      await routeGuestToHost(conversation, text, newMessage!.id);
      res.sendStatus(200);
      return;
    }

    await aiResponseQueue.add('respond', {
      booking_id: conversation.booking_id,
      property_id: conversation.property_id,
      message_id: newMessage!.id,
      text,
      platform: 'whatsapp',
      telegram_chat_id: null,
      whatsapp_phone: phone,
      is_escalated: conversation.is_escalated,
      preferred_language: conversation.preferred_language,
      priority: 5,
    });

    res.sendStatus(200);
  } catch (error: any) {
    Sentry.captureException(error);
    logger.error('whatsapp.webhook_error', { error: error.message });
    res.sendStatus(200);
  }
});
```

---

# V2-PHASE 4: EMAIL SERVICE

## File: `/src/services/email.service.ts`

```typescript
import { resend, FROM_EMAIL } from '../config/resend';

export async function sendWelcomeEmail(hostEmail: string, hostName: string): Promise<void> {
  await resend.emails.send({
    from: FROM_EMAIL,
    to: hostEmail,
    subject: 'Welcome to Alfred! 🏠',
    html: `
      <h2>Welcome, ${hostName}!</h2>
      <p>You're all set to start using Alfred for your vacation rental properties.</p>
      <p><strong>Next step:</strong> Add your first property in the Dashboard.</p>
      <p><a href="${process.env.APP_URL}/dashboard">Open Dashboard →</a></p>
    `,
  });
}

export async function sendPropertyReadyEmail(
  hostEmail: string, propertyName: string
): Promise<void> {
  await resend.emails.send({
    from: FROM_EMAIL,
    to: hostEmail,
    subject: `✅ ${propertyName} is ready — Alfred is live!`,
    html: `
      <h2>${propertyName} is Ready</h2>
      <p>Alfred has learned everything about your property and is now ready to answer guest questions.</p>
      <p>Send a Magic Link to your next guest and Alfred will take care of the rest.</p>
    `,
  });
}

export async function sendEscalationEmail(
  hostEmail: string, guestName: string, propertyName: string, reason: string
): Promise<void> {
  await resend.emails.send({
    from: FROM_EMAIL,
    to: hostEmail,
    subject: `🚨 Guest needs attention at ${propertyName}`,
    html: `
      <h2>Escalation Alert</h2>
      <p><strong>Guest:</strong> ${guestName}</p>
      <p><strong>Property:</strong> ${propertyName}</p>
      <p><strong>Reason:</strong> ${reason}</p>
      <p><a href="${process.env.APP_URL}/dashboard/conversations">Open Dashboard →</a></p>
    `,
  });
}

export async function sendWeeklyReport(
  hostEmail: string, hostName: string,
  stats: {
    conversations: number;
    messages: number;
    escalations: number;
    knowledge_learned: number;
    avg_response_time_ms: number;
  }
): Promise<void> {
  await resend.emails.send({
    from: FROM_EMAIL,
    to: hostEmail,
    subject: `📊 Your Alfred Weekly Report`,
    html: `
      <h2>Weekly Report for ${hostName}</h2>
      <table>
        <tr><td>Conversations handled</td><td><strong>${stats.conversations}</strong></td></tr>
        <tr><td>Messages processed</td><td><strong>${stats.messages}</strong></td></tr>
        <tr><td>Escalations</td><td><strong>${stats.escalations}</strong></td></tr>
        <tr><td>New knowledge learned</td><td><strong>${stats.knowledge_learned}</strong></td></tr>
        <tr><td>Avg response time</td><td><strong>${Math.round(stats.avg_response_time_ms / 1000)}s</strong></td></tr>
      </table>
    `,
  });
}
```

---

# V2-PHASE 5: ANALYTICS SERVICE

## File: `/src/services/analytics.service.ts`

```typescript
import { posthog } from '../config/posthog';

export function trackEvent(
  distinctId: string,  // host_id or 'system'
  event: string,
  properties: Record<string, any> = {}
): void {
  posthog.capture({
    distinctId,
    event,
    properties: {
      ...properties,
      product_version: 'v2',
    },
  });
}

// ─── Pre-defined events ───

export const analytics = {
  hostSignedUp: (hostId: string) =>
    trackEvent(hostId, 'host.signed_up'),

  propertyAdded: (hostId: string, propertyId: string) =>
    trackEvent(hostId, 'property.added', { property_id: propertyId }),

  propertyTrained: (hostId: string, propertyId: string) =>
    trackEvent(hostId, 'property.trained', { property_id: propertyId }),

  firstGuestMessage: (hostId: string, propertyId: string, platform: string) =>
    trackEvent(hostId, 'first_guest_message', { property_id: propertyId, platform }),

  escalationTriggered: (hostId: string, propertyId: string, reason: string) =>
    trackEvent(hostId, 'escalation.triggered', { property_id: propertyId, reason }),

  escalationResolved: (hostId: string, propertyId: string, durationMs: number) =>
    trackEvent(hostId, 'escalation.resolved', { property_id: propertyId, duration_ms: durationMs }),

  knowledgeLearned: (hostId: string, propertyId: string, category: string) =>
    trackEvent(hostId, 'knowledge.learned', { property_id: propertyId, category }),

  systemChatUsed: (hostId: string, propertyId: string) =>
    trackEvent(hostId, 'system_chat.used', { property_id: propertyId }),

  ghostModeUsed: (hostId: string, bookingId: string) =>
    trackEvent(hostId, 'ghost_mode.used', { booking_id: bookingId }),
};
```

---

# V2 TEST CRITERIA

```
V2-PHASE 1 (Redis + BullMQ):
□ Telegram webhook returns 200 in < 100ms (enqueues, doesn't process)
□ AI response arrives 2-5s later via outbound worker
□ Redis cache hit rate > 80% on repeated reads (check with redis-cli INFO)
□ Failed Gemini call → job retries 3 times → dead letter queue
□ 50 simultaneous messages → all processed, no timeouts
□ Pipeline jobs run in background — API returns immediately
□ BullMQ dashboard shows queue depths and processing times

V2-PHASE 2 (WhatsApp):
□ WhatsApp webhook verification passes (GET /api/webhooks/whatsapp)
□ Guest sends Magic Link text → conversation activated
□ Guest message → AI response on WhatsApp
□ Escalation → interactive buttons on WhatsApp
□ Mark Resolved works via WhatsApp button

V2-PHASE 3 (Observability):
□ Intentional error → appears in Sentry within 1 minute
□ Gemini failure → Critical Slack alert
□ Axiom logs show: message.processed events with latency metrics
□ Axiom dashboard: avg response time, escalation rate, cache hit rate

V2-PHASE 4 (Email):
□ Host signup → welcome email received
□ Property trained → "ready" email received
□ Escalation → backup email received
□ Monday → weekly report email

V2-PHASE 5 (Analytics):
□ Events appearing in PostHog
□ Activation funnel visible: signup → property → trained → first_message
□ Feature usage dashboard populated

V2-PHASE 6 (Load Test):
□ 200 concurrent conversations simulated
□ p95 response time < 5 seconds
□ 0 rate limit violations on Telegram/WhatsApp
□ Error rate < 0.1%
□ Redis cache hit rate > 80%
□ No memory leaks after 1 hour sustained load
```

---

*END OF IDE UPGRADE SPEC v3.3*
