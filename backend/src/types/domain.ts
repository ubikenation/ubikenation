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

export const VEHICLE_CLASS_KIND: Record<VehicleClass, RiderKind> = {
  standard_bike: 'bike',
  electric_bike: 'bike',
  economy: 'car',
  comfort: 'car',
  suv: 'car',
  errands: 'errands',
};
