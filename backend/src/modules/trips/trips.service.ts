import { supabaseAdmin } from '../../config/supabase';
import { AppError, badRequest, conflict, forbidden, notFound } from '../../utils/http';
import { calculateFare, estimateErrandFare, validateAdjustment } from '../fare/fare.service';
import { releaseEscrow, refundEscrow } from '../payments/escrow.service';
import { VEHICLE_CLASS_KIND, type AdjustmentReason, type VehicleClass } from '../../types/domain';
import { haversineKm } from '../matching/matching.service';

export interface CreateTripInput {
  customerId: string;
  tripType: 'bike' | 'car' | 'errands' | 'scheduled';
  vehicleClass: VehicleClass;
  pickup: { lat: number; lng: number; address?: string };
  dropoff?: { lat: number; lng: number; address?: string };
  distanceKm: number;
  durationMin: number;
  scheduledFor?: string;
  errandType?: string;
  errandDetails?: Record<string, unknown>;
}

/**
 * Creates a trip in `pending_payment`, calculating the fare server-side and the 50/50 split.
 * The trip moves to `searching` only after the upfront payment settles (see payments.service).
 */
export async function createTrip(input: CreateTripInput) {
  // Errands are priced from the listed items; rides from distance/time/surge.
  const fare =
    input.vehicleClass === 'errands'
      ? await estimateErrandFare({
          errandType: input.errandType ?? 'custom',
          description: (input.errandDetails?.description as string) ?? '',
          distanceKm: input.distanceKm,
          durationMin: input.durationMin,
        }).then((e) => ({ baseFare: e.fare, upfrontAmount: e.upfront, balanceAmount: e.balance }))
      : await calculateFare({
          vehicleClass: input.vehicleClass,
          distanceKm: input.distanceKm,
          durationMin: input.durationMin,
        });

  const { data, error } = await supabaseAdmin
    .from('trips')
    .insert({
      customer_id: input.customerId,
      trip_type: input.tripType,
      vehicle_class: input.vehicleClass,
      status: 'pending_payment',
      pickup_lat: input.pickup.lat,
      pickup_lng: input.pickup.lng,
      pickup_address: input.pickup.address,
      dropoff_lat: input.dropoff?.lat,
      dropoff_lng: input.dropoff?.lng,
      dropoff_address: input.dropoff?.address,
      distance_km: input.distanceKm,
      duration_min: input.durationMin,
      base_fare: fare.baseFare,
      final_fare: fare.baseFare,
      upfront_amount: fare.upfrontAmount,
      balance_amount: fare.balanceAmount,
      scheduled_for: input.scheduledFor,
      errand_type: input.errandType,
      errand_details: input.errandDetails,
    })
    .select('id, base_fare, upfront_amount, balance_amount, status')
    .single();
  if (error) throw new AppError(500, `could not create trip: ${error.message}`);

  return {
    tripId: data.id,
    fare: data.base_fare,
    upfront: data.upfront_amount,
    balance: data.balance_amount,
    status: data.status,
  };
}

/** A rider accepts a searching trip. Verifies vehicle class matches the rider's kind. */
export async function assignRider(tripId: string, riderProfileId: string) {
  const { data: trip } = await supabaseAdmin
    .from('trips')
    .select('id, status, vehicle_class')
    .eq('id', tripId)
    .single();
  if (!trip) throw notFound('trip not found');
  if (trip.status !== 'searching') throw conflict('trip is not awaiting a rider');

  const { data: rider } = await supabaseAdmin
    .from('riders')
    .select('id, kind, status, is_online')
    .eq('profile_id', riderProfileId)
    .single();
  if (!rider) throw forbidden('not a registered rider');
  if (rider.status !== 'activated') throw forbidden('rider is not activated');
  if (VEHICLE_CLASS_KIND[trip.vehicle_class as VehicleClass] !== rider.kind) {
    throw conflict('rider kind does not match the requested service');
  }

  const { data, error } = await supabaseAdmin
    .from('trips')
    .update({ rider_id: rider.id, status: 'rider_assigned', assigned_at: new Date().toISOString() })
    .eq('id', tripId)
    .eq('status', 'searching') // optimistic guard against double-accept
    .select('id, status')
    .single();
  if (error || !data) throw conflict('trip was already taken');
  return data;
}

/** Rider proposes an adjusted fare (<= +30%, approved reason). Customer must accept. */
export async function riderAdjustFare(tripId: string, riderProfileId: string, proposedFare: number, reason: AdjustmentReason) {
  const trip = await loadTripForRider(tripId, riderProfileId);
  if (!['rider_assigned', 'arrived'].includes(trip.status)) {
    throw conflict('fare can only be adjusted before the trip starts');
  }
  const result = validateAdjustment({ originalFare: trip.base_fare, proposedFare, reason });

  await supabaseAdmin
    .from('trips')
    .update({ adjusted_fare: result.cappedFare, adjustment_reason: reason, adjustment_accepted: null })
    .eq('id', tripId);
  return result;
}

/** Customer accepts/declines the rider's adjusted fare. Decline re-broadcasts. */
export async function respondToAdjustment(tripId: string, customerId: string, accept: boolean) {
  const { data: trip } = await supabaseAdmin
    .from('trips')
    .select('id, customer_id, adjusted_fare, base_fare, status')
    .eq('id', tripId)
    .single();
  if (!trip) throw notFound('trip not found');
  if (trip.customer_id !== customerId) throw forbidden();
  if (trip.adjusted_fare == null) throw badRequest('no pending adjustment');

  if (accept) {
    const upfront = Math.round(trip.adjusted_fare * 0.5 / 5) * 5;
    await supabaseAdmin
      .from('trips')
      .update({
        adjustment_accepted: true,
        final_fare: trip.adjusted_fare,
        upfront_amount: upfront,
        balance_amount: trip.adjusted_fare - upfront,
      })
      .eq('id', tripId);
    return { accepted: true, finalFare: trip.adjusted_fare };
  }

  // declined: drop the rider and re-search
  await supabaseAdmin
    .from('trips')
    .update({ adjustment_accepted: false, rider_id: null, status: 'searching', final_fare: trip.base_fare })
    .eq('id', tripId);
  return { accepted: false, finalFare: trip.base_fare };
}

export async function markArrived(tripId: string, riderProfileId: string) {
  await loadTripForRider(tripId, riderProfileId);
  await supabaseAdmin.from('trips').update({ status: 'arrived' }).eq('id', tripId).eq('status', 'rider_assigned');
  return { status: 'arrived' };
}

/** Rider starts the trip. After this point escrow is locked (cancel needs a dispute). */
export async function startTrip(tripId: string, riderProfileId: string) {
  const trip = await loadTripForRider(tripId, riderProfileId);
  if (!['rider_assigned', 'arrived'].includes(trip.status)) throw conflict('trip cannot start from its current state');
  await supabaseAdmin
    .from('trips')
    .update({ status: 'in_progress', started_at: new Date().toISOString() })
    .eq('id', tripId);
  return { status: 'in_progress' };
}

/** Rider completes the trip → release escrow (20/80 split, queue payout). */
export async function completeTrip(tripId: string, riderProfileId: string) {
  const trip = await loadTripForRider(tripId, riderProfileId);
  if (trip.status !== 'in_progress') throw conflict('only in-progress trips can be completed');
  await supabaseAdmin
    .from('trips')
    .update({ status: 'completed', completed_at: new Date().toISOString() })
    .eq('id', tripId);
  const split = await releaseEscrow(tripId);
  await autoGradeRider(tripId);
  return { status: 'completed', split };
}

/**
 * Automatically grades the rider when a trip completes (5 stars baseline, minus
 * one star per violation logged on this trip). This guarantees every completed
 * trip updates the rider's rating even if the customer doesn't rate manually. A
 * later customer rating overrides this entry.
 */
async function autoGradeRider(tripId: string) {
  const { data: trip } = await supabaseAdmin
    .from('trips')
    .select('id, customer_id, rider_id')
    .eq('id', tripId)
    .single();
  if (!trip?.rider_id) return;

  // Don't overwrite an existing (customer) rating.
  const { data: existing } = await supabaseAdmin.from('ratings').select('id').eq('trip_id', tripId).maybeSingle();
  if (existing) return;

  const { count: violations } = await supabaseAdmin
    .from('rider_violations')
    .select('id', { count: 'exact', head: true })
    .eq('rider_id', trip.rider_id)
    .eq('trip_id', tripId);
  const stars = Math.max(1, 5 - (violations ?? 0));

  await supabaseAdmin.from('ratings').upsert(
    { trip_id: tripId, customer_id: trip.customer_id, rider_id: trip.rider_id, stars, comment: 'Auto-graded by system' },
    { onConflict: 'trip_id' },
  );
  const { data: rider } = await supabaseAdmin
    .from('riders')
    .select('rating_avg, rating_count')
    .eq('id', trip.rider_id)
    .single();
  if (rider) {
    const c = rider.rating_count + 1;
    const avg = (Number(rider.rating_avg) * rider.rating_count + stars) / c;
    await supabaseAdmin.from('riders').update({ rating_avg: Math.round(avg * 100) / 100, rating_count: c }).eq('id', trip.rider_id);
  }
}

/** Customer cancels. Before start → 100% refund; after start → blocked (dispute path). */
export async function cancelTrip(tripId: string, customerId: string, reason?: string) {
  const { data: trip } = await supabaseAdmin
    .from('trips')
    .select('id, customer_id, status')
    .eq('id', tripId)
    .single();
  if (!trip) throw notFound('trip not found');
  if (trip.customer_id !== customerId) throw forbidden();
  if (['in_progress', 'completed'].includes(trip.status)) {
    throw conflict('trip already started; open a dispute instead');
  }
  await refundEscrow(tripId).catch(() => undefined); // no-op if nothing was held
  await supabaseAdmin
    .from('trips')
    .update({ status: 'cancelled', cancelled_at: new Date().toISOString(), cancel_reason: reason })
    .eq('id', tripId);
  return { status: 'cancelled' };
}

/** Customer rates the rider after completion; updates the rider's rolling average. */
export async function rateTrip(tripId: string, customerId: string, stars: number, comment?: string) {
  if (stars < 1 || stars > 5) throw badRequest('stars must be 1-5');
  const { data: trip } = await supabaseAdmin
    .from('trips')
    .select('id, customer_id, rider_id, status')
    .eq('id', tripId)
    .single();
  if (!trip) throw notFound('trip not found');
  if (trip.customer_id !== customerId) throw forbidden();
  if (trip.status !== 'completed') throw conflict('can only rate a completed trip');
  if (!trip.rider_id) throw conflict('trip has no rider');

  await supabaseAdmin.from('ratings').upsert(
    { trip_id: tripId, customer_id: customerId, rider_id: trip.rider_id, stars, comment },
    { onConflict: 'trip_id' },
  );

  const { data: rider } = await supabaseAdmin
    .from('riders')
    .select('rating_avg, rating_count')
    .eq('id', trip.rider_id)
    .single();
  if (rider) {
    const count = rider.rating_count + 1;
    const avg = (Number(rider.rating_avg) * rider.rating_count + stars) / count;
    await supabaseAdmin
      .from('riders')
      .update({ rating_avg: Math.round(avg * 100) / 100, rating_count: count })
      .eq('id', trip.rider_id);
  }
  return { rated: true };
}

/** Lists searching trips a given rider is eligible to accept, nearest pickup first. */
export async function listAvailableTrips(riderProfileId: string) {
  const { data: rider } = await supabaseAdmin
    .from('riders')
    .select('id, kind, status, is_online, last_lat, last_lng')
    .eq('profile_id', riderProfileId)
    .maybeSingle();
  if (!rider || rider.status !== 'activated') throw forbidden('rider not activated');

  const classes = CLASSES_BY_KIND[rider.kind as keyof typeof CLASSES_BY_KIND] ?? [];
  const { data: trips } = await supabaseAdmin
    .from('trips')
    .select('id, vehicle_class, pickup_lat, pickup_lng, pickup_address, dropoff_address, base_fare, final_fare, distance_km, duration_min, created_at')
    .eq('status', 'searching')
    .in('vehicle_class', classes)
    .order('created_at', { ascending: false })
    .limit(30);

  const list = trips ?? [];
  if (rider.last_lat == null || rider.last_lng == null) return list;
  // Only surface trips whose pickup is within range of this rider, nearest first.
  // The closest rider in range gets first sight of the request.
  const RADIUS_KM = 7;
  return list
    .map((t) => ({ ...t, pickupDistanceKm: haversineKm(rider.last_lat!, rider.last_lng!, t.pickup_lat, t.pickup_lng) }))
    .filter((t) => t.pickupDistanceKm <= RADIUS_KM)
    .sort((a, b) => a.pickupDistanceKm - b.pickupDistanceKm);
}

/** The authenticated customer's own trips (history). */
export async function listMyTrips(customerId: string, limit = 50) {
  const { data } = await supabaseAdmin
    .from('trips')
    .select('id, trip_type, vehicle_class, status, final_fare, base_fare, balance_amount, pickup_address, dropoff_address, errand_type, created_at')
    .eq('customer_id', customerId)
    .order('created_at', { ascending: false })
    .limit(limit);
  return data ?? [];
}

/** Returns a trip if the caller is the customer or the assigned rider. */
export async function getTrip(tripId: string, userId: string) {
  const { data: trip } = await supabaseAdmin.from('trips').select('*').eq('id', tripId).single();
  if (!trip) throw notFound('trip not found');
  if (trip.customer_id === userId) return trip;
  if (trip.rider_id) {
    const { data: rider } = await supabaseAdmin.from('riders').select('profile_id').eq('id', trip.rider_id).single();
    if (rider?.profile_id === userId) return trip;
  }
  throw forbidden('not your trip');
}

/**
 * Live location of the rider assigned to a trip, for the customer's tracking
 * map. Returns the rider's last GPS ping + pickup/dropoff so the client can draw
 * the route and compute distance/ETA. Accessible to the trip's customer or rider.
 */
export async function getRiderLocation(tripId: string, userId: string) {
  const trip = await getTrip(tripId, userId); // verifies the caller is a party
  if (!trip.rider_id) return { hasRider: false };

  const { data: rider } = await supabaseAdmin
    .from('riders')
    .select('last_lat, last_lng, last_location_at, rating_avg, rating_count, profile_id, profile_photo_url, selfie_url')
    .eq('id', trip.rider_id)
    .single();
  const { data: prof } = await supabaseAdmin
    .from('profiles')
    .select('full_name, avatar_url')
    .eq('id', rider?.profile_id ?? '')
    .maybeSingle();

  // Signed URL for the rider's profile photo (private bucket), for the chat/tracking UI.
  let photoUrl: string | null = prof?.avatar_url ?? null;
  const photoPath = rider?.profile_photo_url ?? rider?.selfie_url;
  if (!photoUrl && photoPath) {
    const { data: signed } = await supabaseAdmin.storage.from('rider-documents').createSignedUrl(photoPath, 60 * 60);
    photoUrl = signed?.signedUrl ?? null;
  }

  return {
    hasRider: true,
    riderName: prof?.full_name ?? 'Your rider',
    riderPhoto: photoUrl,
    rating: Number(rider?.rating_avg ?? 5),
    ratingCount: rider?.rating_count ?? 0,
    riderLat: rider?.last_lat ?? null,
    riderLng: rider?.last_lng ?? null,
    updatedAt: rider?.last_location_at ?? null,
    pickupLat: trip.pickup_lat,
    pickupLng: trip.pickup_lng,
    dropoffLat: trip.dropoff_lat,
    dropoffLng: trip.dropoff_lng,
    status: trip.status,
  };
}

const CLASSES_BY_KIND = {
  bike: ['standard_bike', 'electric_bike'],
  car: ['economy', 'comfort', 'suv'],
  errands: ['errands'],
} as const;

async function loadTripForRider(tripId: string, riderProfileId: string) {
  const { data: rider } = await supabaseAdmin.from('riders').select('id').eq('profile_id', riderProfileId).single();
  if (!rider) throw forbidden('not a rider');
  const { data: trip } = await supabaseAdmin
    .from('trips')
    .select('id, status, base_fare, rider_id')
    .eq('id', tripId)
    .single();
  if (!trip) throw notFound('trip not found');
  if (trip.rider_id !== rider.id) throw forbidden('not your trip');
  return trip;
}
