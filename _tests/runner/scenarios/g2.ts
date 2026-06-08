import { supabaseAnon } from '../lib/supabase.ts';
import type { ScenarioResult } from '../run.ts';

// G2 — rls-message-isolation-01
// Layer 1 DB test (Supabase via anon key).
//
// Asserts that an anonymous caller using the public anon key CANNOT read
// messages from arbitrary conversations. With RLS disabled on `messages`
// (current state), this scenario is EXPECTED TO FAIL — that's the point.
// The failing test is the guardrail forcing RLS policies before beta.

export async function runG2(): Promise<ScenarioResult> {
  const start = Date.now();
  const id = 'rls-message-isolation-01';
  const name = 'G2: Anon key cannot read other guests\' messages';
  console.log(`[${id}] starting...`);

  // Query: as anon, attempt to read messages from any conversation.
  // If RLS is properly enforced, this returns 0 rows (anon has no auth context
  // tying them to a specific booking). If RLS is disabled, it returns all rows.
  const { data, error } = await supabaseAnon
    .from('messages')
    .select('id, conversation_id, sender_type')
    .limit(50);

  const duration_ms = Date.now() - start;
  let status: 'pass' | 'fail';
  let details: string;

  if (error) {
    // RLS denying outright would surface as a Postgres-level error — that's a pass.
    status = 'pass';
    details = `RLS appears to be enforcing isolation (query errored: ${error.message}). This is the desired state.`;
  } else if (!data || data.length === 0) {
    // RLS returning empty array — also a pass.
    status = 'pass';
    details = 'Query returned zero rows for anon role — RLS is enforcing isolation correctly.';
  } else {
    // Got rows back — RLS is NOT enforced. This is the expected fail state today.
    status = 'fail';
    details =
      `Anon role read ${data.length} messages without authentication. ` +
      `This is a critical RLS gap — see project_rls_pending memory. ` +
      `Sample sender_types returned: ${[...new Set(data.map(r => r.sender_type))].join(', ')}`;
  }

  console.log(`[${id}] ${status.toUpperCase()} (${duration_ms}ms)`);

  return {
    id,
    name,
    layer: 1,
    status,
    duration_ms,
    details,
    artifacts: { rowCount: data?.length ?? 0 },
  };
}
