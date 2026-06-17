import '../models/models.dart';
import 'api_client.dart';

/// Backend operations for fares, trips and payments.
class TripRepository {
  TripRepository(this._api);
  final ApiClient _api;

  Future<FareQuote> estimateFare({
    required String vehicleClass,
    required double distanceKm,
    required double durationMin,
  }) async {
    final data = await _api.post('/api/fare/estimate', {
      'vehicleClass': vehicleClass,
      'distanceKm': distanceKm,
      'durationMin': durationMin,
    });
    return FareQuote.fromJson(data as Map<String, dynamic>);
  }

  Future<Trip> createTrip({
    required String tripType,
    required String vehicleClass,
    required double pickupLat,
    required double pickupLng,
    String? pickupAddress,
    double? dropoffLat,
    double? dropoffLng,
    String? dropoffAddress,
    required double distanceKm,
    required double durationMin,
    String? errandType,
  }) async {
    final body = <String, dynamic>{
      'tripType': tripType,
      'vehicleClass': vehicleClass,
      'pickup': {'lat': pickupLat, 'lng': pickupLng, 'address': pickupAddress},
      'distanceKm': distanceKm,
      'durationMin': durationMin,
    };
    if (dropoffLat != null && dropoffLng != null) {
      body['dropoff'] = {'lat': dropoffLat, 'lng': dropoffLng, 'address': dropoffAddress};
    }
    if (errandType != null) body['errandType'] = errandType;

    final data = await _api.post('/api/trips', body);
    return Trip.fromCreate(data as Map<String, dynamic>);
  }

  /// Starts a Paystack checkout for the trip's upfront 50%.
  Future<String> initiateUpfront(String tripId, int amount) async {
    final data = await _api.post('/api/payments/initiate', {
      'purpose': 'trip_upfront',
      'amount': amount,
      'tripId': tripId,
    });
    return (data as Map<String, dynamic>)['authorizationUrl'] as String;
  }

  Future<Trip> getTrip(String tripId) async {
    final data = await _api.get('/api/trips/$tripId');
    return Trip.fromRow(data as Map<String, dynamic>);
  }

  Future<void> cancelTrip(String tripId, {String? reason}) =>
      _api.post('/api/trips/$tripId/cancel', {'reason': reason});

  Future<void> rate(String tripId, int stars, {String? comment}) =>
      _api.post('/api/trips/$tripId/rate', {'stars': stars, 'comment': comment});
}
