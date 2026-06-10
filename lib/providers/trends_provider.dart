import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/supabase_service.dart';
import 'baby_provider.dart';
import '../utils/date_utils.dart';

/// One day's aggregated activity for the Trends screen.
class TrendsDayEntry {
  const TrendsDayEntry({
    required this.day,
    this.feedsCount = 0,
    this.totalMl = 0,
    this.sleepMinutes = 0,
    this.longestSleepMinutes = 0,
    this.wetCount = 0,
    this.dirtyCount = 0,
    this.refluxCount = 0,
    this.maxRefluxSeverity = 0,
  });

  /// Local midnight of the day this entry covers.
  final DateTime day;
  final int feedsCount;
  final double totalMl;
  final int sleepMinutes;
  final int longestSleepMinutes;
  final int wetCount;
  final int dirtyCount;
  final int refluxCount;

  /// 0 when no reflux events that day, otherwise 1-5.
  final int maxRefluxSeverity;
}

/// A week-over-week comparison: the last 7 days vs the 7 before them.
class TrendDelta {
  const TrendDelta({this.current = 0, this.previous = 0});

  final double current;
  final double previous;

  double get delta => current - previous;
}

/// Fourteen day-buckets (oldest → newest) plus week-over-week deltas.
class TrendsData {
  const TrendsData({
    required this.days,
    this.feedsPerDay = const TrendDelta(),
    this.avgMlPerFeed = const TrendDelta(),
    this.sleepMinutesPerDay = const TrendDelta(),
    this.refluxPerDay = const TrendDelta(),
  });

  final List<TrendsDayEntry> days;
  final TrendDelta feedsPerDay;
  final TrendDelta avgMlPerFeed;
  final TrendDelta sleepMinutesPerDay;
  final TrendDelta refluxPerDay;

  bool get hasRefluxData => days.any((d) => d.refluxCount > 0);
}

/// Mutable accumulator used while bucketing rows into days.
class _DayAcc {
  int feedsCount = 0;
  double totalMl = 0;
  int sleepMinutes = 0;
  int longestSleepMinutes = 0;
  int wetCount = 0;
  int dirtyCount = 0;
  int refluxCount = 0;
  int maxRefluxSeverity = 0;
}

String _dateKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

/// Last 14 days of feeding, sleep, nappy and reflux activity for the selected
/// baby, bucketed per day. The reflux table ships with the Care Pack
/// migration; until it exists, the reflux query quietly yields no events
/// instead of failing the whole screen.
final trendsDataProvider = FutureProvider.autoDispose<TrendsData>((ref) async {
  final baby = ref.watch(selectedBabyProvider);

  // Local midnights for the 14-day window, oldest → newest (today last).
  // Day-component arithmetic, not Duration math - DST-safe.
  final now = DateTime.now();
  final dayStarts = List<DateTime>.generate(
    14,
    (i) => DateTime(now.year, now.month, now.day - (13 - i)),
  );

  if (baby == null) {
    return TrendsData(days: [for (final d in dayStarts) TrendsDayEntry(day: d)]);
  }

  final indexByDate = <String, int>{
    for (final (i, d) in dayStarts.indexed) _dateKey(d): i,
  };
  int? indexFor(DateTime local) => indexByDate[_dateKey(local)];

  final startIso = dayStarts.first.toUtc().toIso8601String();
  final client = SupabaseService.client;

  Future<List<Map<String, dynamic>>> feedingsQuery() async =>
      List<Map<String, dynamic>>.from(await client
          .from('feedings')
          .select('logged_at, amount_ml')
          .eq('baby_id', baby.id)
          .isFilter('deleted_at', null)
          .gte('logged_at', startIso));

  Future<List<Map<String, dynamic>>> sleepsQuery() async =>
      List<Map<String, dynamic>>.from(await client
          .from('sleeps')
          .select('start_time, end_time, duration_minutes')
          .eq('baby_id', baby.id)
          .not('end_time', 'is', null)
          .isFilter('deleted_at', null)
          .gte('start_time', startIso));

  Future<List<Map<String, dynamic>>> diapersQuery() async =>
      List<Map<String, dynamic>>.from(await client
          .from('diapers')
          .select('logged_at, type')
          .eq('baby_id', baby.id)
          .isFilter('deleted_at', null)
          .gte('logged_at', startIso));

  Future<List<Map<String, dynamic>>> refluxQuery() async {
    try {
      return List<Map<String, dynamic>>.from(await client
          .from('reflux_events')
          .select('logged_at, severity')
          .eq('baby_id', baby.id)
          .isFilter('deleted_at', null)
          .gte('logged_at', startIso));
    } catch (e) {
      // Table may predate the Care Pack migration - treat as "no events".
      debugPrint('trendsDataProvider reflux query failed: $e');
      return const [];
    }
  }

  final results = await Future.wait(
      [feedingsQuery(), sleepsQuery(), diapersQuery(), refluxQuery()]);
  final feedings = results[0];
  final sleeps = results[1];
  final diapers = results[2];
  final reflux = results[3];

  final accs = List.generate(14, (_) => _DayAcc());

  // avg-ml-per-feed is computed over feeds that recorded an amount, so
  // breast feeds without a volume don't drag the average to zero.
  var prevMlSum = 0.0, prevMlCount = 0, currMlSum = 0.0, currMlCount = 0;

  for (final row in feedings) {
    final at = parseDbTime(row['logged_at'] as String).toLocal();
    final i = indexFor(at);
    if (i == null) continue;
    final ml = (row['amount_ml'] as num?)?.toDouble();
    accs[i].feedsCount++;
    accs[i].totalMl += ml ?? 0;
    if (ml != null) {
      if (i < 7) {
        prevMlSum += ml;
        prevMlCount++;
      } else {
        currMlSum += ml;
        currMlCount++;
      }
    }
  }

  for (final row in sleeps) {
    final start = parseDbTime(row['start_time'] as String).toLocal();
    final i = indexFor(start);
    if (i == null) continue;
    var minutes = (row['duration_minutes'] as num?)?.toInt() ?? 0;
    if (minutes <= 0 && row['end_time'] != null) {
      final end = parseDbTime(row['end_time'] as String).toLocal();
      minutes = end.difference(start).inMinutes;
    }
    if (minutes <= 0) continue;
    accs[i].sleepMinutes += minutes;
    if (minutes > accs[i].longestSleepMinutes) {
      accs[i].longestSleepMinutes = minutes;
    }
  }

  for (final row in diapers) {
    final at = parseDbTime(row['logged_at'] as String).toLocal();
    final i = indexFor(at);
    if (i == null) continue;
    final type = row['type'] as String?;
    // 'both' counts as wet AND dirty, matching the weekly report metrics.
    if (type != 'dirty') accs[i].wetCount++;
    if (type != 'wet') accs[i].dirtyCount++;
  }

  for (final row in reflux) {
    final at = parseDbTime(row['logged_at'] as String).toLocal();
    final i = indexFor(at);
    if (i == null) continue;
    final severity = (row['severity'] as num?)?.toInt() ?? 0;
    accs[i].refluxCount++;
    if (severity > accs[i].maxRefluxSeverity) {
      accs[i].maxRefluxSeverity = severity;
    }
  }

  final days = [
    for (final (i, d) in dayStarts.indexed)
      TrendsDayEntry(
        day: d,
        feedsCount: accs[i].feedsCount,
        totalMl: accs[i].totalMl,
        sleepMinutes: accs[i].sleepMinutes,
        longestSleepMinutes: accs[i].longestSleepMinutes,
        wetCount: accs[i].wetCount,
        dirtyCount: accs[i].dirtyCount,
        refluxCount: accs[i].refluxCount,
        maxRefluxSeverity: accs[i].maxRefluxSeverity,
      ),
  ];

  int sum(int from, int to, int Function(TrendsDayEntry) pick) {
    var total = 0;
    for (var i = from; i < to; i++) {
      total += pick(days[i]);
    }
    return total;
  }

  TrendDelta perDay(int Function(TrendsDayEntry) pick) => TrendDelta(
        current: sum(7, 14, pick) / 7,
        previous: sum(0, 7, pick) / 7,
      );

  return TrendsData(
    days: days,
    feedsPerDay: perDay((d) => d.feedsCount),
    avgMlPerFeed: TrendDelta(
      current: currMlCount == 0 ? 0 : currMlSum / currMlCount,
      previous: prevMlCount == 0 ? 0 : prevMlSum / prevMlCount,
    ),
    sleepMinutesPerDay: perDay((d) => d.sleepMinutes),
    refluxPerDay: perDay((d) => d.refluxCount),
  );
});
