import axios from 'axios';
import { env } from '../../config/env';
import { logger } from '../../utils/logger';

export interface Route {
  distanceKm: number;
  durationMin: number;
}

/**
 * Real driving route distance/time from Google Directions, so fares reflect actual
 * roads rather than straight-line distance. Returns null (caller falls back to the
 * client-supplied straight-line estimate) if routing is disabled, no key is set, or
 * the API errors/denies — so a missing/limited key never breaks a booking.
 */
export async function getRoute(
  pickupLat: number,
  pickupLng: number,
  dropLat: number,
  dropLng: number,
): Promise<Route | null> {
  if (!env.ENABLE_REAL_ROUTING || !env.GOOGLE_MAPS_API_KEY) return null;
  try {
    const { data } = await axios.get('https://maps.googleapis.com/maps/api/directions/json', {
      params: {
        origin: `${pickupLat},${pickupLng}`,
        destination: `${dropLat},${dropLng}`,
        mode: 'driving',
        key: env.GOOGLE_MAPS_API_KEY,
      },
      timeout: 8_000,
    });
    if (data.status !== 'OK' || !data.routes?.length) {
      logger.warn({ status: data.status }, 'directions returned no route; using straight-line');
      return null;
    }
    const leg = data.routes[0].legs[0];
    return {
      distanceKm: Math.round((leg.distance.value / 1000) * 100) / 100,
      durationMin: Math.round((leg.duration.value / 60) * 10) / 10,
    };
  } catch (e) {
    logger.warn({ err: (e as Error).message }, 'directions request failed; using straight-line');
    return null;
  }
}
