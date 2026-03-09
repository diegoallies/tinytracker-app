import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/supabase_service.dart';
import '../utils/date_utils.dart';
import 'baby_provider.dart';

class DashboardStats {
  final int feedCount;
  final int diaperCount;
  final int sleepMinutes;
  final DateTime? lastFeedTime;
  final String? lastFeedType;
  final DateTime? lastDiaperTime;
  final String? lastDiaperType;
  final bool isSleeping;
  final DateTime? sleepStartTime;
  final String? sleepId;
  final String? latestPhotoUrl;

  DashboardStats({
    this.feedCount = 0,
    this.diaperCount = 0,
    this.sleepMinutes = 0,
    this.lastFeedTime,
    this.lastFeedType,
    this.lastDiaperTime,
    this.lastDiaperType,
    this.isSleeping = false,
    this.sleepStartTime,
    this.sleepId,
    this.latestPhotoUrl,
  });
}

final dashboardStatsProvider = FutureProvider<DashboardStats>((ref) async {
  final baby = ref.watch(selectedBabyProvider);
  if (baby == null) return DashboardStats();

  final client = SupabaseService.client;
  final todayStr = AppDateUtils.todayStart.toIso8601String();

  // Run all queries in parallel
  final results = await Future.wait([
    // Today's feeds
    client.from('feedings').select('id').eq('baby_id', baby.id)
        .gte('logged_at', todayStr),
    // Today's diapers
    client.from('diapers').select('id').eq('baby_id', baby.id)
        .gte('logged_at', todayStr),
    // Today's sleep total
    client.from('sleeps').select('duration_minutes').eq('baby_id', baby.id)
        .not('end_time', 'is', null)
        .gte('start_time', todayStr),
    // Last feed
    client.from('feedings').select('logged_at, type').eq('baby_id', baby.id)
        .order('logged_at', ascending: false).limit(1),
    // Last diaper
    client.from('diapers').select('logged_at, type').eq('baby_id', baby.id)
        .order('logged_at', ascending: false).limit(1),
    // Active sleep
    client.from('sleeps').select('id, start_time').eq('baby_id', baby.id)
        .isFilter('end_time', null).limit(1),
    // Latest photo
    client.from('photos').select('url').eq('baby_id', baby.id)
        .order('taken_at', ascending: false).limit(1),
  ]);

  final feeds = results[0] as List;
  final diapers = results[1] as List;
  final sleeps = results[2] as List;
  final lastFeed = results[3] as List;
  final lastDiaper = results[4] as List;
  final activeSleep = results[5] as List;
  final latestPhoto = results[6] as List;

  int sleepMins = 0;
  for (final s in sleeps) {
    sleepMins += (s['duration_minutes'] as int?) ?? 0;
  }

  return DashboardStats(
    feedCount: feeds.length,
    diaperCount: diapers.length,
    sleepMinutes: sleepMins,
    lastFeedTime: lastFeed.isNotEmpty ? DateTime.parse(lastFeed[0]['logged_at']) : null,
    lastFeedType: lastFeed.isNotEmpty ? lastFeed[0]['type'] as String? : null,
    lastDiaperTime: lastDiaper.isNotEmpty ? DateTime.parse(lastDiaper[0]['logged_at']) : null,
    lastDiaperType: lastDiaper.isNotEmpty ? lastDiaper[0]['type'] as String? : null,
    isSleeping: activeSleep.isNotEmpty,
    sleepStartTime: activeSleep.isNotEmpty ? DateTime.parse(activeSleep[0]['start_time']) : null,
    sleepId: activeSleep.isNotEmpty ? activeSleep[0]['id'] as String? : null,
    latestPhotoUrl: latestPhoto.isNotEmpty ? latestPhoto[0]['url'] as String? : null,
  );
});

class WeeklyDataPoint {
  final String day;
  final int feeds;
  final int diapers;
  final double sleepHrs;

  WeeklyDataPoint({required this.day, required this.feeds, required this.diapers, required this.sleepHrs});
}

final weeklyDataProvider = FutureProvider<List<WeeklyDataPoint>>((ref) async {
  final baby = ref.watch(selectedBabyProvider);
  if (baby == null) return [];

  final client = SupabaseService.client;
  final weekAgo = AppDateUtils.weekAgoStart().toIso8601String();

  final results = await Future.wait([
    client.from('feedings').select('logged_at').eq('baby_id', baby.id)
        .gte('logged_at', weekAgo),
    client.from('diapers').select('logged_at').eq('baby_id', baby.id)
        .gte('logged_at', weekAgo),
    client.from('sleeps').select('start_time, duration_minutes').eq('baby_id', baby.id)
        .not('end_time', 'is', null).gte('start_time', weekAgo),
  ]);

  final feeds = results[0] as List;
  final diapers = results[1] as List;
  final sleeps = results[2] as List;

  // Group by day
  final days = <String, WeeklyDataPoint>{};
  final dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  for (int i = 6; i >= 0; i--) {
    final d = DateTime.now().subtract(Duration(days: i));
    final key = '${d.year}-${d.month}-${d.day}';
    days[key] = WeeklyDataPoint(
      day: dayNames[d.weekday - 1],
      feeds: 0,
      diapers: 0,
      sleepHrs: 0,
    );
  }

  for (final f in feeds) {
    final dt = DateTime.parse(f['logged_at']);
    final key = '${dt.year}-${dt.month}-${dt.day}';
    if (days.containsKey(key)) {
      final prev = days[key]!;
      days[key] = WeeklyDataPoint(day: prev.day, feeds: prev.feeds + 1, diapers: prev.diapers, sleepHrs: prev.sleepHrs);
    }
  }

  for (final d in diapers) {
    final dt = DateTime.parse(d['logged_at']);
    final key = '${dt.year}-${dt.month}-${dt.day}';
    if (days.containsKey(key)) {
      final prev = days[key]!;
      days[key] = WeeklyDataPoint(day: prev.day, feeds: prev.feeds, diapers: prev.diapers + 1, sleepHrs: prev.sleepHrs);
    }
  }

  for (final s in sleeps) {
    final dt = DateTime.parse(s['start_time']);
    final key = '${dt.year}-${dt.month}-${dt.day}';
    if (days.containsKey(key)) {
      final prev = days[key]!;
      final mins = (s['duration_minutes'] as int?) ?? 0;
      days[key] = WeeklyDataPoint(day: prev.day, feeds: prev.feeds, diapers: prev.diapers, sleepHrs: prev.sleepHrs + mins / 60);
    }
  }

  return days.values.toList();
});
