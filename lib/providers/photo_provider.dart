import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/photo.dart';
import '../services/supabase_service.dart';
import 'baby_provider.dart';

final photosProvider = FutureProvider.autoDispose<List<Photo>>((ref) async {
  final baby = ref.watch(selectedBabyProvider);
  if (baby == null) return [];

  final data = await SupabaseService.client
      .from('photos')
      .select()
      .eq('baby_id', baby.id)
      .order('taken_at', ascending: false);

  return data.map<Photo>((json) => Photo.fromJson(json)).toList();
});

class PhotoActions {
  static Future<Photo?> uploadPhoto({
    required String babyId,
    required File file,
    String? caption,
  }) async {
    final userId = SupabaseService.userId;
    if (userId == null) return null;

    final ext = file.path.split('.').last;
    final fileName = '${const Uuid().v4()}.$ext';
    final storagePath = '$userId/$babyId/$fileName';

    // Upload to storage
    await SupabaseService.client.storage
        .from('photos')
        .upload(storagePath, file);

    final url = SupabaseService.client.storage
        .from('photos')
        .getPublicUrl(storagePath);

    // Insert record
    final data = await SupabaseService.client.from('photos').insert({
      'baby_id': babyId,
      'user_id': userId,
      'url': url,
      'caption': caption?.isNotEmpty == true ? caption : null,
      'taken_at': DateTime.now().toIso8601String(),
    }).select().single();

    return Photo.fromJson(data);
  }

  static Future<void> deletePhoto(Photo photo) async {
    // Soft delete
    await SupabaseService.client
        .from('photos')
        .delete()
        .eq('id', photo.id);

    // Try to remove from storage
    try {
      final uri = Uri.parse(photo.url);
      final pathSegments = uri.pathSegments;
      final storageIndex = pathSegments.indexOf('photos');
      if (storageIndex >= 0 && storageIndex < pathSegments.length - 1) {
        final storagePath = pathSegments.sublist(storageIndex + 1).join('/');
        await SupabaseService.client.storage.from('photos').remove([storagePath]);
      }
    } catch (_) {}
  }
}
