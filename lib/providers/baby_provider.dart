import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/baby.dart';
import '../models/baby_share.dart';
import '../services/supabase_service.dart';
import 'auth_provider.dart';

class BabyState {
  final Baby? selectedBaby;
  final List<Baby> babies;
  final String? role;
  final bool loading;

  BabyState({
    this.selectedBaby,
    this.babies = const [],
    this.role,
    this.loading = true,
  });

  bool get canLog => role == 'owner' || role == 'logger';
  bool get isOwner => role == 'owner';
  bool get isViewer => role == 'viewer';

  BabyState copyWith({
    Baby? selectedBaby,
    List<Baby>? babies,
    String? role,
    bool? loading,
  }) {
    return BabyState(
      selectedBaby: selectedBaby ?? this.selectedBaby,
      babies: babies ?? this.babies,
      role: role ?? this.role,
      loading: loading ?? this.loading,
    );
  }
}

class BabyNotifier extends StateNotifier<BabyState> {
  BabyNotifier() : super(BabyState()) {
    loadBabies();
  }

  final _client = SupabaseService.client;

  Future<void> loadBabies() async {
    final userId = SupabaseService.userId;
    if (userId == null) return;

    state = state.copyWith(loading: true);

    try {
      // Get babies through baby_shares
      final sharesData = await _client
          .from('baby_shares')
          .select('*, babies(*)')
          .eq('user_id', userId);

      final babies = <Baby>[];
      String? role;

      for (final share in sharesData) {
        if (share['babies'] != null) {
          babies.add(Baby.fromJson(share['babies'] as Map<String, dynamic>));
          if (state.selectedBaby == null ||
              (state.selectedBaby != null &&
                  share['babies']['id'] == state.selectedBaby!.id)) {
            role = share['role'] as String?;
          }
        }
      }

      state = state.copyWith(
        babies: babies,
        selectedBaby: babies.isNotEmpty
            ? (state.selectedBaby != null &&
                    babies.any((b) => b.id == state.selectedBaby!.id)
                ? babies.firstWhere((b) => b.id == state.selectedBaby!.id)
                : babies.first)
            : null,
        role: role,
        loading: false,
      );
    } catch (e) {
      state = state.copyWith(loading: false);
    }
  }

  void selectBaby(Baby baby) async {
    final userId = SupabaseService.userId;
    if (userId == null) return;

    final shareData = await _client
        .from('baby_shares')
        .select('role')
        .eq('user_id', userId)
        .eq('baby_id', baby.id)
        .maybeSingle();

    state = state.copyWith(
      selectedBaby: baby,
      role: shareData?['role'] as String?,
    );
  }

  Future<Baby?> createBaby({
    required String name,
    required DateTime dateOfBirth,
    String? gender,
  }) async {
    final userId = SupabaseService.userId;
    if (userId == null) return null;

    final data = await _client.from('babies').insert({
      'user_id': userId,
      'owner_id': userId,
      'name': name,
      'date_of_birth': dateOfBirth.toIso8601String().split('T')[0],
      'gender': gender,
    }).select().single();

    final baby = Baby.fromJson(data);

    // Create owner share
    await _client.from('baby_shares').insert({
      'baby_id': baby.id,
      'user_id': userId,
      'role': 'owner',
    });

    await loadBabies();
    return baby;
  }

  Future<void> updateBaby({
    required String babyId,
    String? name,
    DateTime? dateOfBirth,
    String? gender,
    String? photoUrl,
  }) async {
    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
    if (dateOfBirth != null) updates['date_of_birth'] = dateOfBirth.toIso8601String().split('T')[0];
    if (gender != null) updates['gender'] = gender;
    if (photoUrl != null) updates['photo_url'] = photoUrl;

    await _client.from('babies').update(updates).eq('id', babyId);
    await loadBabies();
  }

  Future<List<BabyShare>> getShares(String babyId) async {
    final data = await _client
        .from('baby_shares')
        .select('*, profiles(display_name, email)')
        .eq('baby_id', babyId);

    return data.map<BabyShare>((json) => BabyShare.fromJson(json)).toList();
  }

  Future<void> removeShare(String shareId) async {
    await _client.from('baby_shares').delete().eq('id', shareId);
  }
}

final babyProvider = StateNotifierProvider<BabyNotifier, BabyState>((ref) {
  // Watch auth state so babies reload when user logs in/session restores
  ref.watch(authStateProvider);
  return BabyNotifier();
});

final selectedBabyProvider = Provider<Baby?>((ref) {
  return ref.watch(babyProvider).selectedBaby;
});

final canLogProvider = Provider<bool>((ref) {
  return ref.watch(babyProvider).canLog;
});
