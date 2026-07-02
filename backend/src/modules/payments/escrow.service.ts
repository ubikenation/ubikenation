import { supabaseAdmin } from '../../config/supabase';
import { AppError } from '../../utils/http';
import { logger } from '../../utils/logger';
import { applyWallet } from '../wallet/wallet.service';
import { splitCommission } from './commission';

/**
 * Places funds into escrow for a trip (called after a successful upfront/balance payment).
 * While status='held' and the trip hasn't started, a cancel triggers a full refund.
 */
export async function holdEscrow(tripId: string, amount: number) {
  // Accumulate: the upfront 50% is held first, then the balance 50% is added on
  // top so escrow.amount reflects the full fare actually paid in (used for refunds).
  const { data: existing } = await supabaseAdmin
    .from('escrow')
    .select('amount, status')
    .eq('trip_id', tripId)
    .maybeSingle();
  const prior = existing && existing.status === 'held' ? existing.amount : 0;
  const { error } = await supabaseAdmin.from('escrow').upsert(
    { trip_id: tripId, amount: prior + amount, status: 'held', held_at: new Date().toISOString() },
    { onConflict: 'trip_id' },
  );
  if (error) throw new AppError(500, `escrow hold failed: ${error.message}`);
}

/**
 * Releases escrow on trip completion: applies the 20/80 split, credits the rider's
 * pending earnings, and queues an M-Pesa payout (settled 24–48h later).
 */
export async function releaseEscrow(tripId: string) {
  const { data: trip, error } = await supabaseAdmin
    .from('trips')
    .select('id, rider_id, final_fare, commission_rate')
    .eq('id', tripId)
    .single();
  if (error || !trip) throw new AppError(404, 'trip not found for escrow release');
  if (!trip.rider_id) throw new AppError(409, 'trip has no assigned rider');

  const { data: esc } = await supabaseAdmin.from('escrow').select('status').eq('trip_id', tripId).single();
  if (esc?.status === 'released') return; // idempotent

  const gross = trip.final_fare ?? 0;
  // 20% normally, 25% when the rider adjusted the fare (commission_rate set at quote time).
  const split = splitCommission(gross, trip.commission_rate != null ? Number(trip.commission_rate) : undefined);

  const { data: rider } = await supabaseAdmin
    .from('riders')
    .select('profile_id')
    .eq('id', trip.rider_id)
    .single();

  const { data: riderProfile } = await supabaseAdmin
    .from('profiles')
    .select('id, mpesa_number')
    .eq('id', rider?.profile_id)
    .single();

  if (riderProfile?.id) {
    await applyWallet({
      profileId: riderProfile.id,
      direction: 'credit',
      amount: split.riderAmount,
      reason: `Trip earnings (${Math.round((1 - split.rate) * 100)}%) for trip ${tripId}`,
      tripId,
    });
  }

  await supabaseAdmin.from('payouts').insert({
    rider_id: trip.rider_id,
    amount: split.riderAmount,
    mpesa_number: riderProfile?.mpesa_number ?? '',
    status: 'pending',
    trip_id: tripId,
  });

  // Company wallet: accumulate the platform's cut (20% or 25%) for this trip.
  const { error: clErr } = await supabaseAdmin.from('company_ledger').insert({
    trip_id: tripId,
    amount: split.companyAmount,
    rate: split.rate,
    reason: `Commission (${Math.round(split.rate * 100)}%) for trip ${tripId}`,
  });
  if (clErr) logger.error({ tripId, err: clErr.message }, 'company_ledger credit failed');

  await supabaseAdmin
    .from('escrow')
    .update({ status: 'released', released_at: new Date().toISOString() })
    .eq('trip_id', tripId);

  logger.info({ tripId, ...split }, 'escrow released');
  return split;
}

/**
 * Refunds escrow when a customer cancels before the trip starts (100% refund to wallet).
 */
export async function refundEscrow(tripId: string) {
  const { data: trip } = await supabaseAdmin
    .from('trips')
    .select('id, customer_id, status')
    .eq('id', tripId)
    .single();
  if (!trip) throw new AppError(404, 'trip not found');
  if (['in_progress', 'completed'].includes(trip.status)) {
    throw new AppError(409, 'trip already started; refund requires a dispute');
  }

  const { data: esc } = await supabaseAdmin.from('escrow').select('amount, status').eq('trip_id', tripId).single();
  if (!esc || esc.status !== 'held') return;

  await applyWallet({
    profileId: trip.customer_id,
    direction: 'credit',
    amount: esc.amount,
    reason: `Refund for cancelled trip ${tripId}`,
    tripId,
  });

  await supabaseAdmin
    .from('escrow')
    .update({ status: 'refunded', refunded_at: new Date().toISOString() })
    .eq('trip_id', tripId);
}
