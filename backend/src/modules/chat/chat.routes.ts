import { Router } from 'express';
import { z } from 'zod';
import { handler, ok, badRequest, forbidden } from '../../utils/http';
import { requireAuth } from '../../middleware/auth';
import { supabaseAdmin } from '../../config/supabase';
import { moderateMessage } from './moderation';

export const chatRouter = Router();

// POST /api/trips/:id/chat — send a text message (auto-moderated).
chatRouter.post('/:id/chat', requireAuth, handler(async (req, res) => {
  const { body } = z.object({ body: z.string().min(1) }).parse(req.body);
  const tripId = req.params.id;
  const userId = req.user!.id;

  // Caller must be a party to the trip (customer or assigned rider).
  const { data: trip } = await supabaseAdmin
    .from('trips')
    .select('customer_id, rider_id')
    .eq('id', tripId)
    .single();
  if (!trip) throw badRequest('trip not found');

  let isParty = trip.customer_id === userId;
  if (!isParty && trip.rider_id) {
    const { data: rider } = await supabaseAdmin
      .from('riders')
      .select('profile_id')
      .eq('id', trip.rider_id)
      .single();
    isParty = rider?.profile_id === userId;
  }
  if (!isParty) throw forbidden('not a party to this trip');

  const verdict = moderateMessage(body);
  const { data: msg } = await supabaseAdmin
    .from('chat_messages')
    .insert({
      trip_id: tripId,
      sender_id: userId,
      body: verdict.allowed ? body : verdict.sanitized,
      blocked: !verdict.allowed,
      block_reason: verdict.reason,
    })
    .select('id, blocked, block_reason, created_at')
    .single();

  ok(res, { id: msg?.id, delivered: verdict.allowed, blocked: !verdict.allowed, reason: verdict.reason }, 201);
}));

// GET /api/trips/:id/chat — message history (only delivered ones for the recipient view).
chatRouter.get('/:id/chat', requireAuth, handler(async (req, res) => {
  const { data } = await supabaseAdmin
    .from('chat_messages')
    .select('id, sender_id, body, blocked, block_reason, created_at')
    .eq('trip_id', req.params.id)
    .order('created_at', { ascending: true })
    .limit(200);
  ok(res, data ?? []);
}));
