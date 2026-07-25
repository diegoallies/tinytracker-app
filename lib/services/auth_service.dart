import 'package:supabase_flutter/supabase_flutter.dart';
import 'analytics_service.dart';
import 'supabase_service.dart';

class AuthService {
  final _client = SupabaseService.client;

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    final response = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    // Analytics is instrumented here rather than in the screens so the watch
    // bridge, deep links and the auth screens all report identically.
    await AnalyticsService.setUser(response.user?.id);
    await AnalyticsService.logLogin();
    return response;
  }

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final response = await _client.auth.signUp(
      email: email,
      password: password,
      data: displayName != null ? {'display_name': displayName} : null,
    );
    await AnalyticsService.setUser(response.user?.id);
    await AnalyticsService.logSignUp();
    return response;
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
    // Stop attributing subsequent events to the user who just left.
    await AnalyticsService.setUser(null);
  }

  /// Permanently deletes the signed-in user's account and all their data via
  /// the `delete_own_account` Postgres function (required by App Store
  /// guideline 5.1.1(v)).
  Future<void> deleteAccount() async {
    await _client.rpc('delete_own_account');
    try {
      await _client.auth.signOut();
    } catch (_) {
      // The server session is already gone once the auth user is deleted;
      // ignore the failed remote sign-out and rely on local cleanup.
    }
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
