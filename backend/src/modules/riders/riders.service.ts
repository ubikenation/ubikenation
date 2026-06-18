import { supabaseAdmin } from '../../config/supabase';
import { AppError, badRequest, notFound } from '../../utils/http';
import { claimRegistrationFee, quoteRegistrationFee } from './founding.service';
import type { RiderKind } from '../../types/domain';

const REQUIRED_DOCS: Record<RiderKind, string[]> = {
  bike: ['national_id_url', 'driving_license_url', 'profile_photo_url', 'selfie_url', 'vehicle_photo_url', 'ownership_proof_url', 'insurance_url', 'inspection_url'],
  car: ['national_id_url', 'driving_license_url', 'selfie_url', 'logbook_url', 'insurance_url', 'inspection_url', 'vehicle_photo_url'],
  errands: ['national_id_url', 'selfie_url'],
};

/**
 * Registers (or returns) a rider record for a profile and locks in the registration fee
 * via the founding-slot allocation. Founding riders pay 0; otherwise bike=2000 / car=4000.
 */
export async function registerRider(profileId: string, kind: RiderKind) {
  const { data: existing } = await supabaseAdmin
    .from('riders')
    .select('id, status, is_founding, registration_fee, registration_paid')
    .eq('profile_id', profileId)
    .eq('kind', kind)
    .maybeSingle();

  let riderId = existing?.id;
  if (!riderId) {
    const { data, error } = await supabaseAdmin
      .from('riders')
      .insert({ profile_id: profileId, kind, status: 'submitted' })
      .select('id')
      .single();
    if (error) throw new AppError(500, `could not create rider: ${error.message}`);
    riderId = data.id;
  }

  const quote = await claimRegistrationFee(riderId!, kind);
  return {
    riderId,
    kind,
    isFounding: quote.isFounding,
    registrationFee: quote.registrationFee,
    paymentRequired: quote.registrationFee > 0,
    slotsRemaining: quote.slotsRemaining,
  };
}

/** Uploads/updates document URLs; flips to under_review once all required docs are present. */
export async function submitDocuments(profileId: string, kind: RiderKind, docs: Record<string, string>) {
  const { data: rider } = await supabaseAdmin
    .from('riders')
    .select('id, registration_fee, registration_paid')
    .eq('profile_id', profileId)
    .eq('kind', kind)
    .maybeSingle();
  if (!rider) throw notFound('register first');

  const allowed = REQUIRED_DOCS[kind];
  const update: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(docs)) {
    if (allowed.includes(k)) update[k] = v;
  }
  if (Object.keys(update).length === 0) throw badRequest('no valid document fields provided');

  await supabaseAdmin.from('riders').update(update).eq('id', rider.id);

  // Re-read to evaluate completeness.
  const { data: full } = await supabaseAdmin
    .from('riders')
    .select(allowed.join(', '))
    .eq('id', rider.id)
    .single();

  const fullRow = full as unknown as Record<string, unknown> | null;
  const complete = fullRow ? allowed.every((d) => Boolean(fullRow[d])) : false;
  const feePaid = rider.registration_fee === 0 || rider.registration_paid;

  if (complete && feePaid) {
    await supabaseAdmin.from('riders').update({ status: 'under_review' }).eq('id', rider.id);
  }
  return { complete, feePaid, status: complete && feePaid ? 'under_review' : 'submitted' };
}

export async function setOnline(profileId: string, isOnline: boolean) {
  const { data: rider } = await supabaseAdmin
    .from('riders')
    .select('id, status')
    .eq('profile_id', profileId)
    .maybeSingle();
  if (!rider) throw notFound('not a rider');
  if (rider.status !== 'activated') throw badRequest('rider not activated yet');
  await supabaseAdmin.from('riders').update({ is_online: isOnline }).eq('id', rider.id);
  return { isOnline };
}

export async function updateLocation(profileId: string, lat: number, lng: number) {
  const { data: rider } = await supabaseAdmin.from('riders').select('id').eq('profile_id', profileId).maybeSingle();
  if (!rider) throw notFound('not a rider');
  await supabaseAdmin
    .from('riders')
    .update({ last_lat: lat, last_lng: lng, last_location_at: new Date().toISOString() })
    .eq('id', rider.id);
  return { ok: true };
}

/**
 * Logs a rider violation and escalates the penalty by offence count:
 *   1st → warning, 2nd → suspended, 3rd+ → banned.
 * Used for going offline / killing GPS during an active trip.
 */
export async function reportViolation(profileId: string, kind: string, tripId?: string) {
  const { data: rider } = await supabaseAdmin
    .from('riders')
    .select('id, status')
    .eq('profile_id', profileId)
    .maybeSingle();
  if (!rider) throw notFound('not a rider');

  // Count prior violations to decide severity.
  const { count } = await supabaseAdmin
    .from('rider_violations')
    .select('id', { count: 'exact', head: true })
    .eq('rider_id', rider.id);
  const offence = (count ?? 0) + 1;
  const severity = offence >= 3 ? 'termination' : offence === 2 ? 'suspension' : 'warning';

  await supabaseAdmin.from('rider_violations').insert({
    rider_id: rider.id,
    trip_id: tripId ?? null,
    kind,
    severity,
    details: { offence },
  });

  let newStatus = rider.status;
  if (severity === 'termination') newStatus = 'banned';
  else if (severity === 'suspension') newStatus = 'suspended';

  if (newStatus !== rider.status) {
    await supabaseAdmin.from('riders').update({ status: newStatus, is_online: false }).eq('id', rider.id);
  }

  return { offence, severity, status: newStatus };
}

export async function getRiderStatus(profileId: string) {
  const { data } = await supabaseAdmin
    .from('riders')
    .select('id, kind, status, is_founding, registration_fee, registration_paid, is_online, rating_avg, rating_count')
    .eq('profile_id', profileId);
  return data ?? [];
}

export { quoteRegistrationFee };
