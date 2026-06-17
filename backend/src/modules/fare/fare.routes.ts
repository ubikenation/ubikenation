import { Router } from 'express';
import { z } from 'zod';
import { handler, ok } from '../../utils/http';
import { requireAuth } from '../../middleware/auth';
import { calculateFare, validateAdjustment } from './fare.service';

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

const adjustSchema = z.object({
  originalFare: z.number().positive(),
  proposedFare: z.number().positive(),
  reason: z.enum([
    'heavy_rain', 'flooding', 'road_closure', 'accident_ahead', 'traffic_congestion',
    'diversion_route', 'security_alert', 'fuel_cost_surge', 'remote_pickup_area', 'public_event_congestion',
  ]),
});

// POST /api/fare/validate-adjustment — rider proposes a new fare (<= +30%).
fareRouter.post(
  '/validate-adjustment',
  requireAuth,
  handler(async (req, res) => {
    const input = adjustSchema.parse(req.body);
    ok(res, validateAdjustment(input));
  }),
);
