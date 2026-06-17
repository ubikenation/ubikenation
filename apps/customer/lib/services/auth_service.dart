import 'package:supabase_flutter/supabase_flutter.dart';

/// Wraps Supabase Auth for email/password sign-up, sign-in and password reset.
class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Session? get session => _supabase.auth.currentSession;
  User? get currentUser => _supabase.auth.currentUser;
  bool get isSignedIn => session != null;

  Stream<AuthState> get onAuthChange => _supabase.auth.onAuthStateChange;

  /// Returns the AuthResponse. If `session` is null, email confirmation is
  /// required before the user can log in.
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String fullName,
    required String phone,
  }) {
    return _supabase.auth.signUp(
      email: email,
      password: password,
      data: {'full_name': fullName, 'phone': phone, 'role': 'customer'},
    );
  }

  Future<void> signIn({required String email, required String password}) async {
    await _supabase.auth.signInWithPassword(email: email, password: password);
  }

  /// Sends a password-reset email.
  Future<void> resetPassword(String email) => _supabase.auth.resetPasswordForEmail(email);

  Future<void> signOut() => _supabase.auth.signOut();
}
