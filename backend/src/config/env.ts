import dotenv from 'dotenv';
import { z } from 'zod';

dotenv.config();

const schema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().default(8080),

  SUPABASE_URL: z.string().url(),
  SUPABASE_ANON_KEY: z.string().min(10),
  SUPABASE_SERVICE_ROLE_KEY: z.string().min(10),

  PAYSTACK_SECRET_KEY: z.string().min(10),
  PAYSTACK_PUBLIC_KEY: z.string().min(10),
  PAYSTACK_WEBHOOK_SECRET: z.string().optional().default(''),

  GOOGLE_MAPS_API_KEY: z.string().optional().default(''),
  MAPBOX_ACCESS_TOKEN: z.string().optional().default(''),
  ORS_API_KEY: z.string().optional().default(''),

  REDIS_URL: z.string().optional().default(''),

  // ZEGOCLOUD real-time voice calls.
  ZEGO_APP_ID: z.coerce.number().optional().default(0),
  ZEGO_SERVER_SECRET: z.string().optional().default(''),

  // Firebase service account for FCM push (optional; push is a no-op until provided).
  // Provide EITHER a path to the JSON file OR the raw JSON pasted as one env var
  // (handy on Render/Vercel where mounting a file is awkward).
  FIREBASE_SERVICE_ACCOUNT_PATH: z.string().optional().default(''),
  FIREBASE_SERVICE_ACCOUNT_JSON: z.string().optional().default(''),

  // Comma-separated web origins allowed to call the API (the website + admin URLs).
  ALLOWED_ORIGINS: z
    .string()
    .optional()
    .default('https://ubikenation-fkrb.vercel.app,https://ubikenation.vercel.app'),

  COMMISSION_RATE: z.coerce.number().min(0).max(1).default(0.2),
  FOUNDING_BIKE_SLOTS: z.coerce.number().int().default(10),
  FOUNDING_CAR_SLOTS: z.coerce.number().int().default(10),
  BIKE_REGISTRATION_FEE: z.coerce.number().int().default(2000),
  CAR_REGISTRATION_FEE: z.coerce.number().int().default(4000),
  MAX_RIDER_PRICE_ADJUSTMENT: z.coerce.number().min(0).max(1).default(0.3),
  UPFRONT_PAYMENT_RATIO: z.coerce.number().min(0).max(1).default(0.5),

  // Background scheduler: fires due commuter plans + scheduled rides into matching.
  ENABLE_SCHEDULER: z
    .string()
    .optional()
    .default('true')
    .transform((v) => v !== 'false' && v !== '0'),
  SCHEDULER_INTERVAL_MS: z.coerce.number().int().min(15_000).default(120_000),
  // Shared secret so an external cron / pg_cron can call POST /api/plans/run-due
  // (sent as the x-cron-secret header) without an admin JWT. Empty = header disabled.
  CRON_SECRET: z.string().optional().default(''),

  // Automatic rider payouts: N hours after a trip completes, the scheduler sends
  // the rider's share to their M-Pesa via Paystack and debits their wallet.
  // This moves REAL money, so it is OFF by default — set AUTO_PAYOUT_ENABLED=true
  // on the backend once Paystack Transfers are verified working for your account.
  AUTO_PAYOUT_ENABLED: z
    .string()
    .optional()
    .default('false')
    .transform((v) => v === 'true' || v === '1'),
  AUTO_PAYOUT_DELAY_HOURS: z.coerce.number().min(0).default(48),
  // The company's own M-Pesa number. When auto-payouts are on, the accumulated
  // commission cut (company wallet) is swept here on the same 48h cadence.
  COMPANY_MPESA_NUMBER: z.string().optional().default('0792881220'),

  // Real route distances via Google Directions (falls back to straight-line on error).
  ENABLE_REAL_ROUTING: z
    .string()
    .optional()
    .default('true')
    .transform((v) => v !== 'false' && v !== '0'),
});

const parsed = schema.safeParse(process.env);

if (!parsed.success) {
  // eslint-disable-next-line no-console
  console.error('\n❌ Invalid environment configuration:\n');
  for (const issue of parsed.error.issues) {
    // eslint-disable-next-line no-console
    console.error(`  • ${issue.path.join('.')}: ${issue.message}`);
  }
  console.error('\nCopy .env.example to .env and fill in the values.\n');
  process.exit(1);
}

export const env = parsed.data;
export const isProd = env.NODE_ENV === 'production';
