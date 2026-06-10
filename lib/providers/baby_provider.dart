import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
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

  bool get canLog => role == 'owner' || role == 'logger' || role == 'parent';
  bool get isOwner => role == 'owner';
  bool get isViewer => role == 'viewer';
  bool get canLogMeds => role == 'owner' || role == 'parent';

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

    if (!mounted) return;
    state = state.copyWith(loading: true);

    try {
      // Get babies through baby_shares
      final sharesData = await _client
          .from('baby_shares')
          .select('*, babies(*)')
          .eq('user_id', userId)
          // Soft-deleted babies come back as a null embed and are skipped below.
          .isFilter('babies.deleted_at', null);

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

      if (!mounted) return;
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
      if (!mounted) return;
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

    final rows = await _client
        .from('babies')
        .update(updates)
        .eq('id', babyId)
        .select();

    if (rows.isEmpty) {
      throw StateError(
        'Update returned no rows — check RLS on babies table for user ${SupabaseService.userId}',
      );
    }

    final updated = Baby.fromJson(rows.first);

    if (photoUrl != null && updated.photoUrl != photoUrl) {
      throw StateError(
        'photo_url did not persist — column may be missing or blocked by RLS',
      );
    }

    if (!mounted) return;

    // Optimistically apply the saved row so UI flips immediately, without
    // waiting for the full loadBabies() round-trip.
    final newBabies = state.babies
        .map((b) => b.id == updated.id ? updated : b)
        .toList();
    state = state.copyWith(
      babies: newBabies,
      selectedBaby: state.selectedBaby?.id == updated.id
          ? updated
          : state.selectedBaby,
    );

    // Background refresh so anything else (role, new babies) stays in sync.
    await loadBabies();
  }

  Future<List<BabyShare>> getShares(String babyId) async {
    // Get shares first
    final sharesData = await _client
        .from('baby_shares')
        .select('*')
        .eq('baby_id', babyId);

    // Get unique user IDs
    final userIds = sharesData
        .map<String>((s) => s['user_id'] as String)
        .toSet()
        .toList();

    // Fetch profiles for those users
    final profilesData = userIds.isNotEmpty
        ? await _client
            .from('profiles')
            .select('id, display_name, email')
            .inFilter('id', userIds)
        : [];

    // Build a map for quick lookup
    final profilesMap = <String, Map<String, dynamic>>{};
    for (final p in profilesData) {
      profilesMap[p['id'] as String] = p;
    }

    // Merge profile data into shares
    return sharesData.map<BabyShare>((json) {
      final userId = json['user_id'] as String;
      final profile = profilesMap[userId];
      return BabyShare.fromJson({
        ...json,
        'profiles': profile,
      });
    }).toList();
  }

  Future<void> removeShare(String shareId) async {
    await _client.from('baby_shares').delete().eq('id', shareId);
  }

  Future<void> updateShareRole(String shareId, String role) async {
    final rows = await _client
        .from('baby_shares')
        .update({'role': role})
        .eq('id', shareId)
        .select();

    if (rows.isEmpty) {
      throw StateError(
        'Role update returned no rows — only owners can change roles',
      );
    }
  }
}

class BabyActions {
  static Future<String?> uploadPhoto(File file) async {
    final userId = SupabaseService.userId;
    if (userId == null) return null;

    final ext = file.path.split('.').last;
    final fileName = 'baby_${const Uuid().v4()}.$ext';
    final storagePath = '$userId/$fileName';

    await SupabaseService.client.storage.from('avatars').upload(storagePath, file);

    return SupabaseService.client.storage.from('avatars').getPublicUrl(storagePath);
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
