import { Router } from 'express';
import { z } from 'zod';
import { handler, ok, badRequest } from '../../utils/http';
import { requireAuth } from '../../middleware/auth';
import { env } from '../../config/env';
import { getTrip } from '../trips/trips.service';
import { generateZegoToken } from './zego';

export const callsRouter = Router();

// GET /api/calls/token?tripId=... — issue a ZEGO voice-call token for the caller,
// scoped to a trip room. Only a party to the trip can get one.
callsRouter.get('/token', requireAuth, handler(async (req, res) => {
  const { tripId } = z.object({ tripId: z.string().uuid() }).parse({ tripId: req.query.tripId });
  if (!env.ZEGO_APP_ID || !env.ZEGO_SERVER_SECRET) throw badRequest('voice calling is not configured');

  // Verifies the caller is the trip's customer or assigned rider.
  await getTrip(tripId, req.user!.id);

  const token = generateZegoToken(env.ZEGO_APP_ID, req.user!.id, env.ZEGO_SERVER_SECRET, 3600);
  ok(res, {
    token,
    appId: env.ZEGO_APP_ID,
    userId: req.user!.id,
    roomId: tripId, // both parties join the same room (the trip)
  });
}));
