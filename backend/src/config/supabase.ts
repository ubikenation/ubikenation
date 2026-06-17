import { createClient } from '@supabase/supabase-js';
import { env } from './env';

/**
 * Admin client — uses the service-role key and BYPASSES Row Level Security.
 * Use only on the trusted backend. Never expose this key to clients.
 */
export const supabaseAdmin = createClient(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

/**
 * Returns a client scoped to an end-user's JWT, so RLS applies as that user.
 */
export function supabaseAsUser(accessToken: string) {
  return createClient(env.SUPABASE_URL, env.SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: `Bearer ${accessToken}` } },
    auth: { autoRefreshToken: false, persistSession: false },
  });
}
