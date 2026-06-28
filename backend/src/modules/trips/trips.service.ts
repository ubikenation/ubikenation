import { supabaseAdmin } from '../../config/supabase';
import { AppError, badRequest, conflict, forbidden, notFound } from '../../utils/http';
import { calculateFare, estimateErrandFare, validateAdjustment } from '../fare/fare.service';
import { releaseEscrow, refundEscrow } from '../payments/escrow.service';
import {
  COMMISSION_ADJUSTED, COMMISSION_NO_ADJUST, VEHICLE_CLASS_KIND, type VehicleClass,
} from '../../types/domain';
import { findNearbyRiders, haversineKm, weightedShuffleByDistance } from '../matching/matching.service';
import { getRoute } from '../routing/routing.service';
import { notifyProfiles } from '../notifications/notification.service';

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
 * Creates a trip and immediately starts matching (Uber/Bolt order): the trip goes
 * straight to `searching` with NO upfront payment yet. A nearby rider accepts, then
 * quotes the fare, and only then is the customer shown the price and pays 50%.
 * A `scheduledFor` time parks the trip in `scheduled` until it is due.
 * The fare computed here is the system estimate; it becomes the real price at quote time.
 */
export async function createTrip(input: CreateTripInput) {
  // Prefer the real driving route (Google Directions) over the client's straight-line
  // estimate so the booked fare reflects actual roads. Falls back silently if routing
  // is off/unavailable. Estimates shown pre-booking remain indicative (per the T&C).
  if (input.dropoff) {
    const route = await getRoute(input.pickup.lat, input.pickup.lng, input.dropoff.lat, input.dropoff.lng);
    if (route) {
      input = { ...input, distanceKm: route.distanceKm, durationMin: route.durationMin };
    }
  }

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
      status: input.scheduledFor ? 'scheduled' : 'searching',
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

  // Immediate requests go straight to matching — ping nearby riders. Fire-and-forget;
  // never block the booking on a push. (Scheduled trips ping later, when released.)
  if (data.status === 'searching') {
    void notifyNearbyRiders(input.vehicleClass, input.pickup.lat, input.pickup.lng);
  }

  return {
    tripId: data.id,
    fare: data.base_fare,
    upfront: data.upfront_amount,
    balance: data.balance_amount,
    status: data.status,
  };
}

/** Pushes a "new ride request nearby" to activated, online riders within 5km. */
async function notifyNearbyRiders(vehicleClass: VehicleClass, lat: number, lng: number) {
  try {
    const riders = await findNearbyRiders(vehicleClass, lat, lng, 5);
    await notifyProfiles(riders.map((r) => r.profileId), {
      title: 'New ride request nearby',
      body: 'A customer near you needs a ride. Open U-Bike to accept.',
      data: { type: 'new_request' },
    });
  } catch {
    /* push is best-effort */
  }
}

/**
 * A rider accepts a searching trip → `quote_pending`. The customer still only sees
 * "finding your rider" at this point; the rider now sets the price (see quoteFare).
 * Riders the customer has already passed on (declined_rider_ids) cannot accept.
 */
export async function assignRider(tripId: string, riderProfileId: string) {
  const { data: trip } = await supabaseAdmin
    .from('trips')
    .select('id, status, vehicle_class, declined_rider_ids')
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
  if ((trip.declined_rider_ids as string[] | null)?.includes(rider.id)) {
    throw conflict('this request is no longer available to you');
  }

  const { data, error } = await supabaseAdmin
    .from('trips')
    .update({ rider_id: rider.id, status: 'quote_pending', assigned_at: new Date().toISOString() })
    .eq('id', tripId)
    .eq('status', 'searching') // optimistic guard against double-accept
    .select('id, status')
    .single();
  if (error || !data) throw conflict('trip was already taken');
  return data;
}

/**
 * The rider, after accepting, confirms the price: either accepts the auto fare
 * (no `proposedFare`, or ≤ base) or nudges it up to +30% (no reason needed).
 * Adjusting at all raises the company commission from 20% → 25%. The trip then
 * moves to `awaiting_payment` and the customer is shown the price to pay 50%.
 */
export async function quoteFare(tripId: string, riderProfileId: string, proposedFare?: number) {
  const trip = await loadTripForRider(tripId, riderProfileId);
  if (trip.status !== 'quote_pending') throw conflict('this trip is not awaiting your quote');

  const base = trip.base_fare;
  const adjusted = proposedFare != null && proposedFare > base;

  let finalFare = base;
  let cap: ReturnType<typeof validateAdjustment> | null = null;
  if (adjusted) {
    cap = validateAdjustment({ originalFare: base, proposedFare: proposedFare! });
    finalFare = cap.cappedFare;
  }

  const commissionRate = adjusted ? COMMISSION_ADJUSTED : COMMISSION_NO_ADJUST;
  const upfront = roundTo5(finalFare * 0.5);

  await supabaseAdmin
    .from('trips')
    .update({
      status: 'awaiting_payment',
      adjusted,
      adjusted_fare: adjusted ? finalFare : null,
      final_fare: finalFare,
      commission_rate: commissionRate,
      upfront_amount: upfront,
      balance_amount: finalFare - upfront,
    })
    .eq('id', tripId)
    .eq('status', 'quote_pending');

  // Now the customer can be shown the price — nudge them to confirm & pay. If the
  // rider nudged the fare up, say so explicitly so the change isn't a surprise.
  void notifyProfiles([trip.customer_id], {
    title: adjusted ? 'Rider adjusted the fare' : 'Your rider is ready',
    body: adjusted
      ? `Your rider set the fare to KES ${finalFare} (was KES ${base}). Confirm and pay to start.`
      : `Confirm and pay to start your trip — KES ${finalFare}.`,
    data: {
      type: 'rider_found',
      tripId,
      adjusted: String(adjusted),
      baseFare: String(base),
      finalFare: String(finalFare),
    },
  });

  return {
    finalFare,
    adjusted,
    upfront,
    balance: finalFare - upfront,
    maxAllowedFare: cap?.maxAllowedFare ?? roundTo1(base * 1.3),
  };
}

/**
 * Customer passes on the current rider (long wait / cancel-rider before paying):
 * the rider is added to declined_rider_ids and the trip re-enters `searching` so a
 * different nearby rider can pick it up. Only valid before payment.
 */
export async function requeryTrip(tripId: string, customerId: string) {
  const { data: trip } = await supabaseAdmin
    .from('trips')
    .select('id, customer_id, status, rider_id, declined_rider_ids')
    .eq('id', tripId)
    .single();
  if (!trip) throw notFound('trip not found');
  if (trip.customer_id !== customerId) throw forbidden();
  if (!['quote_pending', 'awaiting_payment', 'searching'].includes(trip.status)) {
    throw conflict('cannot change rider at this stage');
  }
  const declined = new Set((trip.declined_rider_ids as string[] | null) ?? []);
  if (trip.rider_id) declined.add(trip.rider_id);

  await supabaseAdmin
    .from('trips')
    .update({
      status: 'searching',
      rider_id: null,
      adjusted: false,
      adjusted_fare: null,
      commission_rate: null,
      declined_rider_ids: [...declined],
    })
    .eq('id', tripId);
  return { status: 'searching' };
}

/**
 * Rider explicitly passes on a request: they're added to the trip's declined list
 * so it disappears from their available list and a different rider gets it. Best for
 * a request the rider doesn't want (too far, wrong direction, etc.).
 */
export async function declineRequest(tripId: string, riderProfileId: string) {
  const { data: rider } = await supabaseAdmin.from('riders').select('id').eq('profile_id', riderProfileId).single();
  if (!rider) throw forbidden('not a rider');
  const { data: trip } = await supabaseAdmin
    .from('trips')
    .select('id, status, declined_rider_ids')
    .eq('id', tripId)
    .single();
  if (!trip) throw notFound('trip not found');
  const declined = new Set((trip.declined_rider_ids as string[] | null) ?? []);
  declined.add(rider.id);
  await supabaseAdmin.from('trips').update({ declined_rider_ids: [...declined] }).eq('id', tripId);
  return { declined: true };
}

/**
 * Customer or assigned rider opens a dispute on an active/finished trip (when an
 * automatic cancel/refund isn't allowed). Moves the trip to `disputed` for an admin
 * to resolve (refund the customer, or resolve in the rider's favour).
 */
export async function openDispute(tripId: string, userId: string, reason: string) {
  const trip = await getTrip(tripId, userId); // verifies the caller is a party
  if (!['in_progress', 'awaiting_balance', 'arrived', 'completed'].includes(trip.status)) {
    throw conflict('this trip cannot be disputed at its current stage');
  }
  await supabaseAdmin
    .from('trips')
    .update({ status: 'disputed', cancel_reason: reason })
    .eq('id', tripId);
  return { status: 'disputed' };
}

export async function markArrived(tripId: string, riderProfileId: string) {
  const trip = await loadTripForRider(tripId, riderProfileId);
  await supabaseAdmin.from('trips').update({ status: 'arrived' }).eq('id', tripId).eq('status', 'rider_assigned');
  void notifyProfiles([trip.customer_id], {
    title: 'Your rider has arrived',
    body: 'Your rider is at the pickup point.',
    data: { type: 'rider_arrived', tripId },
  });
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

/**
 * Rider taps "reached destination". The other 50% is due now: if the customer has
 * already funded the balance (escrow holds the full fare) we complete and release
 * (20/80 or 25/75); otherwise the trip waits in `awaiting_balance` until the balance
 * payment settles (payments.service completes + releases on that webhook).
 */
export async function completeTrip(tripId: string, riderProfileId: string) {
  const trip = await loadTripForRider(tripId, riderProfileId);
  if (!['in_progress', 'awaiting_balance'].includes(trip.status)) {
    throw conflict('only an in-progress trip can be finished');
  }

  const { data: full } = await supabaseAdmin
    .from('trips')
    .select('final_fare')
    .eq('id', tripId)
    .single();
  const { data: esc } = await supabaseAdmin
    .from('escrow')
    .select('amount, status')
    .eq('trip_id', tripId)
    .maybeSingle();

  const funded = esc && esc.status === 'held' && esc.amount >= (full?.final_fare ?? Infinity);
  if (!funded) {
    await supabaseAdmin.from('trips').update({ status: 'awaiting_balance' }).eq('id', tripId);
    void notifyProfiles([trip.customer_id], {
      title: 'You\'ve arrived',
      body: 'Please pay the remaining balance to finish your trip.',
      data: { type: 'pay_balance', tripId },
    });
    return { status: 'awaiting_balance', balanceDue: true };
  }

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

/**
 * Customer cancels. Any time before the ride starts → the held upfront 50% is
 * refunded to the wallet immediately; after start → blocked (dispute path).
 * `reason` comes from the app's Uber-style cancellation question sheet.
 */
export async function cancelTrip(tripId: string, customerId: string, reason?: string) {
  const { data: trip } = await supabaseAdmin
    .from('trips')
    .select('id, customer_id, status')
    .eq('id', tripId)
    .single();
  if (!trip) throw notFound('trip not found');
  if (trip.customer_id !== customerId) throw forbidden();
  // Once you've met the rider (arrived) or the ride has started, you can't cancel —
  // open a dispute instead. Cancel is only allowed while still searching or the rider
  // is on the way (before arrival).
  if (['arrived', 'in_progress', 'awaiting_balance', 'completed'].includes(trip.status)) {
    throw conflict('the rider has already arrived; open a dispute instead of cancelling');
  }
  await refundEscrow(tripId).catch(() => undefined); // immediate refund to wallet; no-op if nothing held
  await supabaseAdmin
    .from('trips')
    .update({ status: 'cancelled', cancelled_at: new Date().toISOString(), cancel_reason: reason })
    .eq('id', tripId);
  return { status: 'cancelled' };
}

/**
 * Customer pushes their live GPS so the assigned rider can trace them to the pickup.
 * Allowed for the trip's customer while the trip is active.
 */
export async function updateCustomerLocation(tripId: string, customerId: string, lat: number, lng: number) {
  const { data: trip } = await supabaseAdmin.from('trips').select('id, customer_id').eq('id', tripId).single();
  if (!trip) throw notFound('trip not found');
  if (trip.customer_id !== customerId) throw forbidden();
  await supabaseAdmin
    .from('trips')
    .update({ customer_lat: lat, customer_lng: lng, customer_location_at: new Date().toISOString() })
    .eq('id', tripId);
  return { ok: true };
}

/**
 * The customer's live point + pickup/dropoff, for the rider's tracing map (mirror of
 * getRiderLocation). Accessible to the trip's rider or customer.
 */
export async function getCustomerLocation(tripId: string, userId: string) {
  const trip = await getTrip(tripId, userId);
  const { data: cust } = await supabaseAdmin
    .from('profiles')
    .select('full_name, avatar_url')
    .eq('id', trip.customer_id)
    .maybeSingle();
  return {
    customerName: cust?.full_name ?? 'Customer',
    customerPhoto: cust?.avatar_url ?? null,
    customerLat: trip.customer_lat ?? trip.pickup_lat,
    customerLng: trip.customer_lng ?? trip.pickup_lng,
    updatedAt: trip.customer_location_at ?? null,
    pickupLat: trip.pickup_lat,
    pickupLng: trip.pickup_lng,
    dropoffLat: trip.dropoff_lat,
    dropoffLng: trip.dropoff_lng,
    pickupAddress: trip.pickup_address,
    dropoffAddress: trip.dropoff_address,
    status: trip.status,
  };
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
    .select('id, vehicle_class, pickup_lat, pickup_lng, pickup_address, dropoff_address, base_fare, final_fare, distance_km, duration_min, errand_type, errand_details, created_at, declined_rider_ids')
    .eq('status', 'searching')
    .in('vehicle_class', classes)
    .order('created_at', { ascending: false })
    .limit(30);

  // Drop requests the customer already passed on for this rider, and strip the
  // internal declined list before returning.
  const list = (trips ?? [])
    .filter((t) => !((t.declined_rider_ids as string[] | null) ?? []).includes(rider.id))
    .map(({ declined_rider_ids: _omit, ...t }) => t);
  if (rider.last_lat == null || rider.last_lng == null) return list;

  // Surface only pickups within 5 km, ordered by a distance-weighted shuffle: the
  // closer the pickup is to this rider, the more likely it appears near the top —
  // but still randomised, so a customer who passes on one rider is likely to reach
  // a different rider on the re-search.
  const RADIUS_KM = 5;
  const inRange = list
    .map((t) => ({ ...t, pickupDistanceKm: haversineKm(rider.last_lat!, rider.last_lng!, t.pickup_lat, t.pickup_lng) }))
    .filter((t) => t.pickupDistanceKm <= RADIUS_KM);
  return weightedShuffleByDistance(inRange, (t) => t.pickupDistanceKm);
}

/** The authenticated customer's own trips (history). */
export async function listMyTrips(customerId: string, limit = 50) {
  const { data } = await supabaseAdmin
    .from('trips')
    .select('id, trip_type, vehicle_class, status, final_fare, base_fare, balance_amount, pickup_address, dropoff_address, errand_type, scheduled_for, created_at')
    .eq('customer_id', customerId)
    .eq('hidden_by_customer', false)
    .order('created_at', { ascending: false })
    .limit(limit);
  return data ?? [];
}

/** Customer removes a trip from their history (soft delete; only terminal trips). */
export async function hideTrip(tripId: string, customerId: string) {
  const { data: trip } = await supabaseAdmin.from('trips').select('id, customer_id, status').eq('id', tripId).single();
  if (!trip) throw notFound('trip not found');
  if (trip.customer_id !== customerId) throw forbidden();
  if (!['completed', 'cancelled', 'expired'].includes(trip.status)) {
    throw conflict('only finished trips can be removed from history');
  }
  await supabaseAdmin.from('trips').update({ hidden_by_customer: true }).eq('id', tripId);
  return { hidden: true };
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
    .select('id, last_lat, last_lng, last_location_at, rating_avg, rating_count, profile_id, profile_photo_url, selfie_url, vehicle_photo_url, plate_number, plate_photo_url, vehicle_make, vehicle_model, vehicle_color')
    .eq('id', trip.rider_id)
    .single();
  const { data: prof } = await supabaseAdmin
    .from('profiles')
    .select('full_name, avatar_url')
    .eq('id', rider?.profile_id ?? '')
    .maybeSingle();

  // A car rider may have its plate/photos on the vehicles row instead of riders.
  const { data: vehicle } = await supabaseAdmin
    .from('vehicles')
    .select('plate_number, make, model, color, plate_photo_url')
    .eq('rider_id', trip.rider_id)
    .limit(1)
    .maybeSingle();

  const sign = async (path?: string | null) => {
    if (!path) return null;
    const { data } = await supabaseAdmin.storage.from('rider-documents').createSignedUrl(path, 60 * 60);
    return data?.signedUrl ?? null;
  };

  // Signed URL for the rider's profile photo (private bucket), for the chat/tracking UI.
  let photoUrl: string | null = prof?.avatar_url ?? null;
  if (!photoUrl) photoUrl = await sign(rider?.profile_photo_url ?? rider?.selfie_url);
  const vehiclePhoto = await sign(rider?.vehicle_photo_url);
  const platePhoto = await sign(rider?.plate_photo_url ?? vehicle?.plate_photo_url);

  return {
    hasRider: true,
    riderName: prof?.full_name ?? 'Your rider',
    riderPhoto: photoUrl,
    rating: Number(rider?.rating_avg ?? 5),
    ratingCount: rider?.rating_count ?? 0,
    // Vehicle identity so the customer recognises the rider, Bolt-style.
    plateNumber: rider?.plate_number ?? vehicle?.plate_number ?? null,
    vehicleMake: rider?.vehicle_make ?? vehicle?.make ?? null,
    vehicleModel: rider?.vehicle_model ?? vehicle?.model ?? null,
    vehicleColor: rider?.vehicle_color ?? vehicle?.color ?? null,
    vehiclePhoto,
    platePhoto,
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

const roundTo5 = (n: number) => Math.round(n / 5) * 5;
const roundTo1 = (n: number) => Math.round(n);

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
    .select('id, status, base_fare, rider_id, customer_id')
    .eq('id', tripId)
    .single();
  if (!trip) throw notFound('trip not found');
  if (trip.rider_id !== rider.id) throw forbidden('not your trip');
  return trip;
}
