import '../models/models.dart';
import 'api_client.dart';

/// Backend operations for the bike rider: registration, online status,
/// trip acceptance, fare adjustment, lifecycle and earnings.
class RiderRepository {
  RiderRepository(this._api);
  final ApiClient _api;

  static const String kind = 'bike';

  Future<FeeQuote> registrationFeeQuote() async {
    final d = await _api.get('/api/riders/registration-fee?kind=$kind');
    return FeeQuote.fromJson(d as Map<String, dynamic>);
  }

  Future<FeeQuote> register() async {
    final d = await _api.post('/api/riders/register', {'kind': kind});
    return FeeQuote.fromJson(d as Map<String, dynamic>);
  }

  Future<void> submitDocuments(Map<String, String> documents) =>
      _api.post('/api/riders/documents', {'kind': kind, 'documents': documents});

  /// Saves detailed personal info (+ optional vehicle) to the database.
  Future<void> submitDetails(Map<String, dynamic> details, Map<String, dynamic>? vehicle) =>
      _api.post('/api/riders/details', {'kind': kind, 'details': details, 'vehicle': vehicle});

  /// Records a KES 0 founding-rider registration (no Paystack charge possible at 0).
  Future<void> confirmFreeRegistration() => _api.post('/api/riders/free-registration', {'kind': kind});

  Future<String> payRegistration(int amount) async {
    final d = await _api.post('/api/payments/initiate', {
      'purpose': 'rider_registration',
      'amount': amount,
    });
    return (d as Map<String, dynamic>)['authorizationUrl'] as String;
  }

  /// Returns the rider record for this account (bike kind), or null if none yet.
  Future<RiderRecord?> myStatus() async {
    final d = await _api.get('/api/riders/me') as List<dynamic>;
    for (final row in d) {
      final m = row as Map<String, dynamic>;
      if (m['kind'] == kind) return RiderRecord.fromJson(m);
    }
    return null;
  }

  Future<void> setOnline(bool online) => _api.post('/api/riders/online', {'isOnline': online});

  Future<void> reportViolation(String kind, {String? tripId}) {
    final body = <String, dynamic>{'kind': kind};
    if (tripId != null) body['tripId'] = tripId;
    return _api.post('/api/riders/violation', body);
  }

  Future<void> pushLocation(double lat, double lng) =>
      _api.post('/api/riders/location', {'lat': lat, 'lng': lng});

  Future<List<AvailableTrip>> availableTrips() async {
    final d = await _api.get('/api/trips/available') as List<dynamic>;
    return d.map((e) => AvailableTrip.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> accept(String tripId) => _api.post('/api/trips/$tripId/accept');

  Future<Map<String, dynamic>> adjustFare(String tripId, int proposedFare, String reason) async =>
      await _api.post('/api/trips/$tripId/adjust', {'proposedFare': proposedFare, 'reason': reason})
          as Map<String, dynamic>;

  Future<void> markArrived(String tripId) => _api.post('/api/trips/$tripId/arrived');
  Future<void> startTrip(String tripId) => _api.post('/api/trips/$tripId/start');
  Future<void> completeTrip(String tripId) => _api.post('/api/trips/$tripId/complete');

  Future<Map<String, dynamic>> trip(String tripId) async =>
      await _api.get('/api/trips/$tripId') as Map<String, dynamic>;

  Future<Earnings> earnings() async {
    final d = await _api.get('/api/payments/wallet') as Map<String, dynamic>;
    return Earnings.fromJson(d['wallet'] as Map<String, dynamic>);
  }
}
