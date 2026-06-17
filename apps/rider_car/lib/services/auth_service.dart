import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase auth for bike riders.
class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Session? get session => _supabase.auth.currentSession;
  User? get currentUser => _supabase.auth.currentUser;
  bool get isSignedIn => session != null;
  Stream<AuthState> get onAuthChange => _supabase.auth.onAuthStateChange;

  Future<void> signUp({
    required String email,
    required String password,
    required String fullName,
    required String phone,
  }) async {
    await _supabase.auth.signUp(
      email: email,
      password: password,
      data: {'full_name': fullName, 'phone': phone, 'role': 'car_rider'},
    );
  }

  Future<void> signIn({required String email, required String password}) =>
      _supabase.auth.signInWithPassword(email: email, password: password);

  Future<void> signOut() => _supabase.auth.signOut();
}
