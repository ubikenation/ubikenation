import { env } from '../../config/env';
import { supabaseAdmin } from '../../config/supabase';
import { AppError, badRequest } from '../../utils/http';
import { haversineKm } from '../matching/matching.service';
import { getRoute } from '../routing/routing.service';
import type { VehicleClass } from '../../types/domain';

export interface FareInputs {
  vehicleClass: VehicleClass;
  distanceKm: number;
  durationMin: number;
  /** 0..1 surge signals; supplied by traffic/weather/demand checks. */
  trafficFactor?: number; // e.g. 0.15 = +15%
  weatherFactor?: number;
  demandFactor?: number;
  pickupDifficulty?: number;
}

export interface FareBreakdown {
  vehicleClass: VehicleClass;
  baseFare: number; // final system fare in KES (what the customer is shown)
  upfrontAmount: number; // 50%
  balanceAmount: number; // 50%
  // The component breakdown is server-only; never returned to the customer app.
  _internal: {
    baseComponent: number;
    distanceComponent: number;
    timeComponent: number;
    surgeMultiplier: number;
    minimumApplied: boolean;
  };
}

/**
 * Server-side fare calculation. The customer never receives the formula — only `baseFare`,
 * `upfrontAmount`, `balanceAmount` are surfaced by the API layer.
 */
export async function calculateFare(input: FareInputs): Promise<FareBreakdown> {
  if (input.distanceKm < 0 || input.durationMin < 0) {
    throw badRequest('distance and duration must be non-negative');
  }

  const { data: cfg, error } = await supabaseAdmin
    .from('fare_config')
    .select('base_fare, per_km, per_min, minimum_fare')
    .eq('vehicle_class', input.vehicleClass)
    .single();

  if (error || !cfg) throw new AppError(404, `No fare config for ${input.vehicleClass}`);

  const baseComponent = cfg.base_fare;
  const distanceComponent = input.distanceKm * Number(cfg.per_km);
  const timeComponent = input.durationMin * Number(cfg.per_min);

  const surge =
    1 +
    clamp01(input.trafficFactor) +
    clamp01(input.weatherFactor) +
    clamp01(input.demandFactor) +
    clamp01(input.pickupDifficulty);

  const raw = (baseComponent + distanceComponent + timeComponent) * surge;
  const minimumApplied = raw < cfg.minimum_fare;
  const baseFare = roundTo(Math.max(raw, cfg.minimum_fare), 5);

  const upfrontAmount = roundTo(baseFare * env.UPFRONT_PAYMENT_RATIO, 5);
  const balanceAmount = baseFare - upfrontAmount;

  return {
    vehicleClass: input.vehicleClass,
    baseFare,
    upfrontAmount,
    balanceAmount,
    _internal: {
      baseComponent,
      distanceComponent: roundTo(distanceComponent, 1),
      timeComponent: roundTo(timeComponent, 1),
      surgeMultiplier: roundTo(surge, 3),
      minimumApplied,
    },
  };
}

/**
 * Fare estimates for EVERY ride vehicle class for a from→to route, computed once from
 * the real driving distance (Google Directions, falling back to straight-line). Used by
 * the customer's vehicle-picker so each option shows its price before they choose.
 */
export async function estimateAllFares(
  pickup: { lat: number; lng: number },
  dropoff: { lat: number; lng: number },
) {
  let distanceKm = haversineKm(pickup.lat, pickup.lng, dropoff.lat, dropoff.lng);
  let durationMin = (distanceKm / 22) * 60;
  const route = await getRoute(pickup.lat, pickup.lng, dropoff.lat, dropoff.lng);
  if (route) {
    distanceKm = route.distanceKm;
    durationMin = route.durationMin;
  }

  const classes: VehicleClass[] = ['standard_bike', 'electric_bike', 'economy', 'comfort', 'suv', 'errands'];
  const fares = [];
  for (const vehicleClass of classes) {
    try {
      const f = await calculateFare({ vehicleClass, distanceKm, durationMin });
      fares.push({ vehicleClass, fare: f.baseFare, upfront: f.upfrontAmount, balance: f.balanceAmount });
    } catch {
      /* skip a class with no config */
    }
  }
  return { distanceKm: Math.round(distanceKm * 100) / 100, durationMin: Math.round(durationMin), fares };
}

export interface AdjustmentRequest {
  originalFare: number;
  proposedFare: number;
}

export interface AdjustmentResult {
  approved: boolean;
  cappedFare: number;
  percentIncrease: number;
  maxAllowedFare: number;
  message: string;
}

/**
 * Validates a rider's fare adjustment: it must not exceed +30% of the system fare.
 * No reason is required (the owner simplified this) — the rider may nudge the auto
 * fare up to the cap. Adjusting at all costs the rider a higher commission, handled
 * by the caller via {@link COMMISSION_ADJUSTED}.
 */
export function validateAdjustment(req: AdjustmentRequest): AdjustmentResult {
  const maxAllowedFare = roundTo(req.originalFare * (1 + env.MAX_RIDER_PRICE_ADJUSTMENT), 1);
  const percentIncrease = (req.proposedFare - req.originalFare) / req.originalFare;

  if (req.proposedFare < req.originalFare) {
    throw badRequest('Adjusted fare cannot be lower than the system fare');
  }

  const approved = req.proposedFare <= maxAllowedFare;
  return {
    approved,
    cappedFare: approved ? req.proposedFare : maxAllowedFare,
    percentIncrease: roundTo(percentIncrease, 4),
    maxAllowedFare,
    message: approved
      ? 'Adjustment within allowed range'
      : `Adjustment exceeds the ${Math.round(env.MAX_RIDER_PRICE_ADJUSTMENT * 100)}% cap; fare capped`,
  };
}

// Per-item handling fee (KES) by errand category — shopping tasks cost more
// per item than a simple parcel/document drop.
const ERRAND_PER_ITEM: Record<string, number> = {
  grocery_shopping: 50,
  shopping_assistance: 50,
  food_pickup: 40,
  pharmacy_pickup: 45,
  gift_delivery: 40,
  parcel_delivery: 30,
  document_delivery: 30,
  business_delivery: 35,
  office_delivery: 35,
  utility_payment: 40,
  personal_assistant: 45,
  custom: 40,
};

export interface ErrandEstimateInput {
  errandType: string;
  description: string;
  distanceKm: number;
  durationMin: number;
}

export interface ErrandEstimate {
  fare: number;
  upfront: number;
  balance: number;
  itemCount: number;
  perItem: number;
}

/**
 * Automatically estimates an errand fare from what the customer listed. The
 * description is "scanned" into individual items (split on new lines / commas /
 * semicolons / bullets); more items + a per-item handling fee + distance/time +
 * the errands base all roll into the fare. The rider may then adjust it ≤30%.
 */
export async function estimateErrandFare(input: ErrandEstimateInput): Promise<ErrandEstimate> {
  const { data: cfg } = await supabaseAdmin
    .from('fare_config')
    .select('base_fare, per_km, per_min, minimum_fare')
    .eq('vehicle_class', 'errands')
    .single();

  const base = cfg?.base_fare ?? 150;
  const perKm = Number(cfg?.per_km ?? 30);
  const perMin = Number(cfg?.per_min ?? 3);
  const minimum = cfg?.minimum_fare ?? 300;

  const items = input.description
    .split(/\r?\n|,|;|•|•|\d+\.|\*/)
    .map((s) => s.trim())
    .filter((s) => s.length > 1);
  const itemCount = Math.max(items.length, 1);
  const perItem = ERRAND_PER_ITEM[input.errandType] ?? 40;

  const raw =
    base +
    input.distanceKm * perKm +
    input.durationMin * perMin +
    itemCount * perItem;

  const fare = Math.max(roundTo(raw, 5), minimum);
  const upfront = roundTo(fare * env.UPFRONT_PAYMENT_RATIO, 5);
  return { fare, upfront, balance: fare - upfront, itemCount, perItem };
}

function clamp01(n?: number): number {
  if (!n || Number.isNaN(n)) return 0;
  return Math.min(Math.max(n, 0), 1);
}
function roundTo(n: number, step: number): number {
  return Math.round(n / step) * step;
}
