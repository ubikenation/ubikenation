import { env } from '../../config/env';
import { supabaseAdmin } from '../../config/supabase';
import type { RiderKind } from '../../types/domain';

export interface FeeQuote {
  kind: RiderKind;
  isFounding: boolean;
  registrationFee: number; // KES
  slotsTotal: number;
  slotsUsed: number;
  slotsRemaining: number;
  programEnabled: boolean;
}

/**
 * Founding Riders Program (final rule):
 *   Bike (standard + electric combined): first 10 approved -> KES 0, then KES 2,000.
 *   Car  (economy + comfort + suv combined): first 10 approved -> KES 0, then KES 4,000 per vehicle.
 *
 * "Used" counts riders who already hold a founding slot (approved/activated founders or
 * riders explicitly granted a free slot). Counting founders — not all approvals — keeps the
 * allocation stable even if non-founding riders are approved in between.
 */
export async function quoteRegistrationFee(kind: RiderKind): Promise<FeeQuote> {
  if (kind === 'errands') {
    // Errands riders are not part of the paid founding program in this spec.
    return {
      kind,
      isFounding: false,
      registrationFee: 0,
      slotsTotal: 0,
      slotsUsed: 0,
      slotsRemaining: 0,
      programEnabled: true,
    };
  }

  const { data: program } = await supabaseAdmin
    .from('founding_program')
    .select('bike_slots, car_slots, enabled')
    .eq('id', 1)
    .single();

  const programEnabled = program?.enabled ?? true;
  const slotsTotal = kind === 'bike' ? program?.bike_slots ?? env.FOUNDING_BIKE_SLOTS : program?.car_slots ?? env.FOUNDING_CAR_SLOTS;

  // Count riders of this kind who already occupy a founding slot.
  const { count } = await supabaseAdmin
    .from('riders')
    .select('id', { count: 'exact', head: true })
    .eq('kind', kind)
    .eq('is_founding', true);

  const slotsUsed = count ?? 0;
  const slotsRemaining = Math.max(0, slotsTotal - slotsUsed);

  const normalFee = kind === 'bike' ? env.BIKE_REGISTRATION_FEE : env.CAR_REGISTRATION_FEE;
  const isFounding = programEnabled && slotsRemaining > 0;

  return {
    kind,
    isFounding,
    registrationFee: isFounding ? 0 : normalFee,
    slotsTotal,
    slotsUsed,
    slotsRemaining,
    programEnabled,
  };
}

/**
 * Atomically claims a founding slot if one is available, returning the fee that applies.
 * Uses a DB function for race-safety when many riders register simultaneously.
 * Falls back to the quote if the RPC is not installed.
 */
export async function claimRegistrationFee(riderId: string, kind: RiderKind): Promise<FeeQuote> {
  // Race-safe allocation via the claim_founding_slot Postgres function.
  const { error } = await supabaseAdmin.rpc('claim_founding_slot', {
    p_rider: riderId,
    p_kind: kind,
    p_bike_fee: env.BIKE_REGISTRATION_FEE,
    p_car_fee: env.CAR_REGISTRATION_FEE,
  });
  if (error) {
    // Fallback to a non-atomic update if the function isn't installed yet.
    const quote = await quoteRegistrationFee(kind);
    await supabaseAdmin
      .from('riders')
      .update({ is_founding: quote.isFounding, registration_fee: quote.registrationFee })
      .eq('id', riderId);
    return quote;
  }
  return quoteRegistrationFee(kind);
}
