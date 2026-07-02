import { Router, type NextFunction, type Request, type Response } from 'express';
import { z } from 'zod';
import { handler, ok } from '../../utils/http';
import { requireAuth, requireRole } from '../../middleware/auth';
import { env } from '../../config/env';
import {
  createCommuterPlan, listMyPlans, releaseDueScheduledTrips, runDuePlans, setPlanStatus,
} from './plans.service';
import { runDuePayouts } from '../payments/payouts.service';

export const plansRouter = Router();

/**
 * Allows the run-due trigger to be called either by an admin (JWT) OR by an external
 * cron / Supabase pg_cron presenting the shared CRON_SECRET in the x-cron-secret header.
 */
function adminOrCron(req: Request, res: Response, next: NextFunction) {
  const secret = env.CRON_SECRET;
  if (secret && req.header('x-cron-secret') === secret) return next();
  requireAuth(req, res, (err?: unknown) => (err ? next(err) : requireRole('admin')(req, res, next)));
}

const createSchema = z.object({
  errandType: z.string().min(1),
  description: z.string().default(''),
  pickup: z.object({ lat: z.number(), lng: z.number(), address: z.string().optional() }),
  dropoff: z.object({ lat: z.number(), lng: z.number(), address: z.string().optional() }).optional(),
  distanceKm: z.number().nonnegative().default(0),
  durationMin: z.number().nonnegative().default(0),
  frequency: z.enum(['daily', 'weekdays', 'weekly']),
  timeOfDay: z.string().regex(/^\d{1,2}:\d{2}$/),
  daysOfWeek: z.array(z.number().int().min(0).max(6)).optional(),
});

// POST /api/plans — create a recurring commuter plan (auto-priced).
plansRouter.post('/', requireAuth, handler(async (req, res) => {
  const body = createSchema.parse(req.body);
  ok(res, await createCommuterPlan({ customerId: req.user!.id, ...body }), 201);
}));

// GET /api/plans/mine — the customer's commuter plans.
plansRouter.get('/mine', requireAuth, handler(async (req, res) => {
  ok(res, await listMyPlans(req.user!.id));
}));

// POST /api/plans/:id/pause | /resume | /cancel
plansRouter.post('/:id/pause', requireAuth, handler(async (req, res) => {
  ok(res, await setPlanStatus(req.params.id, req.user!.id, 'paused'));
}));
plansRouter.post('/:id/resume', requireAuth, handler(async (req, res) => {
  ok(res, await setPlanStatus(req.params.id, req.user!.id, 'active'));
}));
plansRouter.post('/:id/cancel', requireAuth, handler(async (req, res) => {
  ok(res, await setPlanStatus(req.params.id, req.user!.id, 'cancelled'));
}));

// POST /api/plans/run-due — spin up due plans + scheduled trips.
// Callable by an admin JWT or by cron/pg_cron with the x-cron-secret header.
plansRouter.post('/run-due', adminOrCron, handler(async (_req, res) => {
  const plans = await runDuePlans();
  const scheduled = await releaseDueScheduledTrips();
  const payouts = await runDuePayouts();
  ok(res, { ...plans, ...scheduled, payouts });
}));
