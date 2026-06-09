import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/sleep_session.dart';
import '../services/supabase_service.dart';
import '../utils/date_utils.dart';
import 'baby_provider.dart';

final activeSleepProvider = FutureProvider<SleepSession?>((ref) async {
  final baby = ref.watch(selectedBabyProvider);
  if (baby == null) return null;

  final data = await SupabaseService.client
      .from('sleeps')
      .select()
      .eq('baby_id', baby.id)
      .isFilter('end_time', null)
      .order('start_time', ascending: false)
      .limit(1)
      .maybeSingle();

  if (data == null) return null;
  return SleepSession.fromJson(data);
});

final recentSleepsProvider = FutureProvider<List<SleepSession>>((ref) async {
  final baby = ref.watch(selectedBabyProvider);
  if (baby == null) return [];

  final data = await SupabaseService.client
      .from('sleeps')
      .select('*')
      .eq('baby_id', baby.id)
      .not('end_time', 'is', null)
      .order('start_time', ascending: false)
      .limit(10);

  return data.map<SleepSession>((json) => SleepSession.fromJson(json)).toList();
});

final todaySleepMinutesProvider = FutureProvider<int>((ref) async {
  final baby = ref.watch(selectedBabyProvider);
  if (baby == null) return 0;

  final data = await SupabaseService.client
      .from('sleeps')
      .select('duration_minutes')
      .eq('baby_id', baby.id)
      .not('end_time', 'is', null)
      .gte('start_time', AppDateUtils.todayStart.toUtc().toIso8601String());

  int total = 0;
  for (final s in data) {
    total += (s['duration_minutes'] as int?) ?? 0;
  }
  return total;
});

class SleepActions {
  static Future<SleepSession?> startSleep(String babyId) async {
    final userId = SupabaseService.userId;
    if (userId == null) return null;

    final data = await SupabaseService.client.from('sleeps').insert({
      'baby_id': babyId,
      'user_id': userId,
      'start_time': DateTime.now().toUtc().toIso8601String(),
    }).select().single();

    return SleepSession.fromJson(data);
  }

  static Future<void> stopSleep(String sleepId, DateTime startTime) async {
    final now = DateTime.now();
    final duration = now.difference(startTime).inMinutes;

    await SupabaseService.client.from('sleeps').update({
      'end_time': now.toUtc().toIso8601String(),
      'duration_minutes': duration,
    }).eq('id', sleepId);
  }

  static Future<void> deleteSleep(String sleepId) async {
    await SupabaseService.client
        .from('sleeps')
        .delete()
        .eq('id', sleepId);
  }
}
