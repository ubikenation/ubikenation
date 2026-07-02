import { supabaseAdmin } from '../../config/supabase';
import { AppError, badRequest, notFound } from '../../utils/http';
import { claimRegistrationFee, quoteRegistrationFee } from './founding.service';
import type { RiderKind } from '../../types/domain';

const REQUIRED_DOCS: Record<RiderKind, string[]> = {
  bike: ['profile_photo_url', 'national_id_url', 'driving_license_url', 'selfie_url', 'vehicle_photo_url', 'ownership_proof_url', 'insurance_url', 'inspection_url'],
  car: ['profile_photo_url', 'national_id_url', 'driving_license_url', 'selfie_url', 'logbook_url', 'insurance_url', 'inspection_url', 'vehicle_photo_url'],
  // errands riders register exactly like bike riders (full docs + vehicle).
  errands: ['profile_photo_url', 'national_id_url', 'driving_license_url', 'selfie_url', 'vehicle_photo_url', 'ownership_proof_url', 'insurance_url', 'inspection_url'],
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

  // The registration fee is a ONE-TIME charge, locked in when the rider first
  // registers. On any later call we return the already-locked fee — we never
  // re-claim (that could re-charge a paid rider, or flip a founding rider to paid
  // once the free slots fill up). `alreadyPaid` lets the app skip payment.
  if (existing) {
    const { slotsRemaining } = await quoteRegistrationFee(kind);
    return {
      riderId: existing.id,
      kind,
      isFounding: existing.is_founding,
      registrationFee: existing.registration_fee,
      paymentRequired: existing.registration_fee > 0 && !existing.registration_paid,
      alreadyPaid: existing.registration_paid,
      slotsRemaining,
    };
  }

  const { data, error } = await supabaseAdmin
    .from('riders')
    .insert({ profile_id: profileId, kind, status: 'submitted' })
    .select('id')
    .single();
  if (error) throw new AppError(500, `could not create rider: ${error.message}`);

  const quote = await claimRegistrationFee(data.id, kind);
  return {
    riderId: data.id,
    kind,
    isFounding: quote.isFounding,
    registrationFee: quote.registrationFee,
    paymentRequired: quote.registrationFee > 0,
    alreadyPaid: false,
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

/**
 * Records a KES 0 registration "payment" for a founding (free) rider and marks
 * them as paid, so they go through the same pay-then-submit flow. Paystack cannot
 * charge zero, so this is recorded directly as a successful KES 0 transaction.
 */
export async function confirmFreeRegistration(profileId: string, kind: RiderKind) {
  const { data: rider } = await supabaseAdmin
    .from('riders')
    .select('id, registration_fee, registration_paid')
    .eq('profile_id', profileId)
    .eq('kind', kind)
    .maybeSingle();
  if (!rider) throw notFound('register first');
  if (rider.registration_fee !== 0) {
    throw badRequest('this rider has a registration fee and must pay via Paystack');
  }
  if (rider.registration_paid) return { ok: true, alreadyPaid: true };

  const { data: payment } = await supabaseAdmin
    .from('payments')
    .insert({
      profile_id: profileId,
      purpose: 'rider_registration',
      amount: 0,
      status: 'success',
      paystack_ref: `free_${rider.id}`,
    })
    .select('id')
    .single();

  await supabaseAdmin
    .from('riders')
    .update({ registration_paid: true, registration_payment_id: payment?.id ?? null })
    .eq('id', rider.id);

  return { ok: true, amount: 0 };
}

/**
 * Saves detailed rider info: personal details (jsonb on riders.details), the
 * M-Pesa number on the profile, and structured vehicle info in the vehicles table.
 */
export async function submitDetails(
  profileId: string,
  kind: RiderKind,
  details: Record<string, unknown>,
  vehicle: Record<string, unknown> | null,
) {
  const { data: rider } = await supabaseAdmin
    .from('riders')
    .select('id')
    .eq('profile_id', profileId)
    .eq('kind', kind)
    .maybeSingle();
  if (!rider) throw notFound('register first');

  // Denormalise the vehicle identity onto the rider row too, so the customer app can
  // fetch "rider + car + plate" in a single read during a trip (Bolt-style).
  const riderPatch: Record<string, unknown> = { details };
  if (vehicle) {
    if (typeof vehicle.plate === 'string') riderPatch.plate_number = vehicle.plate;
    if (typeof vehicle.make === 'string') riderPatch.vehicle_make = vehicle.make;
    if (typeof vehicle.model === 'string') riderPatch.vehicle_model = vehicle.model;
    if (typeof vehicle.color === 'string') riderPatch.vehicle_color = vehicle.color;
    if (typeof vehicle.platePhoto === 'string') riderPatch.plate_photo_url = vehicle.platePhoto;
    if (typeof vehicle.vehiclePhoto === 'string') riderPatch.vehicle_photo_url = vehicle.vehiclePhoto;
  }
  await supabaseAdmin.from('riders').update(riderPatch).eq('id', rider.id);

  // Keep the profile's M-Pesa number / name in sync if provided.
  const profilePatch: Record<string, unknown> = {};
  if (typeof details.mpesa === 'string') profilePatch.mpesa_number = details.mpesa;
  if (typeof details.phone === 'string') profilePatch.phone = details.phone;
  if (typeof details.fullName === 'string') profilePatch.full_name = details.fullName;
  if (Object.keys(profilePatch).length) {
    await supabaseAdmin.from('profiles').update(profilePatch).eq('id', profileId);
  }

  if (vehicle && Object.keys(vehicle).length) {
    await supabaseAdmin.from('vehicles').insert({
      rider_id: rider.id,
      vehicle_class: (vehicle.vehicleClass as string) ?? (kind === 'car' ? 'economy' : 'standard_bike'),
      plate_number: vehicle.plate as string | undefined,
      make: vehicle.make as string | undefined,
      model: vehicle.model as string | undefined,
      color: vehicle.color as string | undefined,
      plate_photo_url: vehicle.platePhoto as string | undefined,
    });
  }
  return { ok: true };
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
