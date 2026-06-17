import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase auth for riders (sign-up, sign-in, password reset).
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
      data: {'full_name': fullName, 'phone': phone, 'role': 'errands_rider'},
    );
  }

  Future<void> signIn({required String email, required String password}) =>
      _supabase.auth.signInWithPassword(email: email, password: password);

  Future<void> resetPassword(String email) => _supabase.auth.resetPasswordForEmail(email);

  Future<void> signOut() => _supabase.auth.signOut();
}
