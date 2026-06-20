export type RiderKind = 'bike' | 'car' | 'errands';

export type VehicleClass =
  | 'standard_bike'
  | 'electric_bike'
  | 'economy'
  | 'comfort'
  | 'suv'
  | 'errands';

export type AdjustmentReason =
  | 'heavy_rain'
  | 'flooding'
  | 'road_closure'
  | 'accident_ahead'
  | 'traffic_congestion'
  | 'diversion_route'
  | 'security_alert'
  | 'fuel_cost_surge'
  | 'remote_pickup_area'
  | 'public_event_congestion';

export type TripStatus =
  | 'pending_payment'
  | 'searching'
  | 'quote_pending'
  | 'awaiting_payment'
  | 'rider_assigned'
  | 'arrived'
  | 'in_progress'
  | 'awaiting_balance'
  | 'completed'
  | 'cancelled'
  | 'expired'
  | 'scheduled'
  | 'disputed';

export type CommuterFrequency = 'daily' | 'weekdays' | 'weekly';

/** Company commission depends on whether the rider adjusted the auto fare. */
export const COMMISSION_NO_ADJUST = 0.2; // rider keeps 80%
export const COMMISSION_ADJUSTED = 0.25; // rider keeps 75% (penalty for nudging the fare)

export const VEHICLE_CLASS_KIND: Record<VehicleClass, RiderKind> = {
  standard_bike: 'bike',
  electric_bike: 'bike',
  economy: 'car',
  comfort: 'car',
  suv: 'car',
  errands: 'errands',
};
