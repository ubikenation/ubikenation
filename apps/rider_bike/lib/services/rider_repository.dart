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

  /// Paystack callback sentinel the WebView watches for to detect success.
  static const String paystackCallbackUrl = 'https://ubike.app/paystack/callback';

  Future<({String url, String reference})> payRegistration(int amount) async {
    final d = await _api.post('/api/payments/initiate', {
      'purpose': 'rider_registration',
      'amount': amount,
      'callbackUrl': paystackCallbackUrl,
    }) as Map<String, dynamic>;
    return (url: d['authorizationUrl'] as String, reference: d['reference'] as String);
  }

  /// Confirms a Paystack payment with the backend (verifies + settles it).
  Future<void> verifyPayment(String reference) => _api.post('/api/payments/verify/$reference');

  /// Returns the rider record for this account (matching this app's kind), or null if
  /// none yet. Retries once — right after sign-in the auth token can lag a beat, which
  /// would otherwise look like "no record" and wrongly send a verified rider to register.
  Future<RiderRecord?> myStatus() async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final d = await _api.get('/api/riders/me') as List<dynamic>;
      for (final row in d) {
        final m = row as Map<String, dynamic>;
        if (m['kind'] == kind) return RiderRecord.fromJson(m);
      }
      if (attempt == 0) await Future<void>.delayed(const Duration(milliseconds: 700));
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

  /// Opens a dispute on an active/finished trip (admin reviews and resolves).
  Future<void> dispute(String tripId, String reason) =>
      _api.post('/api/trips/$tripId/dispute', {'reason': reason});

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
