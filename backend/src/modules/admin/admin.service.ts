import { supabaseAdmin } from '../../config/supabase';
import { env } from '../../config/env';
import { AppError, conflict, notFound } from '../../utils/http';
import { applyWallet } from '../wallet/wallet.service';

/** Aggregate counters for the dashboard header + analytics. */
export async function getDashboardStats() {
  const [users, riders, tripsToday, revenue, pendingVerifs] = await Promise.all([
    countRows('profiles'),
    countRows('riders', (q) => q.eq('status', 'activated').eq('is_online', true)),
    countRows('trips', (q) => q.gte('created_at', startOfTodayISO())),
    sumCompletedRevenue(),
    countRows('riders', (q) => q.eq('status', 'under_review')),
  ]);

  return {
    totalUsers: users,
    activeRiders: riders,
    tripsToday,
    revenueToday: revenue,
    pendingVerifications: pendingVerifs,
  };
}

export async function listRiders(status?: string) {
  let q = supabaseAdmin
    .from('riders')
    .select('id, kind, status, is_founding, registration_fee, registration_paid, rating_avg, created_at, profile_id, profiles(full_name, phone, email)')
    .order('created_at', { ascending: false })
    .limit(200);
  if (status) q = q.eq('status', status);
  const { data, error } = await q;
  if (error) throw new AppError(500, error.message);
  return data ?? [];
}

/** Approve & activate a rider (Submitted/Under Review → Activated). */
export async function approveRider(riderId: string) {
  const { data: rider } = await supabaseAdmin.from('riders').select('id, registration_fee, registration_paid').eq('id', riderId).single();
  if (!rider) throw notFound('rider not found');
  if (rider.registration_fee > 0 && !rider.registration_paid) {
    throw new AppError(409, 'registration fee not paid');
  }
  const now = new Date().toISOString();
  const { error } = await supabaseAdmin
    .from('riders')
    .update({ status: 'activated', approved_at: now })
    .eq('id', riderId);
  if (error) throw new AppError(500, error.message);
  return { riderId, status: 'activated' };
}

export async function rejectRider(riderId: string, ban = false) {
  const { error } = await supabaseAdmin
    .from('riders')
    .update({ status: ban ? 'banned' : 'suspended' })
    .eq('id', riderId);
  if (error) throw new AppError(500, error.message);
  return { riderId, status: ban ? 'banned' : 'suspended' };
}

export async function getFoundingProgram() {
  const { data } = await supabaseAdmin.from('founding_program').select('*').eq('id', 1).single();
  const [bikeUsed, carUsed] = await Promise.all([
    countRows('riders', (q) => q.eq('kind', 'bike').eq('is_founding', true)),
    countRows('riders', (q) => q.eq('kind', 'car').eq('is_founding', true)),
  ]);
  const founders = await supabaseAdmin
    .from('riders')
    .select('id, kind, status, created_at, approved_at, profiles(full_name)')
    .eq('is_founding', true)
    .order('created_at', { ascending: true });
  return {
    enabled: data?.enabled ?? true,
    bikeSlots: data?.bike_slots ?? env.FOUNDING_BIKE_SLOTS,
    carSlots: data?.car_slots ?? env.FOUNDING_CAR_SLOTS,
    bikeUsed,
    carUsed,
    bikeRemaining: Math.max(0, (data?.bike_slots ?? env.FOUNDING_BIKE_SLOTS) - bikeUsed),
    carRemaining: Math.max(0, (data?.car_slots ?? env.FOUNDING_CAR_SLOTS) - carUsed),
    founders: founders.data ?? [],
  };
}

export async function setFoundingProgram(patch: { enabled?: boolean; bikeSlots?: number; carSlots?: number }) {
  const update: Record<string, unknown> = { updated_at: new Date().toISOString() };
  if (patch.enabled !== undefined) update.enabled = patch.enabled;
  if (patch.bikeSlots !== undefined) update.bike_slots = patch.bikeSlots;
  if (patch.carSlots !== undefined) update.car_slots = patch.carSlots;
  const { error } = await supabaseAdmin.from('founding_program').update(update).eq('id', 1);
  if (error) throw new AppError(500, error.message);
  return getFoundingProgram();
}

const DOC_LABELS: Record<string, string> = {
  national_id_url: 'National ID',
  driving_license_url: 'Driving License',
  profile_photo_url: 'Profile Photo',
  selfie_url: 'Selfie',
  vehicle_photo_url: 'Vehicle Photo',
  plate_photo_url: 'Number-Plate Photo',
  ownership_proof_url: 'Ownership Proof',
  logbook_url: 'Vehicle Logbook',
  insurance_url: 'Insurance',
  inspection_url: 'Inspection Certificate',
};

/**
 * Returns short-lived signed URLs for a rider's uploaded documents so an admin
 * can review them before approving/rejecting. The bucket is private; only the
 * service-role backend can mint these URLs.
 */
export async function getRiderDocuments(riderId: string) {
  const cols = Object.keys(DOC_LABELS);
  const { data: rider, error } = await supabaseAdmin
    .from('riders')
    .select(cols.join(', '))
    .eq('id', riderId)
    .single();
  if (error || !rider) throw notFound('rider not found');

  const row = rider as unknown as Record<string, string | null>;
  const out: Array<{ key: string; label: string; url: string | null }> = [];
  for (const key of cols) {
    const path = row[key];
    if (!path) continue;
    const { data: signed } = await supabaseAdmin.storage
      .from('rider-documents')
      .createSignedUrl(path, 60 * 60); // 1 hour
    out.push({ key, label: DOC_LABELS[key], url: signed?.signedUrl ?? null });
  }
  return out;
}

export async function listTrips(limit = 50) {
  const { data } = await supabaseAdmin
    .from('trips')
    .select('id, trip_type, vehicle_class, status, final_fare, base_fare, created_at, profiles!trips_customer_id_fkey(full_name)')
    .order('created_at', { ascending: false })
    .limit(limit);
  return data ?? [];
}

/** All customers with contact details + their trip counts, for the admin. */
export async function listCustomers(limit = 300) {
  const { data } = await supabaseAdmin
    .from('profiles')
    .select('id, full_name, email, phone, mpesa_number, created_at')
    .eq('role', 'customer')
    .order('created_at', { ascending: false })
    .limit(limit);
  return data ?? [];
}

/** Deletes a rider record (verification / founding). Frees the founding slot too.
 *  Removes its payouts first (FK restrict), the rest cascade. */
export async function deleteRider(riderId: string) {
  await supabaseAdmin.from('payouts').delete().eq('rider_id', riderId);
  const { error } = await supabaseAdmin.from('riders').delete().eq('id', riderId);
  if (error) throw new AppError(409, `could not delete rider: ${error.message}`);
  return { deleted: true };
}

/** Deletes a trip (escrow/chat/ratings cascade; payments/payouts detach). */
export async function deleteTrip(tripId: string) {
  await supabaseAdmin.from('payouts').delete().eq('trip_id', tripId);
  const { error } = await supabaseAdmin.from('trips').delete().eq('id', tripId);
  if (error) throw new AppError(409, `could not delete trip: ${error.message}`);
  return { deleted: true };
}

/** Deletes a commuter plan. */
export async function deletePlan(planId: string) {
  const { error } = await supabaseAdmin.from('commuter_plans').delete().eq('id', planId);
  if (error) throw new AppError(409, `could not delete plan: ${error.message}`);
  return { deleted: true };
}

export async function listPayouts(status?: string) {
  let q = supabaseAdmin
    .from('payouts')
    .select('id, rider_id, amount, mpesa_number, status, created_at, processed_at')
    .order('created_at', { ascending: false })
    .limit(100);
  if (status) q = q.eq('status', status);
  const { data } = await q;
  return data ?? [];
}

/** All commuter (recurring errand) plans across customers, for the admin. */
export async function listAllPlans(limit = 200) {
  const { data } = await supabaseAdmin
    .from('commuter_plans')
    .select('id, errand_type, description, frequency, time_of_day, fare_estimate, status, next_run_at, created_at, profiles!commuter_plans_customer_id_fkey(full_name)')
    .order('created_at', { ascending: false })
    .limit(limit);
  return data ?? [];
}

/** Trips currently in dispute, for admin resolution. */
export async function listDisputes(limit = 100) {
  const { data } = await supabaseAdmin
    .from('trips')
    .select('id, status, final_fare, upfront_amount, balance_amount, cancel_reason, created_at, customer_id, profiles!trips_customer_id_fkey(full_name)')
    .eq('status', 'disputed')
    .order('created_at', { ascending: false })
    .limit(limit);
  return data ?? [];
}

/**
 * Resolves a dispute WITH a refund: returns what the customer actually paid to
 * their wallet (held escrow if still held, otherwise the sum of their successful
 * trip payments), then marks the trip cancelled.
 */
export async function refundDispute(tripId: string) {
  const { data: trip } = await supabaseAdmin
    .from('trips')
    .select('id, customer_id, status')
    .eq('id', tripId)
    .single();
  if (!trip) throw notFound('trip not found');
  if (trip.status !== 'disputed') throw conflict('trip is not in dispute');

  const { data: esc } = await supabaseAdmin.from('escrow').select('amount, status').eq('trip_id', tripId).maybeSingle();
  let refund = 0;
  if (esc && esc.status === 'held') {
    refund = esc.amount;
    await supabaseAdmin.from('escrow').update({ status: 'refunded', refunded_at: new Date().toISOString() }).eq('trip_id', tripId);
  } else {
    const { data: pays } = await supabaseAdmin
      .from('payments')
      .select('amount')
      .eq('trip_id', tripId)
      .eq('status', 'success')
      .in('purpose', ['trip_upfront', 'trip_balance']);
    refund = (pays ?? []).reduce((s, p) => s + (p.amount ?? 0), 0);
  }

  if (refund > 0) {
    await applyWallet({
      profileId: trip.customer_id,
      direction: 'credit',
      amount: refund,
      reason: `Dispute refund for trip ${tripId}`,
      tripId,
    });
  }
  await supabaseAdmin
    .from('trips')
    .update({ status: 'cancelled', cancelled_at: new Date().toISOString(), cancel_reason: 'dispute_refunded' })
    .eq('id', tripId);
  return { refunded: refund };
}

/** Resolves a dispute WITHOUT a refund (in the rider's favour) → marks completed. */
export async function resolveDispute(tripId: string) {
  const { data: trip } = await supabaseAdmin.from('trips').select('id, status').eq('id', tripId).single();
  if (!trip) throw notFound('trip not found');
  if (trip.status !== 'disputed') throw conflict('trip is not in dispute');
  await supabaseAdmin
    .from('trips')
    .update({ status: 'completed', completed_at: new Date().toISOString() })
    .eq('id', tripId);
  return { resolved: true };
}

// ---- helpers ----
type QueryMod = (q: ReturnType<typeof baseCount>) => ReturnType<typeof baseCount>;
function baseCount(table: string) {
  return supabaseAdmin.from(table).select('id', { count: 'exact', head: true });
}
async function countRows(table: string, mod?: QueryMod): Promise<number> {
  const q = mod ? mod(baseCount(table)) : baseCount(table);
  const { count } = await q;
  return count ?? 0;
}
async function sumCompletedRevenue(): Promise<number> {
  const { data } = await supabaseAdmin
    .from('trips')
    .select('final_fare')
    .eq('status', 'completed')
    .gte('completed_at', startOfTodayISO());
  return (data ?? []).reduce((s, t) => s + (t.final_fare ?? 0), 0);
}
function startOfTodayISO(): string {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  return d.toISOString();
}
