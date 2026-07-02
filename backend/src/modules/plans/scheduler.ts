import { env } from '../../config/env';
import { logger } from '../../utils/logger';
import { runDueCompanyPayouts, runDuePayouts } from '../payments/payouts.service';
import { releaseDueScheduledTrips, runDuePlans } from './plans.service';

let timer: NodeJS.Timeout | null = null;
let running = false;

/**
 * One scheduler tick: spin up due commuter plans into errand trips and release
 * any scheduled rides whose time has arrived into matching. Both helpers are
 * idempotent enough to be safe; this is guarded against overlapping runs.
 */
async function tick() {
  if (running) return; // don't overlap if a tick runs long
  running = true;
  try {
    const plans = await runDuePlans();
    const scheduled = await releaseDueScheduledTrips();
    const payouts = await runDuePayouts(); // auto-send rider earnings 48h after completion
    const companyPayouts = await runDueCompanyPayouts(); // sweep company cut to company M-Pesa
    if (plans.created > 0 || scheduled.released > 0 || payouts.processed > 0 || companyPayouts.swept > 0) {
      logger.info({ ...plans, ...scheduled, payouts, companyPayouts }, 'scheduler fired due plans/rides/payouts');
    }
  } catch (e) {
    logger.error({ err: e }, 'scheduler tick failed');
  } finally {
    running = false;
  }
}

/**
 * Starts the in-process scheduler that auto-fires commuter plans and scheduled
 * rides every SCHEDULER_INTERVAL_MS. Returns a stop function. Set ENABLE_SCHEDULER=false
 * to disable (e.g. when running multiple instances and driving this from an external
 * cron / pg_cron hitting POST /api/plans/run-due instead).
 */
export function startScheduler(): () => void {
  if (!env.ENABLE_SCHEDULER) {
    logger.info('scheduler disabled (ENABLE_SCHEDULER=false)');
    return () => {};
  }
  logger.info({ intervalMs: env.SCHEDULER_INTERVAL_MS }, 'scheduler started');
  // Kick once shortly after boot, then on the interval.
  setTimeout(tick, 5_000);
  timer = setInterval(tick, env.SCHEDULER_INTERVAL_MS);
  return () => {
    if (timer) clearInterval(timer);
    timer = null;
  };
}
