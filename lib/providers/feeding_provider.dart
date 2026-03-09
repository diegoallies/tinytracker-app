import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/feeding.dart';
import '../services/supabase_service.dart';
import '../services/notification_service.dart';
import '../utils/date_utils.dart';
import 'baby_provider.dart';

final recentFeedingsProvider = FutureProvider.autoDispose<List<Feeding>>((ref) async {
  final baby = ref.watch(selectedBabyProvider);
  if (baby == null) return [];

  try {
    final data = await SupabaseService.client
        .from('feedings')
        .select('*')
        .eq('baby_id', baby.id)
        .order('logged_at', ascending: false)
        .limit(10);

    return data
        .where((json) => json['deleted_at'] == null)
        .map<Feeding>((json) => Feeding.fromJson(json))
        .toList();
  } catch (e, st) {
    debugPrint('recentFeedingsProvider error: $e\n$st');
    rethrow;
  }
});

final todayFeedCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final baby = ref.watch(selectedBabyProvider);
  if (baby == null) return 0;

  final data = await SupabaseService.client
      .from('feedings')
      .select('id, deleted_at')
      .eq('baby_id', baby.id)
      .gte('logged_at', AppDateUtils.todayStart.toIso8601String());

  return data.where((r) => r['deleted_at'] == null).length;
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

    final now = DateTime.now();
    await SupabaseService.client.from('feedings').insert({
      'baby_id': babyId,
      'user_id': userId,
      'type': type,
      'duration_minutes': durationMinutes,
      'amount_ml': amountMl,
      'notes': notes?.isNotEmpty == true ? notes : null,
      'logged_at': now.toIso8601String(),
    });

    // Reschedule feeding reminder
    final interval = await NotificationService.getReminderInterval();
    await NotificationService.scheduleFeedingReminder(
      lastFeedTime: now,
      intervalMinutes: interval,
    );
  }

  static Future<void> deleteFeeding(String feedingId) async {
    await SupabaseService.client
        .from('feedings')
        .update({'deleted_at': DateTime.now().toIso8601String()})
        .eq('id', feedingId);
  }
}
