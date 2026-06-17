import { Router } from 'express';
import { z } from 'zod';
import { handler, ok } from '../../utils/http';
import { requireAuth } from '../../middleware/auth';
import {
  getRiderStatus, quoteRegistrationFee, registerRider,
  setOnline, submitDocuments, updateLocation,
} from './riders.service';

export const ridersRouter = Router();

const kindSchema = z.enum(['bike', 'car', 'errands']);

// GET /api/riders/registration-fee?kind=bike|car — fee quote (founding-slot aware).
ridersRouter.get('/registration-fee', requireAuth, handler(async (req, res) => {
  ok(res, await quoteRegistrationFee(kindSchema.parse(req.query.kind)));
}));

// POST /api/riders/register — create rider record + lock in fee (claims founding slot).
ridersRouter.post('/register', requireAuth, handler(async (req, res) => {
  const { kind } = z.object({ kind: kindSchema }).parse(req.body);
  ok(res, await registerRider(req.user!.id, kind), 201);
}));

// POST /api/riders/documents — upload/update document URLs.
ridersRouter.post('/documents', requireAuth, handler(async (req, res) => {
  const { kind, documents } = z
    .object({ kind: kindSchema, documents: z.record(z.string()) })
    .parse(req.body);
  ok(res, await submitDocuments(req.user!.id, kind, documents));
}));

// POST /api/riders/online — go online/offline (activated riders only).
ridersRouter.post('/online', requireAuth, handler(async (req, res) => {
  const { isOnline } = z.object({ isOnline: z.boolean() }).parse(req.body);
  ok(res, await setOnline(req.user!.id, isOnline));
}));

// POST /api/riders/location — push a GPS ping.
ridersRouter.post('/location', requireAuth, handler(async (req, res) => {
  const { lat, lng } = z.object({ lat: z.number(), lng: z.number() }).parse(req.body);
  ok(res, await updateLocation(req.user!.id, lat, lng));
}));

// GET /api/riders/me — this profile's rider record(s) + status.
ridersRouter.get('/me', requireAuth, handler(async (req, res) => {
  ok(res, await getRiderStatus(req.user!.id));
}));
