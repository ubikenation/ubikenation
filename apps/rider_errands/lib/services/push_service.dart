import 'package:firebase_messaging/firebase_messaging.dart';

import 'api_client.dart';

/// Registers this device's FCM token with the backend so the customer can be
/// pushed when a rider is found / arriving. Safe to call repeatedly.
class PushService {
  PushService(this._api);
  final ApiClient _api;
  final _fm = FirebaseMessaging.instance;

  /// Requests permission and wires token-refresh. Call once at startup.
  Future<void> init() async {
    try {
      await _fm.requestPermission();
      _fm.onTokenRefresh.listen(_send);
    } catch (_) {/* push is best-effort */}
  }

  /// Fetches the current token and registers it (call after sign-in).
  Future<void> registerToken() async {
    try {
      final token = await _fm.getToken();
      if (token != null) await _send(token);
    } catch (_) {/* ignore */}
  }

  Future<void> _send(String token) async {
    try {
      await _api.post('/api/devices/register', {'token': token, 'platform': 'android'});
    } catch (_) {/* not signed in yet / offline — will retry on next call */}
  }
}
