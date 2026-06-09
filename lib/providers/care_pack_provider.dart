import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/care_pack_models.dart';
import '../services/supabase_service.dart';
import '../utils/care_pack_data.dart';
import 'baby_provider.dart';

/// The Care Pack tables ship in supabase/2026-06-10_care_pack.sql. Until that
/// migration runs, queries fail with undefined-table/column errors; screens
/// catch [SchemaNotReadyException] and show a "database upgrade pending"
/// state instead of a scary generic error.
class SchemaNotReadyException implements Exception {
  @override
  String toString() =>
      'The database upgrade for this feature has not been applied yet.';
}

bool _isSchemaNotReady(Object e) {
  if (e is PostgrestException) {
    final code = e.code ?? '';
    return code == '42P01' || // undefined table
        code == '42703' || // undefined column
        code == 'PGRST204' || // column not in schema cache
        code == 'PGRST205'; // table not in schema cache
  }
  return false;
}

Never _handle(Object e, StackTrace st, String where) {
  debugPrint('$where error: $e\n$st');
  if (_isSchemaNotReady(e)) throw SchemaNotReadyException();
  throw e; // ignore: only_throw_errors
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Monday of the week containing [d] (the pack's weeks run Mon–Sun).
DateTime weekStartOf(DateTime d) =>
    _dateOnly(d).subtract(Duration(days: d.weekday - 1));

String _dateString(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Age in whole months, calendar-accurate.
int ageInMonths(DateTime dateOfBirth, [DateTime? at]) {
  final now = at ?? DateTime.now();
  var months =
      (now.year - dateOfBirth.year) * 12 + (now.month - dateOfBirth.month);
  if (now.day < dateOfBirth.day) months--;
  return months < 0 ? 0 : months;
}

/// The current care-pack stage for the selected baby.
final currentStageProvider = Provider<CarePackStage?>((ref) {
  final baby = ref.watch(selectedBabyProvider);
  if (baby == null) return null;
  return CarePackData.stageForAgeMonths(ageInMonths(baby.dateOfBirth));
});

// ---------------------------------------------------------------------------
// Reflux
// ---------------------------------------------------------------------------

final recentRefluxEventsProvider =
    FutureProvider<List<RefluxEvent>>((ref) async {
  final baby = ref.watch(selectedBabyProvider);
  if (baby == null) return [];

  try {
    final since = DateTime.now().subtract(const Duration(days: 14));
    final data = await SupabaseService.client
        .from('reflux_events')
        .select('*')
        .eq('baby_id', baby.id)
        .gte('logged_at', since.toUtc().toIso8601String())
        .order('logged_at', ascending: false);
    return data.map<RefluxEvent>(RefluxEvent.fromJson).toList();
  } catch (e, st) {
    _handle(e, st, 'recentRefluxEventsProvider');
  }
});

class RefluxActions {
  static Future<void> logEvent({
    required String babyId,
    required int severity,
    bool painfulCrying = false,
    bool archingBack = false,
    String? triggerNoticed,
    String? notes,
    DateTime? loggedAt,
  }) async {
    final userId = SupabaseService.userId;
    if (userId == null) return;
    await SupabaseService.client.from('reflux_events').insert({
      'baby_id': babyId,
      'user_id': userId,
      'severity': severity,
      'painful_crying': painfulCrying,
      'arching_back': archingBack,
      'trigger_noticed':
          (triggerNoticed?.isNotEmpty ?? false) ? triggerNoticed : null,
      'notes': (notes?.isNotEmpty ?? false) ? notes : null,
      'logged_at': (loggedAt ?? DateTime.now()).toUtc().toIso8601String(),
    });
  }

  static Future<void> delete(String id) async {
    await SupabaseService.client.from('reflux_events').delete().eq('id', id);
  }
}

// ---------------------------------------------------------------------------
// Daily journal
// ---------------------------------------------------------------------------

/// Journal for a given day (date-only). Null when nothing logged yet.
final journalForDateProvider =
    FutureProvider.family<DailyJournal?, DateTime>((ref, date) async {
  final baby = ref.watch(selectedBabyProvider);
  if (baby == null) return null;

  try {
    final rows = await SupabaseService.client
        .from('daily_journals')
        .select('*')
        .eq('baby_id', baby.id)
        .eq('journal_date', _dateString(date))
        .limit(1);
    if (rows.isEmpty) return null;
    return DailyJournal.fromJson(rows.first);
  } catch (e, st) {
    _handle(e, st, 'journalForDateProvider');
  }
});

final recentJournalsProvider =
    FutureProvider<List<DailyJournal>>((ref) async {
  final baby = ref.watch(selectedBabyProvider);
  if (baby == null) return [];

  try {
    final data = await SupabaseService.client
        .from('daily_journals')
        .select('*')
        .eq('baby_id', baby.id)
        .order('journal_date', ascending: false)
        .limit(14);
    return data.map<DailyJournal>(DailyJournal.fromJson).toList();
  } catch (e, st) {
    _handle(e, st, 'recentJournalsProvider');
  }
});

class JournalActions {
  static Future<void> upsert({
    required String babyId,
    required DateTime date,
    String? mood,
    int? cramps,
    int? gas,
    String? fussyTimes,
    String? activities,
    String? newThings,
    String? upsets,
    String? notes,
  }) async {
    final userId = SupabaseService.userId;
    if (userId == null) return;
    await SupabaseService.client.from('daily_journals').upsert(
      {
        'baby_id': babyId,
        'user_id': userId,
        'journal_date': _dateString(date),
        'mood': mood,
        'cramps': cramps,
        'gas': gas,
        'fussy_times': _orNull(fussyTimes),
        'activities': _orNull(activities),
        'new_things': _orNull(newThings),
        'upsets': _orNull(upsets),
        'notes': _orNull(notes),
      },
      onConflict: 'baby_id,journal_date',
    );
  }

  static String? _orNull(String? s) =>
      (s == null || s.trim().isEmpty) ? null : s.trim();
}

// ---------------------------------------------------------------------------
// Weekly report
// ---------------------------------------------------------------------------

/// Saved report for the week containing [anchor] (draft or submitted).
final weeklyReportProvider =
    FutureProvider.family<WeeklyCareReport?, DateTime>((ref, anchor) async {
  final baby = ref.watch(selectedBabyProvider);
  if (baby == null) return null;

  try {
    final rows = await SupabaseService.client
        .from('weekly_reports')
        .select('*')
        .eq('baby_id', baby.id)
        .eq('week_start', _dateString(weekStartOf(anchor)))
        .limit(1);
    if (rows.isEmpty) return null;
    return WeeklyCareReport.fromJson(rows.first);
  } catch (e, st) {
    _handle(e, st, 'weeklyReportProvider');
  }
});

final pastWeeklyReportsProvider =
    FutureProvider<List<WeeklyCareReport>>((ref) async {
  final baby = ref.watch(selectedBabyProvider);
  if (baby == null) return [];

  try {
    final data = await SupabaseService.client
        .from('weekly_reports')
        .select('*')
        .eq('baby_id', baby.id)
        .order('week_start', ascending: false)
        .limit(12);
    return data.map<WeeklyCareReport>(WeeklyCareReport.fromJson).toList();
  } catch (e, st) {
    _handle(e, st, 'pastWeeklyReportsProvider');
  }
});

/// Auto-computed metrics for the week containing [anchor], from data that is
/// already logged in the app. The nanny no longer has to tally averages by
/// hand — the report pre-fills itself.
final weeklyMetricsProvider =
    FutureProvider.family<Map<String, dynamic>, DateTime>((ref, anchor) async {
  final baby = ref.watch(selectedBabyProvider);
  if (baby == null) return {};

  final start = weekStartOf(anchor);
  final end = start.add(const Duration(days: 7));
  final startIso = start.toUtc().toIso8601String();
  final endIso = end.toUtc().toIso8601String();
  final client = SupabaseService.client;

  Future<List<Map<String, dynamic>>> rows(
      String table, String timeCol, String cols) async {
    try {
      final data = await client
          .from(table)
          .select(cols)
          .eq('baby_id', baby.id)
          .gte(timeCol, startIso)
          .lt(timeCol, endIso);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('weeklyMetrics $table failed: $e');
      return const [];
    }
  }

  final feedings = await rows(
      'feedings', 'logged_at', 'amount_ml, duration_minutes, logged_at');
  final sleeps = await rows(
      'sleeps', 'start_time', 'start_time, end_time, duration_minutes');
  final diapers = await rows('diapers', 'logged_at', 'type, logged_at');
  final tummy =
      await rows('tummy_times', 'start_time', 'duration_minutes');
  final reflux = await rows(
      'reflux_events', 'logged_at', 'severity, painful_crying, logged_at');

  final daysSoFar =
      DateTime.now().isBefore(end) ? DateTime.now().difference(start).inDays + 1 : 7;
  final divisor = daysSoFar.clamp(1, 7);

  final mlValues = [
    for (final f in feedings)
      if (f['amount_ml'] != null) (f['amount_ml'] as num).toDouble()
  ];

  // Longest completed overnight sleep stretch this week.
  int longestSleepMin = 0;
  int totalNapMin = 0;
  for (final s in sleeps) {
    final mins = (s['duration_minutes'] as num?)?.toInt() ?? 0;
    if (mins > longestSleepMin) longestSleepMin = mins;
    final startT = DateTime.parse(s['start_time'] as String).toLocal();
    if (startT.hour >= 7 && startT.hour < 19) totalNapMin += mins;
  }

  return {
    'feeds_total': feedings.length,
    'feeds_per_day': (feedings.length / divisor).toStringAsFixed(1),
    'avg_ml_per_feed': mlValues.isEmpty
        ? null
        : (mlValues.reduce((a, b) => a + b) / mlValues.length).round(),
    'nap_minutes_per_day': (totalNapMin / divisor).round(),
    'longest_sleep_minutes': longestSleepMin,
    'diapers_total': diapers.length,
    'wet_diapers': diapers.where((d) => d['type'] != 'dirty').length,
    'dirty_diapers': diapers.where((d) => d['type'] != 'wet').length,
    'tummy_time_minutes': tummy.fold<int>(
        0, (sum, t) => sum + ((t['duration_minutes'] as num?)?.toInt() ?? 0)),
    'spitups_total': reflux.length,
    'spitups_per_day': (reflux.length / divisor).toStringAsFixed(1),
    'painful_reflux_episodes':
        reflux.where((r) => r['painful_crying'] == true).length,
  };
});

class WeeklyReportActions {
  static Future<void> save({
    required String babyId,
    required DateTime weekStart,
    required String ageStage,
    String? summary,
    String? struggles,
    String? questions,
    Map<String, String>? milestoneChecks,
    Map<String, String>? focusAnswers,
    Map<String, dynamic>? metrics,
    bool submit = false,
  }) async {
    final userId = SupabaseService.userId;
    if (userId == null) return;
    await SupabaseService.client.from('weekly_reports').upsert(
      {
        'baby_id': babyId,
        'user_id': userId,
        'week_start': _dateString(weekStart),
        'age_stage': ageStage,
        'summary': JournalActions._orNull(summary),
        'struggles': JournalActions._orNull(struggles),
        'questions': JournalActions._orNull(questions),
        'milestone_checks': ?milestoneChecks,
        'focus_answers': ?focusAnswers,
        'metrics': ?metrics,
        if (submit) 'submitted_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'baby_id,week_start',
    );
  }
}

// ---------------------------------------------------------------------------
// Monthly review
// ---------------------------------------------------------------------------

final monthlyReviewProvider =
    FutureProvider.family<MonthlyReview?, DateTime>((ref, month) async {
  final baby = ref.watch(selectedBabyProvider);
  if (baby == null) return null;

  try {
    final rows = await SupabaseService.client
        .from('monthly_reviews')
        .select('*')
        .eq('baby_id', baby.id)
        .eq('review_month', _dateString(DateTime(month.year, month.month, 1)))
        .limit(1);
    if (rows.isEmpty) return null;
    return MonthlyReview.fromJson(rows.first);
  } catch (e, st) {
    _handle(e, st, 'monthlyReviewProvider');
  }
});

final pastMonthlyReviewsProvider =
    FutureProvider<List<MonthlyReview>>((ref) async {
  final baby = ref.watch(selectedBabyProvider);
  if (baby == null) return [];

  try {
    final data = await SupabaseService.client
        .from('monthly_reviews')
        .select('*')
        .eq('baby_id', baby.id)
        .order('review_month', ascending: false)
        .limit(12);
    return data.map<MonthlyReview>(MonthlyReview.fromJson).toList();
  } catch (e, st) {
    _handle(e, st, 'pastMonthlyReviewsProvider');
  }
});

class MonthlyReviewActions {
  static Future<void> save({
    required String babyId,
    required DateTime month,
    required String ageStage,
    required Map<String, String> checklist,
    String? comments,
  }) async {
    final userId = SupabaseService.userId;
    if (userId == null) return;
    await SupabaseService.client.from('monthly_reviews').upsert(
      {
        'baby_id': babyId,
        'user_id': userId,
        'review_month': _dateString(DateTime(month.year, month.month, 1)),
        'age_stage': ageStage,
        'checklist': checklist,
        'comments': JournalActions._orNull(comments),
      },
      onConflict: 'baby_id,review_month',
    );
  }
}

// ---------------------------------------------------------------------------
// Emergency contacts
// ---------------------------------------------------------------------------

final emergencyContactsProvider =
    FutureProvider<List<EmergencyContact>>((ref) async {
  final baby = ref.watch(selectedBabyProvider);
  if (baby == null) return [];

  try {
    final data = await SupabaseService.client
        .from('emergency_contacts')
        .select('*')
        .eq('baby_id', baby.id)
        .order('sort_order');
    return data.map<EmergencyContact>(EmergencyContact.fromJson).toList();
  } catch (e, st) {
    _handle(e, st, 'emergencyContactsProvider');
  }
});

class EmergencyContactActions {
  /// Creates the default fridge-sheet rows on first open.
  static Future<void> seedDefaults(String babyId) async {
    final userId = SupabaseService.userId;
    if (userId == null) return;
    await SupabaseService.client.from('emergency_contacts').insert([
      for (final (i, label) in CarePackData.defaultContactLabels.indexed)
        {
          'baby_id': babyId,
          'user_id': userId,
          'label': label,
          'sort_order': i,
        }
    ]);
  }

  static Future<void> update({
    required String id,
    String? name,
    String? phone,
    String? notes,
  }) async {
    await SupabaseService.client.from('emergency_contacts').update({
      'name': JournalActions._orNull(name),
      'phone': JournalActions._orNull(phone),
      'notes': JournalActions._orNull(notes),
    }).eq('id', id);
  }

  static Future<void> add({
    required String babyId,
    required String label,
    String? name,
    String? phone,
    int sortOrder = 99,
  }) async {
    final userId = SupabaseService.userId;
    if (userId == null) return;
    await SupabaseService.client.from('emergency_contacts').insert({
      'baby_id': babyId,
      'user_id': userId,
      'label': label,
      'name': JournalActions._orNull(name),
      'phone': JournalActions._orNull(phone),
      'sort_order': sortOrder,
    });
  }

  static Future<void> delete(String id) async {
    await SupabaseService.client
        .from('emergency_contacts')
        .delete()
        .eq('id', id);
  }
}
