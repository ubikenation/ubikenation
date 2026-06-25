import fs from 'node:fs';
import path from 'node:path';
import { initializeApp, cert, type App } from 'firebase-admin/app';
import { getMessaging } from 'firebase-admin/messaging';
import { env } from '../../config/env';
import { supabaseAdmin } from '../../config/supabase';
import { logger } from '../../utils/logger';

let app: App | null | undefined; // undefined = not tried yet, null = unavailable

/**
 * Lazily initialises the Firebase Admin app from the service-account JSON. Returns
 * null (and logs once) if the file isn't configured/present, so push is a safe no-op
 * in dev / before Firebase is set up — the rest of the app keeps working.
 */
function fcm() {
  if (app !== undefined) return app;
  try {
    let raw = env.FIREBASE_SERVICE_ACCOUNT_JSON;
    if (!raw) {
      const p = env.FIREBASE_SERVICE_ACCOUNT_PATH;
      if (!p) throw new Error('no FIREBASE_SERVICE_ACCOUNT_JSON or _PATH set');
      const abs = path.isAbsolute(p) ? p : path.resolve(process.cwd(), p);
      if (!fs.existsSync(abs)) throw new Error(`service account not found at ${abs}`);
      raw = fs.readFileSync(abs, 'utf8');
    }
    const sa = JSON.parse(raw);
    app = initializeApp({ credential: cert(sa) });
    logger.info('FCM initialised');
  } catch (e) {
    app = null;
    logger.warn({ err: (e as Error).message }, 'FCM disabled (push notifications are a no-op)');
  }
  return app;
}

export interface PushMessage {
  title: string;
  body: string;
  data?: Record<string, string>;
}

/**
 * Sends a push to every device token of the given profiles. Fire-and-forget: callers
 * should not await this on the critical path. Invalid/expired tokens are pruned.
 */
export async function notifyProfiles(profileIds: string[], msg: PushMessage) {
  const ids = [...new Set(profileIds)].filter(Boolean);
  if (ids.length === 0) return;
  const messaging = fcm() && getMessaging();
  if (!messaging) return;

  const { data: rows } = await supabaseAdmin
    .from('device_tokens')
    .select('token')
    .in('profile_id', ids);
  const tokens = (rows ?? []).map((r) => r.token as string);
  if (tokens.length === 0) return;

  try {
    const res = await messaging.sendEachForMulticast({
      tokens,
      notification: { title: msg.title, body: msg.body },
      data: msg.data ?? {},
      android: { priority: 'high' },
    });
    // Prune tokens Firebase reports as unregistered/invalid.
    const stale: string[] = [];
    res.responses.forEach((r, i) => {
      const code = r.error?.code;
      if (code === 'messaging/registration-token-not-registered' || code === 'messaging/invalid-argument') {
        stale.push(tokens[i]);
      }
    });
    if (stale.length) await supabaseAdmin.from('device_tokens').delete().in('token', stale);
    logger.info({ sent: res.successCount, failed: res.failureCount }, 'push sent');
  } catch (e) {
    logger.error({ err: (e as Error).message }, 'push send failed');
  }
}

/** Registers (upserts) a device token for a profile. */
export async function registerDevice(profileId: string, token: string, platform?: string) {
  await supabaseAdmin
    .from('device_tokens')
    .upsert({ profile_id: profileId, token, platform }, { onConflict: 'token' });
  return { ok: true };
}

export async function unregisterDevice(profileId: string, token: string) {
  await supabaseAdmin.from('device_tokens').delete().eq('profile_id', profileId).eq('token', token);
  return { ok: true };
}
