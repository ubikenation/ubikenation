import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Keeps users signed in across app restarts (Supabase persists the login token),
/// but FORCES a fresh sign-in when the app hasn't been opened for 48h. The
/// "last seen" time is stored in Supabase (profiles.last_seen_at) — NO local
/// database is used. Also flags a friendly "welcome back" greeting on return.
class SessionGuard {
  SessionGuard._();

  static const Duration maxIdle = Duration(hours: 48); // > this ⇒ must sign in again
  static const Duration welcomeAfter = Duration(hours: 1); // away > this ⇒ greet them

  static SupabaseClient get _c => Supabase.instance.client;

  /// Reads the previous last_seen from Supabase, signs out if idle ≥ 48h, then
  /// stamps last_seen = now. Returns true if we should greet with "welcome back".
  /// Fails open (keeps the session) if offline / on any error.
  static Future<bool> evaluate() async {
    final uid = _c.auth.currentUser?.id;
    if (uid == null) return false; // not signed in — nothing to do
    final now = DateTime.now().toUtc();

    DateTime? prev;
    try {
      final row = await _c.from('profiles').select('last_seen_at').eq('id', uid).maybeSingle();
      final ls = row?['last_seen_at'] as String?;
      if (ls != null) prev = DateTime.tryParse(ls)?.toUtc();
    } catch (_) {
      return false; // offline / error → don't disturb the session
    }

    if (prev != null) {
      final away = now.difference(prev);
      if (away >= maxIdle) {
        await _c.auth.signOut(); // idle too long → require a fresh sign-in
        return false;
      }
      if (away >= welcomeAfter) {
        await markSeen();
        return true;
      }
    }
    await markSeen();
    return false;
  }

  /// Stamps profiles.last_seen_at = now (best-effort). Call on sign-in so the next
  /// launch after a forced re-login starts fresh.
  static Future<void> markSeen() async {
    final uid = _c.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await _c.from('profiles').update({'last_seen_at': DateTime.now().toUtc().toIso8601String()}).eq('id', uid);
    } catch (_) {/* best-effort */}
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
