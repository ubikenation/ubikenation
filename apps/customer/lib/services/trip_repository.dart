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
    String? errandDescription,
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
    if (errandDescription != null) body['errandDetails'] = {'description': errandDescription};

    final data = await _api.post('/api/trips', body);
    return Trip.fromCreate(data as Map<String, dynamic>);
  }

  /// Schedules a ride/errand for later (Uber/Bolt style). The trip parks in
  /// `scheduled` until its time, then enters matching automatically.
  Future<Trip> scheduleTrip({
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
    required DateTime scheduledFor,
  }) async {
    final body = <String, dynamic>{
      'tripType': tripType,
      'vehicleClass': vehicleClass,
      'pickup': {'lat': pickupLat, 'lng': pickupLng, 'address': pickupAddress},
      'distanceKm': distanceKm,
      'durationMin': durationMin,
      'scheduledFor': scheduledFor.toUtc().toIso8601String(),
      if (dropoffLat != null && dropoffLng != null)
        'dropoff': {'lat': dropoffLat, 'lng': dropoffLng, 'address': dropoffAddress},
    };
    final data = await _api.post('/api/trips/schedule', body);
    return Trip.fromCreate(data as Map<String, dynamic>);
  }

  /// Auto fare estimate for an errand from the listed items/description.
  Future<({int fare, int upfront, int balance, int itemCount})> estimateErrand({
    required String errandType,
    required String description,
    required double distanceKm,
    required double durationMin,
  }) async {
    final d = await _api.post('/api/fare/errand-estimate', {
      'errandType': errandType,
      'description': description,
      'distanceKm': distanceKm,
      'durationMin': durationMin,
    }) as Map<String, dynamic>;
    return (
      fare: (d['fare'] as num).toInt(),
      upfront: (d['upfront'] as num).toInt(),
      balance: (d['balance'] as num).toInt(),
      itemCount: (d['itemCount'] as num?)?.toInt() ?? 1,
    );
  }

  /// The customer's trip history.
  Future<List<Map<String, dynamic>>> myTrips() async {
    final d = await _api.get('/api/trips/mine') as List<dynamic>;
    return d.cast<Map<String, dynamic>>();
  }

  /// Wallet balance + recent ledger entries.
  Future<Map<String, dynamic>> wallet() async => await _api.get('/api/payments/wallet') as Map<String, dynamic>;

  /// Starts a Paystack checkout to top up the wallet.
  Future<({String url, String reference})> initiateTopup(int amount) async {
    final d = await _api.post('/api/payments/initiate', {
      'purpose': 'wallet_topup',
      'amount': amount,
      'callbackUrl': paystackCallbackUrl,
    }) as Map<String, dynamic>;
    return (url: d['authorizationUrl'] as String, reference: d['reference'] as String);
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

  /// Starts a Paystack checkout for the trip's balance 50% (paid at the destination).
  Future<({String url, String reference})> initiateBalance(String tripId, int amount) async {
    final data = await _api.post('/api/payments/initiate', {
      'purpose': 'trip_balance',
      'amount': amount,
      'tripId': tripId,
      'callbackUrl': paystackCallbackUrl,
    });
    final m = data as Map<String, dynamic>;
    return (url: m['authorizationUrl'] as String, reference: m['reference'] as String);
  }

  /// Confirms a payment with the backend (verifies against Paystack).
  Future<void> verifyPayment(String reference) => _api.post('/api/payments/verify/$reference');

  /// Customer passes on the current rider → the system re-searches a different one.
  Future<void> requery(String tripId) => _api.post('/api/trips/$tripId/requery');

  /// Opens a dispute on an active/finished trip (admin then resolves/refunds).
  Future<void> dispute(String tripId, String reason) =>
      _api.post('/api/trips/$tripId/dispute', {'reason': reason});

  /// Pushes the customer's live GPS so the assigned rider can trace them.
  Future<void> pushLocation(String tripId, double lat, double lng) =>
      _api.post('/api/trips/$tripId/customer-location', {'lat': lat, 'lng': lng});

  // ---- Commuter plans (recurring errands) ----
  Future<Map<String, dynamic>> createPlan(Map<String, dynamic> body) async =>
      await _api.post('/api/plans', body) as Map<String, dynamic>;

  Future<List<Map<String, dynamic>>> myPlans() async =>
      (await _api.get('/api/plans/mine') as List<dynamic>).cast<Map<String, dynamic>>();

  Future<void> setPlan(String planId, String action) => _api.post('/api/plans/$planId/$action');

  /// Sentinel URL Paystack redirects to after a successful checkout; the WebView
  /// detects navigation to this host and closes.
  static const String paystackCallbackUrl = 'https://ubike.app/paystack/callback';

  Future<Trip> getTrip(String tripId) async {
    final data = await _api.get('/api/trips/$tripId');
    return Trip.fromRow(data as Map<String, dynamic>);
  }

  /// Live position of the assigned rider (for the tracking map).
  Future<Map<String, dynamic>> riderLocation(String tripId) async =>
      await _api.get('/api/trips/$tripId/rider-location') as Map<String, dynamic>;

  Future<void> cancelTrip(String tripId, {String? reason}) =>
      _api.post('/api/trips/$tripId/cancel', {'reason': reason});

  Future<void> rate(String tripId, int stars, {String? comment}) =>
      _api.post('/api/trips/$tripId/rate', {'stars': stars, 'comment': comment});

  // ---- in-app chat (text only, auto-moderated server-side) ----
  Future<List<Map<String, dynamic>>> chatHistory(String tripId) async =>
      (await _api.get('/api/trips/$tripId/chat') as List<dynamic>).cast<Map<String, dynamic>>();

  /// Sends a message; returns whether it was delivered (false = blocked by moderation).
  Future<({bool delivered, bool blocked, String? reason})> sendChat(String tripId, String body) async {
    final d = await _api.post('/api/trips/$tripId/chat', {'body': body}) as Map<String, dynamic>;
    return (delivered: d['delivered'] == true, blocked: d['blocked'] == true, reason: d['reason'] as String?);
  }
}
