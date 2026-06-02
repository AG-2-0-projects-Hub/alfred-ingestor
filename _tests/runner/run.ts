import { randomUUID } from 'node:crypto';
import { warmup } from './lib/warmup.ts';
import { generateReport } from './lib/report.ts';
import { runC6 } from './scenarios/c6.ts';
import { runA2 } from './scenarios/a2.ts';
import { runG2 } from './scenarios/g2.ts';

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
  if (mode === 'smoke') {
    return [runC6, runA2, runG2];
  }
  // For now, 'full' is the same as 'smoke'. We expand this once the runner
  // is proven and we start parsing scenarios.md.
  return [runC6, runA2, runG2];
}

main().catch(err => {
  console.error('Fatal error:', err);
  process.exit(2);
});
