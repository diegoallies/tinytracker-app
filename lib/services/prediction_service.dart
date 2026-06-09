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

  /// 0..1 — combination of sample size and how consistent the gaps are.
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

class PredictionService {
  PredictionService._();

  /// Day is 7:00–21:59 local; everything else counts as night. Babies have
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
    return NextEventPrediction(
      expectedAt: last.add(typical),
      typicalGap: typical,
      sampleSize: sample.length,
      confidence: _confidence(sample, typical),
    );
  }

  /// Predict the next nap from completed sleep sessions using awake windows
  /// (time between waking up and the next sleep start).
  static NextEventPrediction? predictNextNap(
    List<({DateTime start, DateTime end})> sessions, {
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
    return NextEventPrediction(
      expectedAt: lastWake.add(typical),
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
    final q1 = sorted[(sorted.length * 0.25).floor()];
    final q3 = sorted[((sorted.length - 1) * 0.75).floor()];
    final spreadRatio =
        (q3 - q1).inMinutes.abs() / typical.inMinutes; // 0 = perfectly regular
    final sizeScore = (sample.length / 8).clamp(0.0, 1.0);
    final regularityScore = (1 - spreadRatio / 2).clamp(0.0, 1.0);
    return (0.4 * sizeScore + 0.6 * regularityScore).clamp(0.0, 1.0);
  }
}
