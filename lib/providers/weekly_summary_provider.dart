import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/weekly_summary.dart';
import '../services/supabase_service.dart';
import '../utils/date_utils.dart';
import 'baby_provider.dart';

final weeklySummaryProvider = FutureProvider.autoDispose<WeeklySummary?>((ref) async {
  final baby = ref.watch(selectedBabyProvider);
  if (baby == null) return null;

  final client = SupabaseService.client;
  final thisWeekStart = AppDateUtils.daysAgoStart(7).toIso8601String();
  final lastWeekStart = AppDateUtils.daysAgoStart(14).toIso8601String();

  final results = await Future.wait([
    // This week feeds
    client.from('feedings').select('id').eq('baby_id', baby.id)
        .isFilter('deleted_at', null).gte('logged_at', thisWeekStart),
    // Last week feeds
    client.from('feedings').select('id').eq('baby_id', baby.id)
        .isFilter('deleted_at', null)
        .gte('logged_at', lastWeekStart)
        .lt('logged_at', thisWeekStart),
    // This week diapers
    client.from('diapers').select('id').eq('baby_id', baby.id)
        .isFilter('deleted_at', null).gte('logged_at', thisWeekStart),
    // Last week diapers
    client.from('diapers').select('id').eq('baby_id', baby.id)
        .isFilter('deleted_at', null)
        .gte('logged_at', lastWeekStart)
        .lt('logged_at', thisWeekStart),
    // This week sleep
    client.from('sleeps').select('duration_minutes').eq('baby_id', baby.id)
        .isFilter('deleted_at', null).not('end_time', 'is', null)
        .gte('start_time', thisWeekStart),
    // Last week sleep
    client.from('sleeps').select('duration_minutes').eq('baby_id', baby.id)
        .isFilter('deleted_at', null).not('end_time', 'is', null)
        .gte('start_time', lastWeekStart)
        .lt('start_time', thisWeekStart),
  ]);

  int sumSleepMinutes(List data) {
    int total = 0;
    for (final s in data) {
      total += (s['duration_minutes'] as int?) ?? 0;
    }
    return total;
  }

  return WeeklySummary(
    feedCount: (results[0] as List).length,
    feedCountLastWeek: (results[1] as List).length,
    diaperCount: (results[2] as List).length,
    diaperCountLastWeek: (results[3] as List).length,
    sleepMinutes: sumSleepMinutes(results[4] as List),
    sleepMinutesLastWeek: sumSleepMinutes(results[5] as List),
  );
});
