/// Pure aggregation math for the family and doctor report PDFs.
///
/// No Flutter, no Supabase, no I/O: plain row maps (as returned by the
/// database) plus period bounds go in, exact numbers come out. Every figure
/// either PDF prints is computed here so it can be unit-tested with
/// handcrafted fixtures (see test/report_math_test.dart).
///
/// Conventions shared by every function in this file:
/// - Periods are half-open: [start, end). "End" is the first instant NOT in
///   the period (e.g. Monday 00:00 of the next week).
/// - Day math uses local calendar components, never raw Duration division,
///   so a DST shift can never drop or duplicate a day.
/// - Night vs day sleep is classified BY SESSION START TIME: a session
///   starting at or after 19:00 or before 07:00 is a night sleep in full;
///   everything else is a day sleep in full. Sessions crossing the boundary
///   are NOT split - the PDFs label the split "by start time" accordingly.
library;

// ---------------------------------------------------------------------------
// Time primitives
// ---------------------------------------------------------------------------

/// Parses a database timestamp (ISO-8601 string or DateTime) into local time.
DateTime? parseTimestamp(dynamic raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw.toLocal();
  return DateTime.tryParse(raw.toString())?.toLocal();
}

/// Local-calendar day key, 'yyyy-MM-dd'. Built from date components, so it
/// is stable across DST transitions.
String dayKey(DateTime dt) =>
    '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

/// Calendar-day difference from [a] to [b] (negative when [b] is earlier).
/// Hour-rounded so the 23h/25h days around DST cannot shift the result.
int daysBetween(DateTime a, DateTime b) {
  final from = DateTime(a.year, a.month, a.day);
  final to = DateTime(b.year, b.month, b.day);
  final hours = to.difference(from).inHours;
  // Round to the nearest multiple of 24 (works for negatives too).
  return (hours + (hours.isNegative ? -12 : 12)) ~/ 24;
}

/// Total calendar days in the half-open period [start, end). Never below 1.
int periodLengthDays(DateTime start, DateTime end) {
  final days = daysBetween(start, end);
  return days < 1 ? 1 : days;
}

/// The divisor for every "/ day" average and for expected medication doses.
///
/// - Period entirely in the past: the full period length (all its days had
///   a chance to be logged).
/// - Period that includes [now]: only the days elapsed so far, so a report
///   generated mid-week never under-reports the rates.
///
/// Always at least 1.
int divisorDays({
  required DateTime periodStart,
  required DateTime periodEnd,
  DateTime? now,
}) {
  final ref = now ?? DateTime.now();
  final total = periodLengthDays(periodStart, periodEnd);
  if (!ref.isBefore(periodEnd)) return total;
  final elapsed = daysBetween(periodStart, ref) + 1;
  if (elapsed < 1) return 1;
  return elapsed > total ? total : elapsed;
}

/// Per-day rate; safe for a zero or negative divisor (treated as 1 day).
double perDay(num count, int days) => count / (days < 1 ? 1 : days);

/// '+12%' / '-8%' / 'no change' / 'new' for the current vs previous period.
/// Compare per-day RATES, not raw counts, so unequal period lengths and
/// partially elapsed periods stay comparable.
String deltaLabel(double current, double previous) {
  if (previous <= 0 && current <= 0) return 'no change';
  if (previous <= 0) return 'new';
  final pct = ((current - previous) / previous * 100).round();
  if (pct == 0) return 'no change';
  return '${pct > 0 ? '+' : ''}$pct%';
}

/// Duration of a sleep/tummy session in minutes: trusts duration_minutes
/// when positive, otherwise derives it from end - start. 0 when unknown
/// or the session has no end yet.
int sessionMinutes(Map<String, dynamic> row) {
  final stored = (row['duration_minutes'] as num?)?.toInt() ?? 0;
  if (stored > 0) return stored;
  final start = parseTimestamp(row['start_time']);
  final end = parseTimestamp(row['end_time']);
  if (start == null || end == null) return 0;
  final mins = end.difference(start).inMinutes;
  return mins > 0 ? mins : 0;
}

// ---------------------------------------------------------------------------
// Chart bucketing (weekly report: 7 day buckets; monthly: W1..W5)
// ---------------------------------------------------------------------------

/// Number of chart buckets for the period: 7 days for weekly reports, one
/// bucket per (possibly partial) week for monthly reports.
int bucketCountFor({
  required DateTime periodStart,
  required DateTime periodEnd,
  required bool isMonthly,
}) {
  if (!isMonthly) return 7;
  return ((periodLengthDays(periodStart, periodEnd) - 1) ~/ 7) + 1;
}

/// Bucket index of [dt] within the period; clamped into range so a row a
/// hair outside the bounds can never crash the chart.
int bucketIndexOf(
  DateTime dt, {
  required DateTime periodStart,
  required bool isMonthly,
  required int bucketCount,
}) {
  final dayIndex = daysBetween(periodStart, dt);
  if (!isMonthly) return dayIndex.clamp(0, 6);
  return (dayIndex ~/ 7).clamp(0, bucketCount - 1);
}

/// Sums [weight] per bucket for rows with a parseable [timeField]. The
/// default weight of 1 yields plain counts.
List<double> bucketTotals(
  List<Map<String, dynamic>> rows, {
  required String timeField,
  required DateTime periodStart,
  required bool isMonthly,
  required int bucketCount,
  double Function(Map<String, dynamic> row)? weight,
}) {
  final totals = List<double>.filled(bucketCount, 0);
  for (final row in rows) {
    final dt = parseTimestamp(row[timeField]);
    if (dt == null) continue;
    final i = bucketIndexOf(dt,
        periodStart: periodStart,
        isMonthly: isMonthly,
        bucketCount: bucketCount);
    totals[i] += weight?.call(row) ?? 1;
  }
  return totals;
}

// ---------------------------------------------------------------------------
// Feeding
// ---------------------------------------------------------------------------

/// Daypart of an hour-of-day, for the "most frequent feeds" insight.
String daypartOf(int hour) {
  if (hour >= 6 && hour < 12) return 'morning';
  if (hour >= 12 && hour < 18) return 'afternoon';
  if (hour >= 18) return 'evening';
  return 'night';
}

class FeedingStats {
  /// All feed rows in the period.
  final int total;

  /// Mean amount over ONLY the rows that carry a numeric amount_ml.
  final double? avgMl;

  /// Mean quality (1-5) over ONLY the rows that carry a numeric quality.
  final double? avgQuality;

  /// Rows with quality recorded / rows with quality == 1 ("refused").
  final int qualityKnown;
  final int refusedCount;

  /// Rows that carry a boolean had_spitup / of those, how many were true.
  final int spitUpKnown;
  final int spitUpYes;

  /// Feed count per local day key.
  final Map<String, int> perDayCounts;

  /// Feed count per daypart (morning/afternoon/evening/night).
  final Map<String, int> daypartCounts;

  const FeedingStats({
    required this.total,
    required this.avgMl,
    required this.avgQuality,
    required this.qualityKnown,
    required this.refusedCount,
    required this.spitUpKnown,
    required this.spitUpYes,
    required this.perDayCounts,
    required this.daypartCounts,
  });

  /// Share of spit-up feeds among feeds where it was recorded; null when
  /// no feed carries the flag.
  double? get spitUpRate => spitUpKnown == 0 ? null : spitUpYes / spitUpKnown;

  /// Day with the most feeds (earliest day wins ties), or null.
  String? get busiestDay {
    String? day;
    var best = 0;
    final keys = perDayCounts.keys.toList()..sort();
    for (final k in keys) {
      final c = perDayCounts[k]!;
      if (c > best) {
        best = c;
        day = k;
      }
    }
    return day;
  }

  int get busiestDayCount => busiestDay == null ? 0 : perDayCounts[busiestDay]!;

  factory FeedingStats.fromRows(
    List<Map<String, dynamic>> rows, {
    String timeField = 'logged_at',
  }) {
    var total = 0;
    var mlSum = 0.0;
    var mlCount = 0;
    var qSum = 0.0;
    var qCount = 0;
    var refused = 0;
    var spitKnown = 0;
    var spitYes = 0;
    final perDay = <String, int>{};
    final dayparts = <String, int>{};

    for (final f in rows) {
      total++;
      final dt = parseTimestamp(f[timeField]);
      if (dt != null) {
        perDay.update(dayKey(dt), (v) => v + 1, ifAbsent: () => 1);
        dayparts.update(daypartOf(dt.hour), (v) => v + 1, ifAbsent: () => 1);
      }
      final ml = f['amount_ml'];
      if (ml is num) {
        mlSum += ml.toDouble();
        mlCount++;
      }
      final q = f['quality'];
      if (q is num) {
        qSum += q.toDouble();
        qCount++;
        if (q.toInt() == 1) refused++;
      }
      final spit = f['had_spitup'];
      if (spit is bool) {
        spitKnown++;
        if (spit) spitYes++;
      }
    }

    return FeedingStats(
      total: total,
      avgMl: mlCount == 0 ? null : mlSum / mlCount,
      avgQuality: qCount == 0 ? null : qSum / qCount,
      qualityKnown: qCount,
      refusedCount: refused,
      spitUpKnown: spitKnown,
      spitUpYes: spitYes,
      perDayCounts: perDay,
      daypartCounts: dayparts,
    );
  }
}

// ---------------------------------------------------------------------------
// Sleep
// ---------------------------------------------------------------------------

/// Night window bounds, by session START hour: [nightStartHour, 24) and
/// [0, nightEndHour) are night.
const int nightStartHour = 19;
const int nightEndHour = 7;

/// True when a session starting at [start] counts as a night sleep.
bool isNightStart(DateTime start) =>
    start.hour >= nightStartHour || start.hour < nightEndHour;

class SleepStats {
  /// Sum of minutes over completed sessions (end_time set, positive length).
  final int totalMinutes;

  /// Longest single completed stretch.
  final int longestMinutes;

  /// Number of completed stretches counted into [totalMinutes].
  final int stretchCount;

  /// Minutes attributed entirely to night/day by the session's START time
  /// (19:00-07:00 = night). Boundary-crossing sessions are not split.
  final int nightMinutes;
  final int dayMinutes;

  const SleepStats({
    required this.totalMinutes,
    required this.longestMinutes,
    required this.stretchCount,
    required this.nightMinutes,
    required this.dayMinutes,
  });

  /// Whole-percent night share; day share is its complement, and both are
  /// 0 when nothing was recorded.
  int get nightPct {
    final split = nightMinutes + dayMinutes;
    return split == 0 ? 0 : (nightMinutes / split * 100).round();
  }

  int get dayPct => nightMinutes + dayMinutes == 0 ? 0 : 100 - nightPct;

  factory SleepStats.fromRows(List<Map<String, dynamic>> rows) {
    var total = 0;
    var longest = 0;
    var stretches = 0;
    var night = 0;
    var day = 0;

    for (final s in rows) {
      if (s['end_time'] == null) continue;
      final mins = sessionMinutes(s);
      if (mins <= 0) continue;
      total += mins;
      stretches++;
      if (mins > longest) longest = mins;
      final start = parseTimestamp(s['start_time']);
      if (start != null && isNightStart(start)) {
        night += mins;
      } else {
        day += mins;
      }
    }

    return SleepStats(
      totalMinutes: total,
      longestMinutes: longest,
      stretchCount: stretches,
      nightMinutes: night,
      dayMinutes: day,
    );
  }
}

// ---------------------------------------------------------------------------
// Nappies & digestion
// ---------------------------------------------------------------------------

class NappyStats {
  final int total;

  /// type == 'wet' or 'both' ('both' counts in each).
  final int wetCount;

  /// type == 'dirty' or 'both'.
  final int dirtyCount;

  /// Bristol-style stool_type -> count (rows without the column skipped).
  final Map<int, int> stoolTypeCounts;

  const NappyStats({
    required this.total,
    required this.wetCount,
    required this.dirtyCount,
    required this.stoolTypeCounts,
  });

  factory NappyStats.fromRows(List<Map<String, dynamic>> rows) {
    var total = 0;
    var wet = 0;
    var dirty = 0;
    final stools = <int, int>{};
    for (final d in rows) {
      total++;
      final type = (d['type'] ?? '').toString();
      if (type == 'wet' || type == 'both') wet++;
      if (type == 'dirty' || type == 'both') dirty++;
      final st = d['stool_type'];
      if (st is int) stools.update(st, (v) => v + 1, ifAbsent: () => 1);
    }
    return NappyStats(
      total: total,
      wetCount: wet,
      dirtyCount: dirty,
      stoolTypeCounts: stools,
    );
  }
}

/// Distinct journalled days where cramps or gas was rated 2+ (0-3 scale).
int uncomfortableDayCount(List<Map<String, dynamic>> journals) {
  final days = <String>{};
  for (final j in journals) {
    final cramps = (j['cramps'] as num?)?.toInt() ?? 0;
    final gas = (j['gas'] as num?)?.toInt() ?? 0;
    if (cramps >= 2 || gas >= 2) {
      days.add((j['journal_date'] ?? '').toString());
    }
  }
  return days.length;
}

// ---------------------------------------------------------------------------
// Reflux
// ---------------------------------------------------------------------------

class RefluxStats {
  final int total;

  /// severity (1-5) -> count, only over rows that carry an int severity.
  final Map<int, int> severityCounts;

  /// Events flagged painful_crying == true.
  final int painfulCount;

  /// trigger_noticed grouped after trim + lowercase; empties skipped.
  final Map<String, int> triggerCounts;

  /// Event count per local day key.
  final Map<String, int> perDayCounts;

  const RefluxStats({
    required this.total,
    required this.severityCounts,
    required this.painfulCount,
    required this.triggerCounts,
    required this.perDayCounts,
  });

  /// Triggers sorted most-frequent first (alphabetical within ties).
  List<MapEntry<String, int>> get topTriggers {
    final entries = triggerCounts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    return entries;
  }

  /// Day with the most events (earliest wins ties), or null.
  String? get worstDay {
    String? day;
    var best = 0;
    final keys = perDayCounts.keys.toList()..sort();
    for (final k in keys) {
      final c = perDayCounts[k]!;
      if (c > best) {
        best = c;
        day = k;
      }
    }
    return day;
  }

  int get worstDayCount => worstDay == null ? 0 : perDayCounts[worstDay]!;

  factory RefluxStats.fromRows(
    List<Map<String, dynamic>> rows, {
    String timeField = 'logged_at',
  }) {
    var total = 0;
    var painful = 0;
    final severities = <int, int>{};
    final triggers = <String, int>{};
    final perDay = <String, int>{};
    for (final r in rows) {
      total++;
      final dt = parseTimestamp(r[timeField]);
      if (dt != null) {
        perDay.update(dayKey(dt), (v) => v + 1, ifAbsent: () => 1);
      }
      final sev = r['severity'];
      if (sev is int) severities.update(sev, (v) => v + 1, ifAbsent: () => 1);
      if (r['painful_crying'] == true) painful++;
      final trigger =
          (r['trigger_noticed'] ?? '').toString().trim().toLowerCase();
      if (trigger.isNotEmpty) {
        triggers.update(trigger, (v) => v + 1, ifAbsent: () => 1);
      }
    }
    return RefluxStats(
      total: total,
      severityCounts: severities,
      painfulCount: painful,
      triggerCounts: triggers,
      perDayCounts: perDay,
    );
  }
}

// ---------------------------------------------------------------------------
// Medication adherence
// ---------------------------------------------------------------------------

/// One catalogued medication on a fixed schedule.
class ScheduledAdherence {
  final String name;
  final int frequencyPerDay;
  final int given;

  /// frequency x divisor days (elapsed days when the period includes today,
  /// full period length for past periods).
  final int expected;

  /// The catalog row, for display fields (default_dosage etc.).
  final Map<String, dynamic> source;

  const ScheduledAdherence({
    required this.name,
    required this.frequencyPerDay,
    required this.given,
    required this.expected,
    required this.source,
  });

  /// 0..1+ fraction (can exceed 1 when extra doses were given); null when
  /// nothing was expected.
  double? get adherence => expected == 0 ? null : given / expected;
}

/// An as-needed medication, or doses logged for a name not in the catalog.
class AsNeededUsage {
  final String name;
  final int given;
  final bool inCatalog;

  /// The catalog row when [inCatalog]; empty map otherwise.
  final Map<String, dynamic> source;

  const AsNeededUsage({
    required this.name,
    required this.given,
    required this.inCatalog,
    required this.source,
  });
}

class MedicationAdherence {
  final List<ScheduledAdherence> scheduled;
  final List<AsNeededUsage> asNeeded;

  const MedicationAdherence({
    required this.scheduled,
    required this.asNeeded,
  });

  /// [catalog]: baby_medications rows. [healthLogs]: health_logs rows; only
  /// those with a non-empty medication count as doses. [days]: the divisor
  /// from [divisorDays] - elapsed days for a live period, full length for a
  /// past one.
  factory MedicationAdherence.compute({
    required List<Map<String, dynamic>> catalog,
    required List<Map<String, dynamic>> healthLogs,
    required int days,
  }) {
    final givenByName = <String, int>{};
    for (final h in healthLogs) {
      final name = (h['medication'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      givenByName.update(name.toLowerCase(), (v) => v + 1, ifAbsent: () => 1);
    }

    final scheduled = <ScheduledAdherence>[];
    final asNeeded = <AsNeededUsage>[];
    final matched = <String>{};
    for (final m in catalog) {
      final name = (m['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      final key = name.toLowerCase();
      matched.add(key);
      final given = givenByName[key] ?? 0;
      final freq = (m['frequency_per_day'] as num?)?.toInt();
      final isAsNeeded = m['as_needed'] == true || freq == null || freq <= 0;
      if (isAsNeeded) {
        asNeeded.add(AsNeededUsage(
          name: name,
          given: given,
          inCatalog: true,
          source: m,
        ));
      } else {
        scheduled.add(ScheduledAdherence(
          name: name,
          frequencyPerDay: freq,
          given: given,
          expected: freq * (days < 1 ? 1 : days),
          source: m,
        ));
      }
    }

    // Doses logged for medicines not in the catalog still deserve a row.
    final extraKeys = givenByName.keys.where((k) => !matched.contains(k))
        .toList()
      ..sort();
    for (final key in extraKeys) {
      asNeeded.add(AsNeededUsage(
        name: key,
        given: givenByName[key]!,
        inCatalog: false,
        source: const {},
      ));
    }

    return MedicationAdherence(scheduled: scheduled, asNeeded: asNeeded);
  }
}

/// Health-log rows that record a medicine dose.
int medicationDoseCount(List<Map<String, dynamic>> healthLogs) => healthLogs
    .where((h) => (h['medication'] ?? '').toString().trim().isNotEmpty)
    .length;

/// Banding for a temperature in Celsius, per the NHS "Fever in children"
/// page (https://www.nhs.uk/symptoms/fever-in-children/): 38°C or more is a
/// high temperature; 39°C+ means contact a doctor for young babies.
/// Keep in sync with _getTempStatus() in health_screen.dart.
String temperatureStatus(double celsius) {
  if (celsius < 36) return 'Low';
  if (celsius < 38) return 'Normal';
  if (celsius < 39) return 'Fever';
  return 'High fever';
}

/// Citation line rendered under any report table that uses
/// [temperatureStatus] (Apple guideline 1.4.1).
const String temperatureSourceNote =
    'Temperature status per NHS "Fever in children" guidance '
    '(nhs.uk/symptoms/fever-in-children). Not medical advice.';

// ---------------------------------------------------------------------------
// Mood (journals)
// ---------------------------------------------------------------------------

/// Recognised journal moods, in display order.
const List<String> knownMoods = ['happy', 'okay', 'fussy', 'very_fussy'];

/// mood -> count over journal rows; unknown moods are skipped.
Map<String, int> moodCounts(List<Map<String, dynamic>> journals) {
  final counts = <String, int>{};
  for (final j in journals) {
    final mood = (j['mood'] ?? '').toString();
    if (knownMoods.contains(mood)) {
      counts.update(mood, (v) => v + 1, ifAbsent: () => 1);
    }
  }
  return counts;
}

// ---------------------------------------------------------------------------
// "At a glance" aggregates (current vs previous period, computed identically
// so the deltas compare like with like)
// ---------------------------------------------------------------------------

class GlanceAggregates {
  final int feeds;
  final double? avgMl;
  final int sleepMinutes;
  final int longestSleepMin;
  final int nappies;
  final int tummyMinutes;
  final int refluxEvents;
  final int medicineDoses;

  const GlanceAggregates({
    required this.feeds,
    required this.avgMl,
    required this.sleepMinutes,
    required this.longestSleepMin,
    required this.nappies,
    required this.tummyMinutes,
    required this.refluxEvents,
    required this.medicineDoses,
  });

  factory GlanceAggregates.of({
    required List<Map<String, dynamic>> feedings,
    required List<Map<String, dynamic>> sleeps,
    required List<Map<String, dynamic>> diapers,
    required List<Map<String, dynamic>> tummyTimes,
    required List<Map<String, dynamic>> reflux,
    required List<Map<String, dynamic>> healthLogs,
  }) {
    final feeding = FeedingStats.fromRows(feedings);
    final sleep = SleepStats.fromRows(sleeps);
    final tummyMin = tummyTimes.fold<int>(
        0, (sum, t) => sum + ((t['duration_minutes'] as num?)?.toInt() ?? 0));
    return GlanceAggregates(
      feeds: feeding.total,
      avgMl: feeding.avgMl,
      sleepMinutes: sleep.totalMinutes,
      longestSleepMin: sleep.longestMinutes,
      nappies: diapers.length,
      tummyMinutes: tummyMin,
      refluxEvents: reflux.length,
      medicineDoses: medicationDoseCount(healthLogs),
    );
  }
}

// ---------------------------------------------------------------------------
// Day-by-day ledger
// ---------------------------------------------------------------------------

/// One day's complete activity line in the family report's daily ledger.
class DayLedger {
  final DateTime day;
  final int feeds;
  final double milkMl;
  final int sleepSessions;
  final int sleepMinutes;
  final int nappies;
  final int refluxEvents;
  final int medicineDoses;
  final int tummyMinutes;
  final String? mood;

  const DayLedger({
    required this.day,
    required this.feeds,
    required this.milkMl,
    required this.sleepSessions,
    required this.sleepMinutes,
    required this.nappies,
    required this.refluxEvents,
    required this.medicineDoses,
    required this.tummyMinutes,
    required this.mood,
  });

  bool get isEmpty =>
      feeds == 0 &&
      sleepSessions == 0 &&
      nappies == 0 &&
      refluxEvents == 0 &&
      medicineDoses == 0 &&
      tummyMinutes == 0 &&
      mood == null;
}

/// Buckets every record into local calendar days, one [DayLedger] per day
/// from [start] (inclusive) for [days] days, in order. Sleep and tummy
/// sessions count on the day they STARTED; medicine doses are health_logs
/// rows with a non-empty medication.
List<DayLedger> dailyLedger({
  required DateTime start,
  required int days,
  required List<Map<String, dynamic>> feedings,
  required List<Map<String, dynamic>> sleeps,
  required List<Map<String, dynamic>> diapers,
  required List<Map<String, dynamic>> reflux,
  required List<Map<String, dynamic>> healthLogs,
  required List<Map<String, dynamic>> tummyTimes,
  required List<Map<String, dynamic>> journals,
}) {
  String? keyOf(Map<String, dynamic> row, String field) {
    final dt = parseTimestamp(row[field]);
    return dt == null ? null : dayKey(dt);
  }

  final feedCount = <String, int>{};
  final mlSum = <String, double>{};
  for (final f in feedings) {
    final k = keyOf(f, 'logged_at');
    if (k == null) continue;
    feedCount[k] = (feedCount[k] ?? 0) + 1;
    final ml = f['amount_ml'];
    if (ml is num) mlSum[k] = (mlSum[k] ?? 0) + ml.toDouble();
  }

  final sleepCount = <String, int>{};
  final sleepMin = <String, int>{};
  for (final s in sleeps) {
    final k = keyOf(s, 'start_time');
    if (k == null) continue;
    final minutes = sessionMinutes(s);
    if (minutes <= 0) continue;
    sleepCount[k] = (sleepCount[k] ?? 0) + 1;
    sleepMin[k] = (sleepMin[k] ?? 0) + minutes;
  }

  final nappyCount = <String, int>{};
  for (final d in diapers) {
    final k = keyOf(d, 'logged_at');
    if (k != null) nappyCount[k] = (nappyCount[k] ?? 0) + 1;
  }

  final refluxCount = <String, int>{};
  for (final r in reflux) {
    final k = keyOf(r, 'logged_at');
    if (k != null) refluxCount[k] = (refluxCount[k] ?? 0) + 1;
  }

  final doseCount = <String, int>{};
  for (final h in healthLogs) {
    if ((h['medication'] ?? '').toString().trim().isEmpty) continue;
    final k = keyOf(h, 'logged_at');
    if (k != null) doseCount[k] = (doseCount[k] ?? 0) + 1;
  }

  final tummyMin = <String, int>{};
  for (final t in tummyTimes) {
    final k = keyOf(t, 'start_time');
    if (k == null) continue;
    final minutes = (t['duration_minutes'] as num?)?.toInt() ?? 0;
    if (minutes > 0) tummyMin[k] = (tummyMin[k] ?? 0) + minutes;
  }

  final moodByDay = <String, String>{};
  for (final j in journals) {
    final date = DateTime.tryParse((j['journal_date'] ?? '').toString());
    final mood = (j['mood'] ?? '').toString().trim();
    if (date != null && mood.isNotEmpty) moodByDay[dayKey(date)] = mood;
  }

  return [
    for (var i = 0; i < days; i++)
      () {
        final day = DateTime(start.year, start.month, start.day + i);
        final k = dayKey(day);
        return DayLedger(
          day: day,
          feeds: feedCount[k] ?? 0,
          milkMl: mlSum[k] ?? 0,
          sleepSessions: sleepCount[k] ?? 0,
          sleepMinutes: sleepMin[k] ?? 0,
          nappies: nappyCount[k] ?? 0,
          refluxEvents: refluxCount[k] ?? 0,
          medicineDoses: doseCount[k] ?? 0,
          tummyMinutes: tummyMin[k] ?? 0,
          mood: moodByDay[k],
        );
      }(),
  ];
}
