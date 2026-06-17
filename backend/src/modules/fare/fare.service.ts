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

function clamp01(n?: number): number {
  if (!n || Number.isNaN(n)) return 0;
  return Math.min(Math.max(n, 0), 1);
}
function roundTo(n: number, step: number): number {
  return Math.round(n / step) * step;
}
