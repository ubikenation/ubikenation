import { Router } from 'express';
import { z } from 'zod';
import { handler, ok } from '../../utils/http';
import { requireAuth } from '../../middleware/auth';
import {
  assignRider, cancelTrip, completeTrip, createTrip, getRiderLocation, getTrip,
  listAvailableTrips, listMyTrips, markArrived, rateTrip, respondToAdjustment,
  riderAdjustFare, startTrip,
} from './trips.service';

export const tripsRouter = Router();

const REASONS = [
  'heavy_rain', 'flooding', 'road_closure', 'accident_ahead', 'traffic_congestion',
  'diversion_route', 'security_alert', 'fuel_cost_surge', 'remote_pickup_area', 'public_event_congestion',
] as const;

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

// POST /api/trips — customer creates a trip (returns fare + 50/50 to pay).
tripsRouter.post('/', requireAuth, handler(async (req, res) => {
  const body = createSchema.parse(req.body);
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

// GET /api/trips/:id/rider-location — live position of the assigned rider.
tripsRouter.get('/:id/rider-location', requireAuth, handler(async (req, res) => {
  ok(res, await getRiderLocation(req.params.id, req.user!.id));
}));

// POST /api/trips/:id/accept — rider accepts a searching trip.
tripsRouter.post('/:id/accept', requireAuth, handler(async (req, res) => {
  ok(res, await assignRider(req.params.id, req.user!.id));
}));

// POST /api/trips/:id/adjust — rider proposes a new fare.
tripsRouter.post('/:id/adjust', requireAuth, handler(async (req, res) => {
  const { proposedFare, reason } = z
    .object({ proposedFare: z.number().positive(), reason: z.enum(REASONS) })
    .parse(req.body);
  ok(res, await riderAdjustFare(req.params.id, req.user!.id, proposedFare, reason));
}));

// POST /api/trips/:id/adjust-response — customer accepts/declines the adjustment.
tripsRouter.post('/:id/adjust-response', requireAuth, handler(async (req, res) => {
  const { accept } = z.object({ accept: z.boolean() }).parse(req.body);
  ok(res, await respondToAdjustment(req.params.id, req.user!.id, accept));
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

// POST /api/trips/:id/rate — customer rates the rider.
tripsRouter.post('/:id/rate', requireAuth, handler(async (req, res) => {
  const { stars, comment } = z.object({ stars: z.number().int(), comment: z.string().optional() }).parse(req.body);
  ok(res, await rateTrip(req.params.id, req.user!.id, stars, comment));
}));
