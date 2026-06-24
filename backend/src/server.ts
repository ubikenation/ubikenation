import { createApp } from './app';
import { env } from './config/env';
import { logger } from './utils/logger';
import { startScheduler } from './modules/plans/scheduler';

const app = createApp();

const server = app.listen(env.PORT, () => {
  logger.info(`U-Bike backend listening on http://localhost:${env.PORT} (${env.NODE_ENV})`);
});

// Auto-fire due commuter plans + scheduled rides (in-process; disable with ENABLE_SCHEDULER=false).
const stopScheduler = startScheduler();

for (const signal of ['SIGINT', 'SIGTERM'] as const) {
  process.on(signal, () => {
    logger.info(`${signal} received, shutting down`);
    stopScheduler();
    server.close(() => process.exit(0));
  });
}
