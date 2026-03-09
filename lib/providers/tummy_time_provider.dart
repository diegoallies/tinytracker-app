import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/tummy_time.dart';
import '../services/supabase_service.dart';
import '../utils/date_utils.dart';
import 'baby_provider.dart';

final activeTummyTimeProvider = FutureProvider.autoDispose<TummyTime?>((ref) async {
  final baby = ref.watch(selectedBabyProvider);
  if (baby == null) return null;

  final data = await SupabaseService.client
      .from('tummy_times')
      .select()
      .eq('baby_id', baby.id)
      .isFilter('end_time', null)
      .order('start_time', ascending: false)
      .limit(1)
      .maybeSingle();

  if (data == null) return null;
  return TummyTime.fromJson(data);
});

final recentTummyTimesProvider = FutureProvider.autoDispose<List<TummyTime>>((ref) async {
  final baby = ref.watch(selectedBabyProvider);
  if (baby == null) return [];

  final data = await SupabaseService.client
      .from('tummy_times')
      .select()
      .eq('baby_id', baby.id)
      .not('end_time', 'is', null)
      .order('start_time', ascending: false)
      .limit(10);

  return data.map<TummyTime>((json) => TummyTime.fromJson(json)).toList();
});

final todayTummyTimeMinutesProvider = FutureProvider.autoDispose<int>((ref) async {
  final baby = ref.watch(selectedBabyProvider);
  if (baby == null) return 0;

  final data = await SupabaseService.client
      .from('tummy_times')
      .select('duration_minutes')
      .eq('baby_id', baby.id)
      .not('end_time', 'is', null)
      .gte('start_time', AppDateUtils.todayStart.toIso8601String());

  int total = 0;
  for (final t in data) {
    total += (t['duration_minutes'] as int?) ?? 0;
  }
  return total;
});

class TummyTimeActions {
  static Future<TummyTime?> start(String babyId) async {
    final userId = SupabaseService.userId;
    if (userId == null) return null;

    final data = await SupabaseService.client.from('tummy_times').insert({
      'baby_id': babyId,
      'user_id': userId,
      'start_time': DateTime.now().toIso8601String(),
    }).select().single();

    return TummyTime.fromJson(data);
  }

  static Future<void> stop(String tummyTimeId, DateTime startTime) async {
    final now = DateTime.now();
    final duration = now.difference(startTime).inMinutes;

    await SupabaseService.client.from('tummy_times').update({
      'end_time': now.toIso8601String(),
      'duration_minutes': duration,
    }).eq('id', tummyTimeId);
  }

  static Future<void> delete(String id) async {
    await SupabaseService.client.from('tummy_times').delete().eq('id', id);
  }
}
