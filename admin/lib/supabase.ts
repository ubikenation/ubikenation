'use client';

import { createClient } from '@supabase/supabase-js';
import { config } from './config';

/** Browser Supabase client for admin auth (session persisted in localStorage). */
export const supabase = createClient(config.supabaseUrl, config.supabaseAnonKey, {
  auth: { persistSession: true, autoRefreshToken: true },
});
