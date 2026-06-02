import { GoogleGenAI } from '@google/genai';
import { env } from './env.ts';

const ai = new GoogleGenAI({ apiKey: env.geminiApiKey });

export type Verdict = {
  pass: boolean;
  notes: string;
  raw: string;
};

// Sends a screenshot + expected description to Gemini and returns PASS/FAIL.
// Uses gemini-2.5-flash for speed and cost; upgrade to pro if accuracy drops.
export async function judgeScreenshot(
  screenshotPng: Buffer,
  expectedDescription: string,
): Promise<Verdict> {
  const base64 = screenshotPng.toString('base64');

  const prompt =
    `You are a strict UI test judge. Look at the screenshot and decide if it matches the expected description.\n\n` +
    `Expected: ${expectedDescription}\n\n` +
    `Respond on the FIRST LINE with exactly one of:\n` +
    `PASS — <one short sentence describing what matches>\n` +
    `FAIL — <one short sentence describing what is wrong or missing>\n\n` +
    `Do not include any other text on the first line. Only use PASS or FAIL, never both.`;

  // Retry on transient 5xx (overload, rate limit) — Gemini's free tier sees
  // these intermittently. Three attempts with exponential backoff.
  let response: Awaited<ReturnType<typeof ai.models.generateContent>> | undefined;
  let lastErr: Error | undefined;
  for (let attempt = 1; attempt <= 3; attempt++) {
    try {
      response = await ai.models.generateContent({
        model: 'gemini-2.5-flash',
        contents: [
          {
            role: 'user',
            parts: [
              { text: prompt },
              { inlineData: { mimeType: 'image/png', data: base64 } },
            ],
          },
        ],
      });
      break; // success
    } catch (err) {
      lastErr = err as Error;
      const msg = (err as Error).message;
      const transient = /5\d\d|UNAVAILABLE|RESOURCE_EXHAUSTED|overload|rate.?limit/i.test(msg);
      if (!transient || attempt === 3) throw err;
      await new Promise(r => setTimeout(r, 1000 * 3 ** (attempt - 1))); // 1s, 3s
    }
  }
  if (!response) throw lastErr ?? new Error('judge failed without response');

  const raw = response.text ?? '';
  const firstLine = raw.split('\n')[0].trim();

  // Strict parsing: starts with PASS or FAIL, optionally followed by separator + notes
  const passMatch = /^PASS\b\s*[—\-:]?\s*(.*)$/i.exec(firstLine);
  const failMatch = /^FAIL\b\s*[—\-:]?\s*(.*)$/i.exec(firstLine);

  if (passMatch) {
    return { pass: true, notes: passMatch[1].trim() || 'matches expected', raw };
  }
  if (failMatch) {
    return { pass: false, notes: failMatch[1].trim() || 'does not match expected', raw };
  }
  // Defensive: if Gemini didn't follow the format, treat as fail with a flag
  return {
    pass: false,
    notes: `Judge returned unparseable verdict: "${firstLine.slice(0, 100)}"`,
    raw,
  };
}
