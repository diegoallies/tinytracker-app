import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/feeding.dart';
import '../services/supabase_service.dart';
import '../utils/date_utils.dart';
import 'baby_provider.dart';

final recentFeedingsProvider = FutureProvider.autoDispose<List<Feeding>>((ref) async {
  final baby = ref.watch(selectedBabyProvider);
  if (baby == null) return [];

  final data = await SupabaseService.client
      .from('feedings')
      .select('*')
      .eq('baby_id', baby.id)
      .order('logged_at', ascending: false)
      .limit(10);

  return data.map<Feeding>((json) => Feeding.fromJson(json)).toList();
});

final todayFeedCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final baby = ref.watch(selectedBabyProvider);
  if (baby == null) return 0;

  final data = await SupabaseService.client
      .from('feedings')
      .select('id')
      .eq('baby_id', baby.id)
      .gte('logged_at', AppDateUtils.todayStart.toIso8601String());

  return data.length;
});

class FeedingActions {
  static Future<void> logFeeding({
    required String babyId,
    required String type,
    int? durationMinutes,
    int? amountMl,
    String? notes,
  }) async {
    final userId = SupabaseService.userId;
    if (userId == null) return;

    await SupabaseService.client.from('feedings').insert({
      'baby_id': babyId,
      'user_id': userId,
      'type': type,
      'duration_minutes': durationMinutes,
      'amount_ml': amountMl,
      'notes': notes?.isNotEmpty == true ? notes : null,
      'logged_at': DateTime.now().toIso8601String(),
    });
  }

  static Future<void> deleteFeeding(String feedingId) async {
    await SupabaseService.client
        .from('feedings')
        .delete()
        .eq('id', feedingId);
  }
}
