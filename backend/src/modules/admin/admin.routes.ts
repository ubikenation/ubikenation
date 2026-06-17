import { Router } from 'express';
import { z } from 'zod';
import { handler, ok } from '../../utils/http';
import { requireAuth, requireRole } from '../../middleware/auth';
import {
  approveRider, getDashboardStats, getFoundingProgram, getRiderDocuments, listPayouts,
  listRiders, listTrips, rejectRider, setFoundingProgram,
} from './admin.service';

export const adminRouter = Router();

// All admin routes require an authenticated user with the 'admin' role.
adminRouter.use(requireAuth, requireRole('admin'));

adminRouter.get('/stats', handler(async (_req, res) => ok(res, await getDashboardStats())));

adminRouter.get('/riders', handler(async (req, res) => {
  const status = typeof req.query.status === 'string' ? req.query.status : undefined;
  ok(res, await listRiders(status));
}));

adminRouter.get('/riders/:id/documents', handler(async (req, res) => {
  ok(res, await getRiderDocuments(req.params.id));
}));

adminRouter.post('/riders/:id/approve', handler(async (req, res) => {
  ok(res, await approveRider(req.params.id));
}));

adminRouter.post('/riders/:id/reject', handler(async (req, res) => {
  const { ban } = z.object({ ban: z.boolean().optional() }).parse(req.body ?? {});
  ok(res, await rejectRider(req.params.id, ban ?? false));
}));

adminRouter.get('/founding', handler(async (_req, res) => ok(res, await getFoundingProgram())));

adminRouter.patch('/founding', handler(async (req, res) => {
  const patch = z
    .object({ enabled: z.boolean().optional(), bikeSlots: z.number().int().optional(), carSlots: z.number().int().optional() })
    .parse(req.body);
  ok(res, await setFoundingProgram(patch));
}));

adminRouter.get('/trips', handler(async (_req, res) => ok(res, await listTrips())));

adminRouter.get('/payouts', handler(async (req, res) => {
  const status = typeof req.query.status === 'string' ? req.query.status : undefined;
  ok(res, await listPayouts(status));
}));
