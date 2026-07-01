import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'api_client.dart';

/// Handles FCM: registers the device token, shows an in-app banner when a push
/// arrives in the foreground (Android only auto-shows them in the background), and
/// routes a notification tap to the right screen via [onOpen].
class PushService {
  PushService(this._api, {this.messengerKey, this.onOpen});
  final ApiClient _api;
  final GlobalKey<ScaffoldMessengerState>? messengerKey;
  final void Function(Map<String, dynamic> data)? onOpen;
  final _fm = FirebaseMessaging.instance;

  /// Requests permission and wires foreground display + tap routing. Call once.
  Future<void> init() async {
    try {
      await _fm.requestPermission();
      _fm.onTokenRefresh.listen(_send);
      FirebaseMessaging.onMessage.listen(_showForeground);
      FirebaseMessaging.onMessageOpenedApp.listen((m) => onOpen?.call(m.data));
      // App opened from a terminated state by tapping a notification.
      final initial = await _fm.getInitialMessage();
      if (initial != null) onOpen?.call(initial.data);
    } catch (_) {/* push is best-effort */}
  }

  /// Fetches the current token and registers it (call after sign-in).
  Future<void> registerToken() async {
    try {
      final token = await _fm.getToken();
      if (token != null) await _send(token);
    } catch (_) {/* ignore */}
  }

  void _showForeground(RemoteMessage m) {
    // An incoming call in the foreground should ring immediately, not sit in a
    // passive banner — jump straight to the call screen.
    if (m.data['type'] == 'incoming_call') {
      onOpen?.call(m.data);
      return;
    }
    final n = m.notification;
    final messenger = messengerKey?.currentState;
    if (n == null || messenger == null) return;
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (n.title != null) Text(n.title!, style: const TextStyle(fontWeight: FontWeight.bold)),
            if (n.body != null) Text(n.body!),
          ],
        ),
        action: onOpen != null && m.data.isNotEmpty
            ? SnackBarAction(label: 'View', onPressed: () => onOpen!.call(m.data))
            : null,
      ),
    );
  }

  Future<void> _send(String token) async {
    try {
      await _api.post('/api/devices/register', {'token': token, 'platform': 'android'});
    } catch (_) {/* not signed in yet / offline — will retry on next call */}
  }
}
