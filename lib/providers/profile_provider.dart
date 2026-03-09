import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/profile.dart';
import '../services/supabase_service.dart';

final profileProvider = FutureProvider.autoDispose<Profile?>((ref) async {
  final userId = SupabaseService.userId;
  if (userId == null) return null;

  final data = await SupabaseService.client
      .from('profiles')
      .select()
      .eq('id', userId)
      .maybeSingle();

  if (data == null) return null;
  return Profile.fromJson(data);
});

class ProfileActions {
  static Future<void> updateProfile({
    String? displayName,
    String? phone,
    String? bio,
    String? avatarUrl,
  }) async {
    final userId = SupabaseService.userId;
    if (userId == null) return;

    final updates = <String, dynamic>{};
    if (displayName != null) updates['display_name'] = displayName;
    if (phone != null) updates['phone'] = phone;
    if (bio != null) updates['bio'] = bio;
    if (avatarUrl != null) updates['avatar_url'] = avatarUrl;

    await SupabaseService.client.from('profiles').update(updates).eq('id', userId);
  }

  static Future<String?> uploadAvatar(File file) async {
    final userId = SupabaseService.userId;
    if (userId == null) return null;

    final ext = file.path.split('.').last;
    final fileName = '${const Uuid().v4()}.$ext';
    final storagePath = '$userId/$fileName';

    await SupabaseService.client.storage.from('avatars').upload(storagePath, file);

    return SupabaseService.client.storage.from('avatars').getPublicUrl(storagePath);
  }
}
