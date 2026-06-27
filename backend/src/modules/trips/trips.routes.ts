import { Router } from 'express';
import { z } from 'zod';
import { handler, ok } from '../../utils/http';
import { requireAuth } from '../../middleware/auth';
import {
  assignRider, cancelTrip, completeTrip, createTrip, declineRequest, getCustomerLocation,
  getRiderLocation, getTrip, hideTrip, listAvailableTrips, listMyTrips, markArrived, openDispute,
  quoteFare, rateTrip, requeryTrip, startTrip, updateCustomerLocation,
} from './trips.service';

export const tripsRouter = Router();

const createSchema = z.object({
  tripType: z.enum(['bike', 'car', 'errands', 'scheduled']),
  vehicleClass: z.enum(['standard_bike', 'electric_bike', 'economy', 'comfort', 'suv', 'errands']),
  pickup: z.object({ lat: z.number(), lng: z.number(), address: z.string().optional() }),
  dropoff: z.object({ lat: z.number(), lng: z.number(), address: z.string().optional() }).optional(),
  distanceKm: z.number().nonnegative(),
  durationMin: z.number().nonnegative(),
  scheduledFor: z.string().datetime().optional(),
  errandType: z.string().optional(),
  errandDetails: z.record(z.unknown()).optional(),
});

// POST /api/trips — customer requests a ride/errand; goes straight to matching
// (no payment yet). Returns the trip id + system estimate.
tripsRouter.post('/', requireAuth, handler(async (req, res) => {
  const body = createSchema.parse(req.body);
  ok(res, await createTrip({ customerId: req.user!.id, ...body }), 201);
}));

// POST /api/trips/schedule — customer schedules a ride for later (status `scheduled`).
tripsRouter.post('/schedule', requireAuth, handler(async (req, res) => {
  const body = createSchema.extend({ scheduledFor: z.string().datetime() }).parse(req.body);
  ok(res, await createTrip({ customerId: req.user!.id, ...body }), 201);
}));

// GET /api/trips/available — rider pulls nearby searching trips it can accept.
tripsRouter.get('/available', requireAuth, handler(async (req, res) => {
  ok(res, await listAvailableTrips(req.user!.id));
}));

// GET /api/trips/mine — the customer's own trip history.
tripsRouter.get('/mine', requireAuth, handler(async (req, res) => {
  ok(res, await listMyTrips(req.user!.id));
}));

// GET /api/trips/:id — trip status for a party (customer or assigned rider).
tripsRouter.get('/:id', requireAuth, handler(async (req, res) => {
  ok(res, await getTrip(req.params.id, req.user!.id));
}));

// GET /api/trips/:id/rider-location — live position + vehicle identity of the rider.
tripsRouter.get('/:id/rider-location', requireAuth, handler(async (req, res) => {
  ok(res, await getRiderLocation(req.params.id, req.user!.id));
}));

// GET /api/trips/:id/customer-location — live position of the customer (for the rider).
tripsRouter.get('/:id/customer-location', requireAuth, handler(async (req, res) => {
  ok(res, await getCustomerLocation(req.params.id, req.user!.id));
}));

// POST /api/trips/:id/customer-location — customer pushes their live GPS.
tripsRouter.post('/:id/customer-location', requireAuth, handler(async (req, res) => {
  const { lat, lng } = z.object({ lat: z.number(), lng: z.number() }).parse(req.body);
  ok(res, await updateCustomerLocation(req.params.id, req.user!.id, lat, lng));
}));

// POST /api/trips/:id/accept — rider accepts a searching trip → quote_pending.
tripsRouter.post('/:id/accept', requireAuth, handler(async (req, res) => {
  ok(res, await assignRider(req.params.id, req.user!.id));
}));

// POST /api/trips/:id/quote — rider confirms the price (accept auto, or adjust ≤ +30%).
tripsRouter.post('/:id/quote', requireAuth, handler(async (req, res) => {
  const { proposedFare } = z.object({ proposedFare: z.number().positive().optional() }).parse(req.body ?? {});
  ok(res, await quoteFare(req.params.id, req.user!.id, proposedFare));
}));

// POST /api/trips/:id/requery — customer passes on this rider; re-search a new one.
tripsRouter.post('/:id/requery', requireAuth, handler(async (req, res) => {
  ok(res, await requeryTrip(req.params.id, req.user!.id));
}));

// POST /api/trips/:id/decline — rider passes on a request (hides it from them).
tripsRouter.post('/:id/decline', requireAuth, handler(async (req, res) => {
  ok(res, await declineRequest(req.params.id, req.user!.id));
}));

// POST /api/trips/:id/dispute — customer/rider opens a dispute on an active/finished trip.
tripsRouter.post('/:id/dispute', requireAuth, handler(async (req, res) => {
  const { reason } = z.object({ reason: z.string().min(1) }).parse(req.body ?? {});
  ok(res, await openDispute(req.params.id, req.user!.id, reason));
}));

tripsRouter.post('/:id/arrived', requireAuth, handler(async (req, res) => {
  ok(res, await markArrived(req.params.id, req.user!.id));
}));

tripsRouter.post('/:id/start', requireAuth, handler(async (req, res) => {
  ok(res, await startTrip(req.params.id, req.user!.id));
}));

tripsRouter.post('/:id/complete', requireAuth, handler(async (req, res) => {
  ok(res, await completeTrip(req.params.id, req.user!.id));
}));

// POST /api/trips/:id/cancel — customer cancels (full refund before start).
tripsRouter.post('/:id/cancel', requireAuth, handler(async (req, res) => {
  const { reason } = z.object({ reason: z.string().optional() }).parse(req.body ?? {});
  ok(res, await cancelTrip(req.params.id, req.user!.id, reason));
}));

// POST /api/trips/:id/hide — customer removes a finished trip from their history.
tripsRouter.post('/:id/hide', requireAuth, handler(async (req, res) => {
  ok(res, await hideTrip(req.params.id, req.user!.id));
}));

// POST /api/trips/:id/rate — customer rates the rider.
tripsRouter.post('/:id/rate', requireAuth, handler(async (req, res) => {
  const { stars, comment } = z
    .object({ stars: z.number().int(), comment: z.string().nullish() })
    .parse(req.body);
  ok(res, await rateTrip(req.params.id, req.user!.id, stars, comment ?? undefined));
}));
