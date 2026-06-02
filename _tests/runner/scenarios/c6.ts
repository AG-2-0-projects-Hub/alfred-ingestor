import { runFlutterTest } from '../lib/flutter-runner.ts';
import type { ScenarioResult } from '../run.ts';

// C6 — chat-sys-markers-01
// Layer 1 widget test: asserts ChatSystemMessages formatters and inferMode logic.
// See _tests/scenarios.md C6.

export async function runC6(): Promise<ScenarioResult> {
  const start = Date.now();
  const id = 'chat-sys-markers-01';
  const name = 'C6: System message markers render correctly per viewer';

  console.log(`[${id}] starting...`);

  const result = await runFlutterTest('test/utils/chat_system_messages_test.dart');

  const duration_ms = Date.now() - start;
  const status = result.pass ? 'pass' : 'fail';
  const details = result.pass
    ? 'All widget tests passed'
    : `flutter test exited non-zero.\n${result.stderr || result.stdout}`.slice(0, 4000);

  console.log(`[${id}] ${status.toUpperCase()} (${duration_ms}ms)`);

  return {
    id,
    name,
    layer: 1,
    status,
    duration_ms,
    details,
    artifacts: { stdout: result.stdout.slice(-4000) },
  };
}
