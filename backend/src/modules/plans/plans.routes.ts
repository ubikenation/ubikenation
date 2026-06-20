import { Router } from 'express';
import { z } from 'zod';
import { handler, ok } from '../../utils/http';
import { requireAuth, requireRole } from '../../middleware/auth';
import {
  createCommuterPlan, listMyPlans, releaseDueScheduledTrips, runDuePlans, setPlanStatus,
} from './plans.service';

export const plansRouter = Router();

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

// POST /api/plans/run-due — admin/cron trigger: spin up due plans + scheduled trips.
// (A Supabase scheduled function will call this; guarded to admins for now.)
plansRouter.post('/run-due', requireAuth, requireRole('admin'), handler(async (_req, res) => {
  const plans = await runDuePlans();
  const scheduled = await releaseDueScheduledTrips();
  ok(res, { ...plans, ...scheduled });
}));
