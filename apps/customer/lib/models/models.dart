import 'package:flutter/material.dart';

/// A bookable service category shown on the home screen.
class ServiceCategory {
  final String id; // vehicle_class on the backend
  final String label;
  final String tripType; // bike | car | errands | scheduled
  final int minFare;
  final IconData icon;

  const ServiceCategory({
    required this.id,
    required this.label,
    required this.tripType,
    required this.minFare,
    required this.icon,
  });

  static const List<ServiceCategory> all = [
    ServiceCategory(id: 'standard_bike', label: 'Standard Bike', tripType: 'bike', minFare: 120, icon: Icons.pedal_bike),
    ServiceCategory(id: 'electric_bike', label: 'Electric Bike', tripType: 'bike', minFare: 150, icon: Icons.electric_bike),
    ServiceCategory(id: 'economy', label: 'Economy', tripType: 'car', minFare: 300, icon: Icons.directions_car),
    ServiceCategory(id: 'comfort', label: 'Comfort', tripType: 'car', minFare: 450, icon: Icons.local_taxi),
    ServiceCategory(id: 'suv', label: 'SUV', tripType: 'car', minFare: 600, icon: Icons.airport_shuttle),
    ServiceCategory(id: 'errands', label: 'Errands', tripType: 'errands', minFare: 300, icon: Icons.shopping_bag),
  ];
}

/// Result of a fare estimate from the backend (customer-facing fields only).
class FareQuote {
  final int fare;
  final int upfront;
  final int balance;

  const FareQuote({required this.fare, required this.upfront, required this.balance});

  factory FareQuote.fromJson(Map<String, dynamic> j) => FareQuote(
        fare: (j['fare'] as num).toInt(),
        upfront: (j['upfront'] as num).toInt(),
        balance: (j['balance'] as num).toInt(),
      );
}

/// A created trip and its live status.
class Trip {
  final String id;
  final String status;
  final int fare;
  final int upfront;
  final int balance;

  const Trip({
    required this.id,
    required this.status,
    required this.fare,
    required this.upfront,
    required this.balance,
  });

  factory Trip.fromCreate(Map<String, dynamic> j) => Trip(
        id: j['tripId'] as String,
        status: j['status'] as String? ?? 'pending_payment',
        fare: (j['fare'] as num).toInt(),
        upfront: (j['upfront'] as num).toInt(),
        balance: (j['balance'] as num).toInt(),
      );

  factory Trip.fromRow(Map<String, dynamic> j) => Trip(
        id: j['id'] as String,
        status: j['status'] as String,
        fare: (j['final_fare'] as num?)?.toInt() ?? (j['base_fare'] as num).toInt(),
        upfront: (j['upfront_amount'] as num?)?.toInt() ?? 0,
        balance: (j['balance_amount'] as num?)?.toInt() ?? 0,
      );
}
