import { randomUUID } from 'node:crypto';
import { warmup } from './lib/warmup.ts';
import { generateReport } from './lib/report.ts';
// Layer 1
import { runC6 } from './scenarios/c6.ts';
import { runG2 } from './scenarios/g2.ts';
// Layer 2
import { runA2 } from './scenarios/a2.ts';
import { runA3 } from './scenarios/a3.ts';
import { runA4 } from './scenarios/a4.ts';
import { runB6 } from './scenarios/b6.ts';
import { runB7 } from './scenarios/b7.ts';
import { runB15 } from './scenarios/b15.ts';
import { runB16 } from './scenarios/b16.ts';
import { runD6 } from './scenarios/d6.ts';
import { runD7 } from './scenarios/d7.ts';
import { runD8 } from './scenarios/d8.ts';
import { runD9 } from './scenarios/d9.ts';
import { runP1 } from './scenarios/p1.ts';
import { runQ1 } from './scenarios/q1.ts';

export type ScenarioResult = {
  id: string;
  name: string;
  layer: number;
  status: 'pass' | 'fail';
  duration_ms: number;
  details: string;
  artifacts?: Record<string, unknown>;
};

const mode = (process.argv[2] ?? 'smoke').toLowerCase();

async function main() {
  const runId = randomUUID();
  const start = Date.now();

  console.log('═══════════════════════════════════════════════════════');
  console.log(`Alfred QA — mode: ${mode}`);
  console.log(`Run ID: ${runId}`);
  console.log('═══════════════════════════════════════════════════════\n');

  await warmup();

  const scenarios = pickScenarios(mode);
  console.log(`Running ${scenarios.length} scenario(s)...\n`);

  const results: ScenarioResult[] = [];
  for (const scenario of scenarios) {
    try {
      const result = await scenario();
      results.push(result);
    } catch (err) {
      console.error(`Scenario threw: ${(err as Error).message}`);
      results.push({
        id: 'unknown',
        name: 'Scenario crashed',
        layer: 0,
        status: 'fail',
        duration_ms: 0,
        details: (err as Error).stack ?? (err as Error).message,
      });
    }
  }

  const total = Date.now() - start;
  const reportPath = await generateReport(runId, results, total);

  console.log('\n═══════════════════════════════════════════════════════');
  console.log(`Done in ${total}ms`);
  console.log(`Passed: ${results.filter(r => r.status === 'pass').length}/${results.length}`);
  console.log(`Failed: ${results.filter(r => r.status === 'fail').length}/${results.length}`);
  console.log(`Report: ${reportPath}`);
  console.log('═══════════════════════════════════════════════════════');

  const failed = results.some(r => r.status === 'fail');
  process.exit(failed ? 1 : 0);
}

function pickScenarios(mode: string): Array<() => Promise<ScenarioResult>> {
  // smoke: fast Layer 1 checks + the core login scenario. No Playwright UI flows
  // that need Render warmup beyond what warmup() already covers.
  if (mode === 'smoke') {
    return [runC6, runG2, runA2];
  }
  // full: all implemented scenarios — Layer 1 first, then Layer 2 auth suite,
  // then Layer 2 ingest error scenarios.
  return [
    // Layer 1
    runC6,
    runG2,
    // Layer 2 — auth
    runA2,
    runA3,
    runA4,
    // Layer 2 — ingest error paths
    runB6,
    runB7,
    runB15,
    runB16,
    // Layer 2 — dashboard
    runD6,
    runD7,
    runD8,
    runD9,
    // Layer 2 — Telegram host escalation
    runP1,
    // Layer 2 — first-login onboarding
    runQ1,
  ];
}

main().catch(err => {
  console.error('Fatal error:', err);
  process.exit(2);
});
