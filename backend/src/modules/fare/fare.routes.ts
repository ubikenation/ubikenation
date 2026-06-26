import { Router } from 'express';
import { z } from 'zod';
import { handler, ok } from '../../utils/http';
import { requireAuth } from '../../middleware/auth';
import { calculateFare, estimateAllFares, estimateErrandFare, validateAdjustment } from './fare.service';

export const fareRouter = Router();

const estimateSchema = z.object({
  vehicleClass: z.enum(['standard_bike', 'electric_bike', 'economy', 'comfort', 'suv', 'errands']),
  distanceKm: z.number().nonnegative(),
  durationMin: z.number().nonnegative(),
  trafficFactor: z.number().optional(),
  weatherFactor: z.number().optional(),
  demandFactor: z.number().optional(),
  pickupDifficulty: z.number().optional(),
});

// POST /api/fare/estimate — customer sees only the final fare + 50/50 split.
fareRouter.post(
  '/estimate',
  requireAuth,
  handler(async (req, res) => {
    const input = estimateSchema.parse(req.body);
    const fare = await calculateFare(input);
    ok(res, {
      vehicleClass: fare.vehicleClass,
      fare: fare.baseFare,
      upfront: fare.upfrontAmount,
      balance: fare.balanceAmount,
    });
  }),
);

// POST /api/fare/estimate-all — price for EVERY vehicle type for a route (real
// distance via Directions). Lets the customer compare options before choosing.
fareRouter.post(
  '/estimate-all',
  requireAuth,
  handler(async (req, res) => {
    const { pickup, dropoff } = z
      .object({
        pickup: z.object({ lat: z.number(), lng: z.number() }),
        dropoff: z.object({ lat: z.number(), lng: z.number() }),
      })
      .parse(req.body);
    ok(res, await estimateAllFares(pickup, dropoff));
  }),
);

const errandSchema = z.object({
  errandType: z.string().min(1),
  description: z.string().min(1),
  distanceKm: z.number().nonnegative().default(0),
  durationMin: z.number().nonnegative().default(0),
});

// POST /api/fare/errand-estimate — auto fare from the listed errand items.
fareRouter.post(
  '/errand-estimate',
  requireAuth,
  handler(async (req, res) => {
    const input = errandSchema.parse(req.body);
    ok(res, await estimateErrandFare(input));
  }),
);

const adjustSchema = z.object({
  originalFare: z.number().positive(),
  proposedFare: z.number().positive(),
});

// POST /api/fare/validate-adjustment — rider proposes a new fare (<= +30%, no reason).
fareRouter.post(
  '/validate-adjustment',
  requireAuth,
  handler(async (req, res) => {
    const input = adjustSchema.parse(req.body);
    ok(res, validateAdjustment(input));
  }),
);
