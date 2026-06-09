import { createClient } from '@supabase/supabase-js';
import { env } from './env.ts';

// Anon-role client — simulates a malicious / unauthenticated caller.
// Used for RLS isolation scenarios: queries should return zero rows
// for data the anon role isn't supposed to see.
export const supabaseAnon = createClient(env.supabaseUrl, env.supabaseAnonKey, {
  auth: { persistSession: false },
});

// Returns a one-off client that sends requests as the given authenticated user.
// Pass the access_token from a signInWithPassword response.
// Used in scenarios that need to read/write rows scoped to a specific user
// (e.g. B6 orphan-row check) without touching the shared supabaseAnon client.
export function createAuthedClient(accessToken: string) {
  return createClient(env.supabaseUrl, env.supabaseAnonKey, {
    auth: { persistSession: false },
    global: { headers: { Authorization: `Bearer ${accessToken}` } },
  });
}
