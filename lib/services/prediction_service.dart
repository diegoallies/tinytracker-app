/// Pattern-based predictions for "what's next" (feeding, nap).
///
/// Pure Dart on purpose: no Supabase or Flutter imports, so the logic is
/// unit-testable and reusable from any provider.
library;

class NextEventPrediction {
  /// When the next event is expected.
  final DateTime expectedAt;

  /// The typical gap used to make the prediction.
  final Duration typicalGap;

  /// How many historical gaps informed the prediction.
  final int sampleSize;

  /// 0..1 - combination of sample size and how consistent the gaps are.
  final double confidence;

  const NextEventPrediction({
    required this.expectedAt,
    required this.typicalGap,
    required this.sampleSize,
    required this.confidence,
  });

  bool isOverdue(DateTime now) => now.isAfter(expectedAt);

  Duration timeUntil(DateTime now) => expectedAt.difference(now);
}

/// Prediction for the next dose of a scheduled medication.
class NextMedicationDue {
  /// Catalog name of the medication (original casing).
  final String medName;

  /// Default dosage string to show alongside, when known (e.g. '2.5ml').
  final String? dosage;

  /// When the next dose is due.
  final DateTime dueAt;

  /// How many doses have already been given today.
  final int dosesGivenToday;

  /// Configured doses-per-day cap, when set.
  final int? frequencyPerDay;

  /// 0..1 - higher when a concrete min-interval drives the timing.
  final double confidence;

  const NextMedicationDue({
    required this.medName,
    this.dosage,
    required this.dueAt,
    required this.dosesGivenToday,
    this.frequencyPerDay,
    required this.confidence,
  });

  bool isOverdue(DateTime now) => now.isAfter(dueAt);

  Duration timeUntil(DateTime now) => dueAt.difference(now);
}

class PredictionService {
  PredictionService._();

  /// When only a daily frequency is known (no explicit interval), doses are
  /// spread across a ~12h waking day.
  static const double _wakingHoursPerDay = 12;

  /// Predict when the next dose of a scheduled medication is due.
  ///
  /// [recentDoses] are the administered-dose times from roughly the last few
  /// days (any order). Timing prefers an explicit [minIntervalHours]; failing
  /// that it spreads [frequencyPerDay] across the waking day. Returns null when
  /// the med is as-needed, has no schedule, or the daily cap is already met.
  static NextMedicationDue? predictNextDose({
    required String name,
    String? dosage,
    int? frequencyPerDay,
    double? minIntervalHours,
    bool asNeeded = false,
    required List<DateTime> recentDoses,
    DateTime? now,
  }) {
    final n = now ?? DateTime.now();

    // As-needed meds (Calpol etc.) have no schedule to predict against.
    if (asNeeded) return null;
    // Nothing to base a time on.
    if (frequencyPerDay == null && minIntervalHours == null) return null;

    final sorted = [...recentDoses]..sort();

    // Daily cap: once today's doses hit frequencyPerDay, nothing more is due.
    final startOfDay = DateTime(n.year, n.month, n.day);
    final todayCount = sorted.where((d) => !d.isBefore(startOfDay)).length;
    final freq = frequencyPerDay ?? 0;
    if (freq > 0 && todayCount >= freq) return null;

    final interval = _medInterval(minIntervalHours, frequencyPerDay);

    // No dose ever recorded -> a scheduled med is due now. Otherwise the next
    // dose lands one interval after the most recent one.
    final dueAt = sorted.isEmpty ? n : sorted.last.add(interval);

    return NextMedicationDue(
      medName: name,
      dosage: dosage,
      dueAt: dueAt,
      dosesGivenToday: todayCount,
      frequencyPerDay: frequencyPerDay,
      confidence: (minIntervalHours != null && minIntervalHours > 0) ? 0.9 : 0.6,
    );
  }

  static Duration _medInterval(double? minIntervalHours, int? frequencyPerDay) {
    if (minIntervalHours != null && minIntervalHours > 0) {
      return Duration(minutes: (minIntervalHours * 60).round());
    }
    if (frequencyPerDay != null && frequencyPerDay > 0) {
      final hrs = _wakingHoursPerDay / frequencyPerDay;
      return Duration(minutes: (hrs * 60).round());
    }
    return const Duration(hours: 4);
  }

  /// Day is 7:00-21:59 local; everything else counts as night. Babies have
  /// very different rhythms across dayparts, so gaps are bucketed by the
  /// daypart they START in and the prediction prefers gaps from the same
  /// daypart as the most recent event.
  static bool _isDayTime(DateTime t) => t.hour >= 7 && t.hour < 22;

  /// Predict the next event from past event times (e.g. feeding times).
  ///
  /// Gaps outside [minGap, maxGap] are discarded: shorter ones are usually
  /// double-logs or cluster feeds, longer ones overnight stretches that
  /// would skew a daytime prediction. Returns null when there isn't enough
  /// signal (fewer than 3 usable gaps).
  static NextEventPrediction? predictNextFromEvents(
    List<DateTime> events, {
    DateTime? now,
    Duration minGap = const Duration(minutes: 20),
    Duration maxGap = const Duration(hours: 8),
  }) {
    if (events.length < 4) return null;
    final sorted = [...events]..sort();
    final last = sorted.last;

    final dayGaps = <Duration>[];
    final nightGaps = <Duration>[];
    for (var i = 1; i < sorted.length; i++) {
      final gap = sorted[i].difference(sorted[i - 1]);
      if (gap < minGap || gap > maxGap) continue;
      (_isDayTime(sorted[i - 1]) ? dayGaps : nightGaps).add(gap);
    }

    final all = [...dayGaps, ...nightGaps];
    if (all.length < 3) return null;

    // Prefer gaps from the daypart the last event happened in.
    final preferred = _isDayTime(last) ? dayGaps : nightGaps;
    final sample = preferred.length >= 3 ? preferred : all;

    final typical = _median(sample);
    final expectedAt = _rollForward(last.add(typical), typical, now);
    return NextEventPrediction(
      expectedAt: expectedAt,
      typicalGap: typical,
      sampleSize: sample.length,
      confidence: _confidence(sample, typical),
    );
  }

  /// Advance a predicted time past slots that have already been missed.
  ///
  /// A prediction is `last + typicalGap`. Once that moment is well behind the
  /// clock (the slot was missed, or the screen has been open a while), keep
  /// adding [gap] until the prediction lands at the next slot. A half-gap of
  /// grace is kept so a genuinely-due event still shows as "around now" rather
  /// than instantly skipping to the next slot.
  static DateTime _rollForward(DateTime expectedAt, Duration gap, DateTime? now) {
    // Without a current-time reference there's nothing to roll past — keep the
    // raw last+gap prediction (also what the pure unit tests rely on).
    if (now == null || gap <= Duration.zero) return expectedAt;
    final grace = Duration(minutes: gap.inMinutes ~/ 2);
    var next = expectedAt;
    var guard = 0;
    while (now.difference(next) > grace && guard < 1000) {
      next = next.add(gap);
      guard++;
    }
    return next;
  }

  /// Predict the next nap from completed sleep sessions using awake windows
  /// (time between waking up and the next sleep start).
  static NextEventPrediction? predictNextNap(
    List<({DateTime start, DateTime end})> sessions, {
    DateTime? now,
    Duration minWindow = const Duration(minutes: 15),
    Duration maxWindow = const Duration(hours: 6),
  }) {
    if (sessions.length < 3) return null;
    final sorted = [...sessions]..sort((a, b) => a.start.compareTo(b.start));

    final windows = <Duration>[];
    for (var i = 1; i < sorted.length; i++) {
      final awake = sorted[i].start.difference(sorted[i - 1].end);
      if (awake < minWindow || awake > maxWindow) continue;
      windows.add(awake);
    }
    if (windows.length < 2) return null;

    final typical = _median(windows);
    final lastWake = sorted.last.end;
    final expectedAt = _rollForward(lastWake.add(typical), typical, now);
    return NextEventPrediction(
      expectedAt: expectedAt,
      typicalGap: typical,
      sampleSize: windows.length,
      confidence: _confidence(windows, typical),
    );
  }

  static Duration _median(List<Duration> values) {
    final sorted = [...values]..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[mid];
    return (sorted[mid - 1] + sorted[mid]) ~/ 2;
  }

  /// Confidence grows with sample size (saturating at 8) and shrinks with
  /// spread (interquartile range relative to the median).
  static double _confidence(List<Duration> sample, Duration typical) {
    if (typical.inMinutes <= 0) return 0;
    final sorted = [...sample]..sort();
    final q1 = sorted[((sorted.length - 1) * 0.25).floor()];
    final q3 = sorted[((sorted.length - 1) * 0.75).ceil()];
    final spreadRatio =
        (q3 - q1).inMinutes.abs() / typical.inMinutes; // 0 = perfectly regular
    final sizeScore = (sample.length / 8).clamp(0.0, 1.0);
    final regularityScore = (1 - spreadRatio / 2).clamp(0.0, 1.0);
    return (0.4 * sizeScore + 0.6 * regularityScore).clamp(0.0, 1.0);
  }
}
