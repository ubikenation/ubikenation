import { createClient } from '@supabase/supabase-js';

const url = import.meta.env.VITE_SUPABASE_URL ?? 'https://eqlreobcizgtxviqegdh.supabase.co';
const anonKey =
  import.meta.env.VITE_SUPABASE_ANON_KEY ??
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVxbHJlb2JjaXpndHh2aXFlZ2RoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODE2OTEyMTAsImV4cCI6MjA5NzI2NzIxMH0.usen6Y2UCgYaNjrxo3jiUWH14h-fEI7p7XnXm0wuLWc';

// detectSessionInUrl picks up the recovery token from the password-reset email link.
export const supabase = createClient(url, anonKey, {
  auth: { detectSessionInUrl: true, persistSession: true, autoRefreshToken: true },
});
