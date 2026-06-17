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
  /// Returns the checkout URL + reference so the WebView can verify on completion.
  Future<({String url, String reference})> initiateUpfront(String tripId, int amount) async {
    final data = await _api.post('/api/payments/initiate', {
      'purpose': 'trip_upfront',
      'amount': amount,
      'tripId': tripId,
      'callbackUrl': paystackCallbackUrl,
    });
    final m = data as Map<String, dynamic>;
    return (url: m['authorizationUrl'] as String, reference: m['reference'] as String);
  }

  /// Confirms a payment with the backend (verifies against Paystack).
  Future<void> verifyPayment(String reference) => _api.post('/api/payments/verify/$reference');

  /// Sentinel URL Paystack redirects to after a successful checkout; the WebView
  /// detects navigation to this host and closes.
  static const String paystackCallbackUrl = 'https://ubike.app/paystack/callback';

  Future<Trip> getTrip(String tripId) async {
    final data = await _api.get('/api/trips/$tripId');
    return Trip.fromRow(data as Map<String, dynamic>);
  }

  Future<void> cancelTrip(String tripId, {String? reason}) =>
      _api.post('/api/trips/$tripId/cancel', {'reason': reason});

  Future<void> rate(String tripId, int stars, {String? comment}) =>
      _api.post('/api/trips/$tripId/rate', {'stars': stars, 'comment': comment});
}
