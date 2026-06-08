import { createClient } from '@supabase/supabase-js';
import { env } from './env.ts';

// Anon-role client — simulates a malicious / unauthenticated caller.
// Used for RLS isolation scenarios: queries should return zero rows
// for data the anon role isn't supposed to see.
export const supabaseAnon = createClient(env.supabaseUrl, env.supabaseAnonKey, {
  auth: { persistSession: false },
});
