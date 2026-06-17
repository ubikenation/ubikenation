import cors from 'cors';
import express from 'express';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';
import pinoHttp from 'pino-http';
import { logger } from './utils/logger';
import { errorHandler, notFoundHandler } from './middleware/error';
import { fareRouter } from './modules/fare/fare.routes';
import { ridersRouter } from './modules/riders/riders.routes';
import { paymentsRouter } from './modules/payments/payments.routes';
import { tripsRouter } from './modules/trips/trips.routes';
import { chatRouter } from './modules/chat/chat.routes';
import { adminRouter } from './modules/admin/admin.routes';

export function createApp() {
  const app = express();

  app.use(helmet());
  app.use(cors());
  // Paystack webhooks need the raw body for signature verification; capture it.
  app.use(
    express.json({
      verify: (req, _res, buf) => {
        (req as express.Request & { rawBody?: Buffer }).rawBody = buf;
      },
    }),
  );
  app.use(pinoHttp({ logger }));
  app.use(rateLimit({ windowMs: 60_000, limit: 120, standardHeaders: true, legacyHeaders: false }));

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
