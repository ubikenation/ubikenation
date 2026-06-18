import cors, { type CorsOptions } from 'cors';
import express from 'express';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';
import pinoHttp from 'pino-http';
import { env } from './config/env';
import { logger } from './utils/logger';
import { errorHandler, notFoundHandler } from './middleware/error';
import { fareRouter } from './modules/fare/fare.routes';
import { ridersRouter } from './modules/riders/riders.routes';
import { paymentsRouter } from './modules/payments/payments.routes';
import { tripsRouter } from './modules/trips/trips.routes';
import { chatRouter } from './modules/chat/chat.routes';
import { adminRouter } from './modules/admin/admin.routes';

/**
 * Web origins allowed to call the API. Mobile apps send no Origin header and
 * are always allowed; browsers must match this allowlist.
 */
function corsOptions(): CorsOptions {
  const allowed = new Set(
    (env.ALLOWED_ORIGINS || '')
      .split(',')
      .map((s) => s.trim())
      .filter(Boolean),
  );
  return {
    origin(origin, cb) {
      // No Origin = native app / curl / same-origin → allow.
      if (!origin) return cb(null, true);
      if (allowed.has(origin) || /^(http:\/\/localhost(:\d+)?|http:\/\/127\.0\.0\.1(:\d+)?)$/.test(origin)) {
        return cb(null, true);
      }
      return cb(new Error('Not allowed by CORS'));
    },
    methods: ['GET', 'POST', 'PATCH', 'PUT', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization', 'x-paystack-signature'],
    maxAge: 600,
  };
}

export function createApp() {
  const app = express();

  app.disable('x-powered-by');
  app.use(
    helmet({
      crossOriginResourcePolicy: { policy: 'cross-origin' },
      hsts: { maxAge: 31536000, includeSubDomains: true, preload: true },
    }),
  );
  app.use(cors(corsOptions()));
  // Paystack webhooks need the raw body for signature verification; capture it.
  app.use(
    express.json({
      limit: '1mb',
      verify: (req, _res, buf) => {
        (req as express.Request & { rawBody?: Buffer }).rawBody = buf;
      },
    }),
  );
  app.use(pinoHttp({ logger }));

  // Global limiter, with a stricter one for auth-sensitive write paths.
  app.use(rateLimit({ windowMs: 60_000, limit: 120, standardHeaders: true, legacyHeaders: false }));
  const strict = rateLimit({ windowMs: 60_000, limit: 20, standardHeaders: true, legacyHeaders: false });
  app.use('/api/payments', strict);
  app.use('/api/admin', strict);

  app.get('/health', (_req, res) => res.json({ status: 'ok', service: 'ubike-backend', time: new Date().toISOString() }));

  app.use('/api/fare', fareRouter);
  app.use('/api/riders', ridersRouter);
  app.use('/api/payments', paymentsRouter);
  app.use('/api/trips', tripsRouter);
  app.use('/api/trips', chatRouter);
  app.use('/api/admin', adminRouter);

  app.use(notFoundHandler);
  app.use(errorHandler);

  return app;
}
