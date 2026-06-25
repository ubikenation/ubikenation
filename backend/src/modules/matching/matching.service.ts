import { supabaseAdmin } from '../../config/supabase';
import { VEHICLE_CLASS_KIND, type VehicleClass } from '../../types/domain';

export interface NearbyRider {
  riderId: string;
  profileId: string;
  distanceKm: number;
  lat: number;
  lng: number;
  ratingAvg: number;
}

/** Haversine distance in km between two coordinates. */
export function haversineKm(aLat: number, aLng: number, bLat: number, bLng: number): number {
  const R = 6371;
  const dLat = toRad(bLat - aLat);
  const dLng = toRad(bLng - aLng);
  const lat1 = toRad(aLat);
  const lat2 = toRad(bLat);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}
const toRad = (d: number) => (d * Math.PI) / 180;

/**
 * Finds activated, online riders of the right kind within `radiusKm` of the pickup,
 * sorted nearest-first. (For scale this should move to a PostGIS/Redis geo index; this
 * exact version is correct and fine for launch volumes.)
 */
export async function findNearbyRiders(
  vehicleClass: VehicleClass,
  pickupLat: number,
  pickupLng: number,
  radiusKm = 5,
  limit = 10,
): Promise<NearbyRider[]> {
  const kind = VEHICLE_CLASS_KIND[vehicleClass];
  const { data } = await supabaseAdmin
    .from('riders')
    .select('id, profile_id, last_lat, last_lng, rating_avg')
    .eq('kind', kind)
    .eq('status', 'activated')
    .eq('is_online', true)
    .not('last_lat', 'is', null)
    .not('last_lng', 'is', null);

  const inRange = (data ?? [])
    .map((r) => ({
      riderId: r.id as string,
      profileId: r.profile_id as string,
      lat: r.last_lat as number,
      lng: r.last_lng as number,
      ratingAvg: Number(r.rating_avg ?? 5),
      distanceKm: haversineKm(pickupLat, pickupLng, r.last_lat as number, r.last_lng as number),
    }))
    .filter((r) => r.distanceKm <= radiusKm);
  // Closer riders are more likely to be picked first (but not guaranteed) so a
  // re-search can still reach a different rider.
  return weightedShuffleByDistance(inRange, (r) => r.distanceKm).slice(0, limit);
}

/**
 * Randomly shuffles a list (Fisher–Yates). Kept for uniform-random needs.
 */
export function shuffle<T>(items: readonly T[]): T[] {
  const a = [...items];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

/**
 * Distance-weighted random ordering: closer items are MORE likely to come first,
 * but the order is still randomised so re-requests vary. Uses the Efraimidis–Spirakis
 * weighted-sampling key `u^(1/w)` with weight `w = 1/distance` (a 50 m floor avoids
 * division by zero); larger keys sort first, so a nearer rider tends to win.
 */
export function weightedShuffleByDistance<T>(items: readonly T[], distanceOf: (item: T) => number): T[] {
  return items
    .map((item) => {
      const d = Math.max(distanceOf(item), 0.05); // 50 m floor
      const weight = 1 / d; // closer → larger weight
      const key = Math.pow(Math.random(), 1 / weight);
      return { item, key };
    })
    .sort((a, b) => b.key - a.key)
    .map((x) => x.item);
}
