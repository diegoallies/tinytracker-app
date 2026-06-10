import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/growth.dart';
import '../services/supabase_service.dart';
import 'baby_provider.dart';

final growthEntriesProvider = FutureProvider.autoDispose<List<Growth>>((ref) async {
  final baby = ref.watch(selectedBabyProvider);
  if (baby == null) return [];

  final data = await SupabaseService.client
      .from('growth')
      .select()
      .eq('baby_id', baby.id)
      .isFilter('deleted_at', null)
      .order('measured_at', ascending: true);

  return data.map<Growth>((json) => Growth.fromJson(json)).toList();
});

class GrowthActions {
  static Future<void> logGrowth({
    required String babyId,
    double? weightKg,
    double? heightCm,
    double? headCm,
    String? notes,
  }) async {
    final userId = SupabaseService.userId;
    if (userId == null) return;

    await SupabaseService.client.from('growth').insert({
      'baby_id': babyId,
      'user_id': userId,
      'weight_kg': weightKg,
      'height_cm': heightCm,
      'head_cm': headCm,
      'notes': notes?.isNotEmpty == true ? notes : null,
      'measured_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  static Future<void> deleteGrowth(String growthId) async {
    await SupabaseService.client.from('growth').update({
      'deleted_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', growthId);
  }
}
