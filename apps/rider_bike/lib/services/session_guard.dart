import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Keeps users signed in across app restarts (Supabase persists the session), but
/// FORCES a fresh sign-in when the app hasn't been opened for 48h. Also flags a
/// friendly "welcome back" greeting when they return after being away a while.
class SessionGuard {
  SessionGuard._();

  static const _kLastOpened = 'last_opened_ms';
  static const Duration maxIdle = Duration(hours: 48); // > this ⇒ must sign in again
  static const Duration welcomeAfter = Duration(hours: 1); // away > this ⇒ greet them

  /// Evaluates idle time: signs out if idle ≥ 48h, then records "now" as the last
  /// open. Returns true if we should show the "welcome back" popup.
  static Future<bool> evaluate() async {
    final prefs = await SharedPreferences.getInstance();
    final lastMs = prefs.getInt(_kLastOpened);
    final now = DateTime.now();
    final signedIn = Supabase.instance.client.auth.currentSession != null;

    var welcome = false;
    if (signedIn && lastMs != null) {
      final away = now.difference(DateTime.fromMillisecondsSinceEpoch(lastMs));
      if (away >= maxIdle) {
        // Too long away — require a fresh sign-in.
        await Supabase.instance.client.auth.signOut();
      } else if (away >= welcomeAfter) {
        welcome = true;
      }
    }
    await prefs.setInt(_kLastOpened, now.millisecondsSinceEpoch);
    return welcome;
  }

  /// Shows the 10-second "welcome back" greeting via the app-wide messenger.
  static void showWelcome(GlobalKey<ScaffoldMessengerState> key) {
    final messenger = key.currentState;
    if (messenger == null) return;
    messenger.showSnackBar(const SnackBar(
      duration: Duration(seconds: 10),
      behavior: SnackBarBehavior.floating,
      backgroundColor: Color(0xFF12A0D7),
      content: Text(
        '👋 Welcome back — we missed you!',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ));
  }
}
