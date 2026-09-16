import { env } from './env.ts';

export type Verdict = {
  pass: boolean;
  notes: string;
  raw: string;
};

// Vision judge model, chosen 2026-09-16 via a 4-way empirical comparison against known
// PASS/FAIL screenshots (see README.md "Vision judge model"): gemini-3.8-flash (the prior
// model here) and the free OpenRouter candidate both failed live during the comparison
// (a 503 "high demand" and a 429 rate-limit respectively — the exact failure class this
// project's main Gemini reliability work was fighting). This model scored 2/2 correct with
// zero errors, at a fraction-of-a-cent cost per call. Re-run the comparison script before
// changing this if the judge starts misbehaving — don't swap models on a guess.
const MODEL = 'qwen/qwen3-vl-8b-instruct';

// Sends a screenshot + expected description to the judge model and returns PASS/FAIL.
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

  // Retry on transient failures (429 rate-limit, 5xx, or a network-level error) — three
  // attempts with exponential backoff, same policy the prior Gemini-direct judge used.
  let raw = '';
  let lastErr: Error | undefined;
  for (let attempt = 1; attempt <= 3; attempt++) {
    try {
      const res = await fetch('https://openrouter.ai/api/v1/chat/completions', {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${env.openrouterApiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          model: MODEL,
          messages: [
            {
              role: 'user',
              content: [
                { type: 'text', text: prompt },
                { type: 'image_url', image_url: { url: `data:image/png;base64,${base64}` } },
              ],
            },
          ],
        }),
      });
      const json: any = await res.json();
      if (!res.ok) {
        const err = new Error(`OpenRouter judge error ${res.status}: ${JSON.stringify(json).slice(0, 300)}`);
        (err as any).status = res.status;
        throw err;
      }
      raw = json.choices?.[0]?.message?.content ?? '';
      break; // success
    } catch (err) {
      lastErr = err as Error;
      const status = (err as any).status;
      const transient = status === 429 || (typeof status === 'number' && status >= 500) || status === undefined;
      if (!transient || attempt === 3) throw err;
      await new Promise(r => setTimeout(r, 1000 * 3 ** (attempt - 1))); // 1s, 3s
    }
  }
  if (!raw && lastErr) throw lastErr;

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
  // Defensive: if the model didn't follow the format, treat as fail with a flag
  return {
    pass: false,
    notes: `Judge returned unparseable verdict: "${firstLine.slice(0, 100)}"`,
    raw,
  };
}
