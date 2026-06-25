'use client';

import { config } from './config';
import { supabase } from './supabase';

async function authHeaders(): Promise<Record<string, string>> {
  const { data } = await supabase.auth.getSession();
  const token = data.session?.access_token;
  return {
    'Content-Type': 'application/json',
    ...(token ? { Authorization: `Bearer ${token}` } : {}),
  };
}

async function handle(res: Response) {
  const json = await res.json().catch(() => ({}));
  if (!res.ok) {
    throw new Error(json?.error?.message ?? `Request failed (${res.status})`);
  }
  return json.data ?? json;
}

export const api = {
  async get(path: string) {
    const res = await fetch(`${config.apiBaseUrl}${path}`, { headers: await authHeaders(), cache: 'no-store' });
    return handle(res);
  },
  async post(path: string, body?: unknown) {
    const res = await fetch(`${config.apiBaseUrl}${path}`, {
      method: 'POST',
      headers: await authHeaders(),
      body: JSON.stringify(body ?? {}),
    });
    return handle(res);
  },
  async patch(path: string, body?: unknown) {
    const res = await fetch(`${config.apiBaseUrl}${path}`, {
      method: 'PATCH',
      headers: await authHeaders(),
      body: JSON.stringify(body ?? {}),
    });
    return handle(res);
  },
  async del(path: string) {
    const res = await fetch(`${config.apiBaseUrl}${path}`, { method: 'DELETE', headers: await authHeaders() });
    return handle(res);
  },
};
