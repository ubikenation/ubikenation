import { Router } from 'express';
import { z } from 'zod';
import { handler, ok, badRequest } from '../../utils/http';
import { requireAuth } from '../../middleware/auth';
import { env } from '../../config/env';
import { supabaseAdmin } from '../../config/supabase';
import { getTrip } from '../trips/trips.service';
import { notifyProfiles } from '../notifications/notification.service';
import { generateZegoToken } from './zego';

export const callsRouter = Router();

// GET /api/calls/token?tripId=... — issue a ZEGO voice-call token for the caller,
// scoped to a trip room. Only a party to the trip can get one.
callsRouter.get('/token', requireAuth, handler(async (req, res) => {
  const { tripId } = z.object({ tripId: z.string().uuid() }).parse({ tripId: req.query.tripId });
  if (!env.ZEGO_APP_ID || !env.ZEGO_SERVER_SECRET) throw badRequest('voice calling is not configured');

  // Verifies the caller is the trip's customer or assigned rider.
  await getTrip(tripId, req.user!.id);

  // Grant explicit room login (1) + stream publish (2) privileges for THIS room.
  // Required when the ZEGO project has privilege/room authentication enabled; safely
  // ignored if it isn't. Fixes ZEGO login error 1001005 (auth on empty-payload token).
  const payload = JSON.stringify({
    room_id: tripId,
    privilege: { '1': 1, '2': 1 },
    stream_id_list: null,
  });
  const token = generateZegoToken(env.ZEGO_APP_ID, req.user!.id, env.ZEGO_SERVER_SECRET, 3600, payload);
  ok(res, {
    token,
    appId: env.ZEGO_APP_ID,
    // Sent only when the ZEGO project uses AppSign auth; the app then authenticates
    // with it instead of the token (fixes login error 1001005). Empty ⇒ token auth.
    appSign: env.ZEGO_APP_SIGN,
    userId: req.user!.id,
    roomId: tripId, // both parties join the same room (the trip)
  });
}));

// POST /api/calls/ring — the caller (already joining the room) rings the other
// party so they get an "Incoming call" push and can join the same room. Without
// this the peer never knows to join and the call can't connect.
callsRouter.post('/ring', requireAuth, handler(async (req, res) => {
  const { tripId } = z.object({ tripId: z.string().uuid() }).parse(req.body ?? {});
  const caller = req.user!.id;
  const trip = await getTrip(tripId, caller); // verifies caller is a party

  // Resolve the peer's profile id + the caller's display name.
  let peerProfileId: string | null = null;
  if (trip.customer_id === caller) {
    // Caller is the customer → ring the rider.
    if (trip.rider_id) {
      const { data: rider } = await supabaseAdmin
        .from('riders')
        .select('profile_id')
        .eq('id', trip.rider_id)
        .maybeSingle();
      peerProfileId = rider?.profile_id ?? null;
    }
  } else {
    // Caller is the rider → ring the customer.
    peerProfileId = trip.customer_id;
  }
  if (!peerProfileId) return ok(res, { rung: false, reason: 'no peer yet' });

  const { data: me } = await supabaseAdmin
    .from('profiles')
    .select('full_name')
    .eq('id', caller)
    .maybeSingle();
  const callerName = me?.full_name ?? 'Someone';

  await notifyProfiles([peerProfileId], {
    title: 'Incoming call',
    body: `${callerName} is calling you`,
    data: { type: 'incoming_call', tripId, callerName },
  });
  ok(res, { rung: true });
}));
