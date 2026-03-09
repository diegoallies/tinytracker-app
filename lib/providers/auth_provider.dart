import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';

final authStateProvider = StreamProvider<AuthState>((ref) {
  return SupabaseService.authStateChanges;
});

final currentUserProvider = Provider<User?>((ref) {
  // Watch auth stream so this re-evaluates when auth state changes
  ref.watch(authStateProvider);
  return SupabaseService.currentUser;
});

final isAuthenticatedProvider = Provider<bool>((ref) {
  // Depend on reactive currentUserProvider instead of static check
  return ref.watch(currentUserProvider) != null;
});
