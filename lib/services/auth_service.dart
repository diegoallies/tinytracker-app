import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

class AuthService {
  final _client = SupabaseService.client;

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {
    return await _client.auth.signUp(
      email: email,
      password: password,
      data: displayName != null ? {'display_name': displayName} : null,
    );
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  Future<bool> resetPassword(String email) async {
    try {
      // Deep-link back into the app (NOT the old website) - handled by
      // supabase_flutter, which emits AuthChangeEvent.passwordRecovery.
      await _client.auth.resetPasswordForEmail(
        email,
        redirectTo: 'tinytracker://reset-password',
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Resends the signup confirmation email for accounts that registered but
  /// never clicked the verify link.
  Future<bool> resendConfirmation(String email) async {
    try {
      await _client.auth.resend(
        type: OtpType.signup,
        email: email,
        emailRedirectTo: 'tinytracker://login',
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  User? get currentUser => _client.auth.currentUser;
  String? get userId => currentUser?.id;
  bool get isAuthenticated => currentUser != null;
}
