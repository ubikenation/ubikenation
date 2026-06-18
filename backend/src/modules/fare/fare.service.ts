import { env } from '../../config/env';
import { supabaseAdmin } from '../../config/supabase';
import { AppError, badRequest } from '../../utils/http';
import type { AdjustmentReason, VehicleClass } from '../../types/domain';

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

export interface AdjustmentRequest {
  originalFare: number;
  proposedFare: number;
  reason: AdjustmentReason;
}

export interface AdjustmentResult {
  approved: boolean;
  cappedFare: number;
  percentIncrease: number;
  maxAllowedFare: number;
  reason: AdjustmentReason;
  message: string;
}

const VALID_REASONS = new Set<AdjustmentReason>([
  'heavy_rain',
  'flooding',
  'road_closure',
  'accident_ahead',
  'traffic_congestion',
  'diversion_route',
  'security_alert',
  'fuel_cost_surge',
  'remote_pickup_area',
  'public_event_congestion',
]);

/**
 * Validates a rider's fare adjustment: must use an approved reason and stay within +30%.
 * (Automated cross-checks against Google traffic / weather are layered on top in
 * validation.service — this enforces the hard business cap.)
 */
export function validateAdjustment(req: AdjustmentRequest): AdjustmentResult {
  if (!VALID_REASONS.has(req.reason)) {
    throw badRequest('Adjustment reason must be one of the approved reasons');
  }
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
    reason: req.reason,
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
