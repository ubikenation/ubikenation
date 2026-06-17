import { supabaseAdmin } from '../../config/supabase';
import { env } from '../../config/env';
import { AppError, notFound } from '../../utils/http';

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
