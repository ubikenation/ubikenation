import '../models/models.dart';
import 'api_client.dart';

/// Backend operations for the bike rider: registration, online status,
/// trip acceptance, fare adjustment, lifecycle and earnings.
class RiderRepository {
  RiderRepository(this._api);
  final ApiClient _api;

  static const String kind = 'car';

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

  Future<void> submitDetails(Map<String, dynamic> details, Map<String, dynamic>? vehicle) =>
      _api.post('/api/riders/details', {'kind': kind, 'details': details, 'vehicle': vehicle});

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

  /// Rider passes on a request → it's hidden from them and offered to others.
  Future<void> decline(String tripId) => _api.post('/api/trips/$tripId/decline');

  /// Confirms the price after accepting: pass no [proposedFare] to take the auto
  /// fare (company keeps 20%), or a higher one to adjust up to +30% (company keeps 25%).
  Future<Map<String, dynamic>> quote(String tripId, {int? proposedFare}) async =>
      await _api.post('/api/trips/$tripId/quote',
              proposedFare != null ? {'proposedFare': proposedFare} : <String, dynamic>{})
          as Map<String, dynamic>;

  /// The customer's live location + pickup/destination, to trace them on the map.
  Future<Map<String, dynamic>> customerLocation(String tripId) async =>
      await _api.get('/api/trips/$tripId/customer-location') as Map<String, dynamic>;

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
