/// Registration fee quote (founding-slot aware).
class FeeQuote {
  final bool isFounding;
  final int registrationFee;
  final int slotsRemaining;
  final bool paymentRequired;

  /// True if this rider already paid their one-time registration fee — never charge again.
  final bool alreadyPaid;

  const FeeQuote({
    required this.isFounding,
    required this.registrationFee,
    required this.slotsRemaining,
    required this.paymentRequired,
    this.alreadyPaid = false,
  });

  factory FeeQuote.fromJson(Map<String, dynamic> j) => FeeQuote(
        isFounding: j['isFounding'] as bool? ?? false,
        registrationFee: (j['registrationFee'] as num?)?.toInt() ?? 0,
        slotsRemaining: (j['slotsRemaining'] as num?)?.toInt() ?? 0,
        paymentRequired: j['paymentRequired'] as bool? ?? (((j['registrationFee'] as num?)?.toInt() ?? 0) > 0),
        alreadyPaid: j['alreadyPaid'] as bool? ?? false,
      );
}

/// The rider's verification/account record.
class RiderRecord {
  final String id;
  final String status; // submitted | under_review | approved | activated | suspended | banned
  final bool isFounding;
  final int registrationFee;
  final bool registrationPaid;
  final bool isOnline;
  final double ratingAvg;

  const RiderRecord({
    required this.id,
    required this.status,
    required this.isFounding,
    required this.registrationFee,
    required this.registrationPaid,
    required this.isOnline,
    required this.ratingAvg,
  });

  factory RiderRecord.fromJson(Map<String, dynamic> j) => RiderRecord(
        id: j['id'] as String,
        status: j['status'] as String,
        isFounding: j['is_founding'] as bool? ?? false,
        registrationFee: (j['registration_fee'] as num?)?.toInt() ?? 0,
        registrationPaid: j['registration_paid'] as bool? ?? false,
        isOnline: j['is_online'] as bool? ?? false,
        ratingAvg: (j['rating_avg'] as num?)?.toDouble() ?? 5.0,
      );
}

/// A searching trip the rider can accept.
class AvailableTrip {
  final String id;
  final String vehicleClass;
  final String? pickupAddress;
  final String? dropoffAddress;
  final int fare;
  final double distanceKm;
  final double durationMin;
  final double? pickupDistanceKm;
  final String? errandType;
  final String? errandDescription;

  const AvailableTrip({
    required this.id,
    required this.vehicleClass,
    required this.pickupAddress,
    required this.dropoffAddress,
    required this.fare,
    required this.distanceKm,
    required this.durationMin,
    required this.pickupDistanceKm,
    this.errandType,
    this.errandDescription,
  });

  bool get isErrand => vehicleClass == 'errands';

  factory AvailableTrip.fromJson(Map<String, dynamic> j) => AvailableTrip(
        id: j['id'] as String,
        vehicleClass: j['vehicle_class'] as String,
        pickupAddress: j['pickup_address'] as String?,
        dropoffAddress: j['dropoff_address'] as String?,
        fare: (j['final_fare'] as num?)?.toInt() ?? (j['base_fare'] as num).toInt(),
        distanceKm: (j['distance_km'] as num?)?.toDouble() ?? 0,
        durationMin: (j['duration_min'] as num?)?.toDouble() ?? 0,
        pickupDistanceKm: (j['pickupDistanceKm'] as num?)?.toDouble(),
        errandType: j['errand_type'] as String?,
        errandDescription: (j['errand_details'] as Map<String, dynamic>?)?['description'] as String?,
      );
}

/// Wallet/earnings snapshot.
class Earnings {
  final int balance;
  final int pending;
  const Earnings({required this.balance, required this.pending});
  factory Earnings.fromJson(Map<String, dynamic> j) => Earnings(
        balance: (j['balance'] as num?)?.toInt() ?? 0,
        pending: (j['pending'] as num?)?.toInt() ?? 0,
      );
}

/// Approved fare-adjustment reasons (must match backend enum).
class AdjustmentReasons {
  static const List<({String value, String label})> all = [
    (value: 'heavy_rain', label: 'Heavy Rain'),
    (value: 'flooding', label: 'Flooding'),
    (value: 'road_closure', label: 'Road Closure'),
    (value: 'accident_ahead', label: 'Accident Ahead'),
    (value: 'traffic_congestion', label: 'Traffic Congestion'),
    (value: 'diversion_route', label: 'Diversion Route'),
    (value: 'security_alert', label: 'Security Alert'),
    (value: 'fuel_cost_surge', label: 'Fuel Cost Surge'),
    (value: 'remote_pickup_area', label: 'Remote Pickup Area'),
    (value: 'public_event_congestion', label: 'Public Event Congestion'),
  ];
}
