import 'package:flutter_test/flutter_test.dart';
import 'package:tinytrack_app/services/prediction_service.dart';

void main() {
  group('PredictionService.predictNextFromEvents', () {
    test('returns null with too little history', () {
      final events = [
        DateTime(2026, 6, 9, 8),
        DateTime(2026, 6, 9, 11),
      ];
      expect(PredictionService.predictNextFromEvents(events), isNull);
    });

    test('predicts last event + median gap for regular feedings', () {
      // Every 3 hours during the day.
      final events = [
        DateTime(2026, 6, 9, 8),
        DateTime(2026, 6, 9, 11),
        DateTime(2026, 6, 9, 14),
        DateTime(2026, 6, 9, 17),
        DateTime(2026, 6, 9, 20),
      ];
      final p = PredictionService.predictNextFromEvents(events);
      expect(p, isNotNull);
      expect(p!.typicalGap, const Duration(hours: 3));
      expect(p.expectedAt, DateTime(2026, 6, 9, 23));
      expect(p.confidence, greaterThan(0.5));
    });

    test('ignores double-log gaps shorter than minGap', () {
      final events = [
        DateTime(2026, 6, 9, 8),
        DateTime(2026, 6, 9, 8, 5), // accidental double log
        DateTime(2026, 6, 9, 11),
        DateTime(2026, 6, 9, 14),
        DateTime(2026, 6, 9, 17),
        DateTime(2026, 6, 9, 20),
      ];
      final p = PredictionService.predictNextFromEvents(events);
      expect(p!.typicalGap.inMinutes, closeTo(180, 6));
    });

    test('irregular gaps lower confidence vs regular gaps', () {
      final regular = PredictionService.predictNextFromEvents([
        for (var i = 0; i < 6; i++) DateTime(2026, 6, 9, 8 + i * 2),
      ])!;
      final irregular = PredictionService.predictNextFromEvents([
        DateTime(2026, 6, 9, 8),
        DateTime(2026, 6, 9, 8, 40),
        DateTime(2026, 6, 9, 13),
        DateTime(2026, 6, 9, 14),
        DateTime(2026, 6, 9, 20),
        DateTime(2026, 6, 9, 21),
      ])!;
      expect(regular.confidence, greaterThan(irregular.confidence));
    });

    test('unsorted input is handled', () {
      final events = [
        DateTime(2026, 6, 9, 14),
        DateTime(2026, 6, 9, 8),
        DateTime(2026, 6, 9, 20),
        DateTime(2026, 6, 9, 17),
        DateTime(2026, 6, 9, 11),
      ];
      final p = PredictionService.predictNextFromEvents(events);
      expect(p!.expectedAt, DateTime(2026, 6, 9, 23));
    });
  });

  group('PredictionService.predictNextNap', () {
    test('predicts next nap from awake windows', () {
      final sessions = [
        (start: DateTime(2026, 6, 9, 9), end: DateTime(2026, 6, 9, 10)),
        (start: DateTime(2026, 6, 9, 12), end: DateTime(2026, 6, 9, 13)),
        (start: DateTime(2026, 6, 9, 15), end: DateTime(2026, 6, 9, 16, 30)),
      ];
      // Awake windows: 2h and 2h → next nap 2h after last wake (16:30).
      final p = PredictionService.predictNextNap(sessions);
      expect(p, isNotNull);
      expect(p!.expectedAt, DateTime(2026, 6, 9, 18, 30));
    });

    test('returns null with too few sessions', () {
      final sessions = [
        (start: DateTime(2026, 6, 9, 9), end: DateTime(2026, 6, 9, 10)),
        (start: DateTime(2026, 6, 9, 12), end: DateTime(2026, 6, 9, 13)),
      ];
      expect(PredictionService.predictNextNap(sessions), isNull);
    });

    test('overdue detection works', () {
      final p = NextEventPrediction(
        expectedAt: DateTime(2026, 6, 9, 12),
        typicalGap: const Duration(hours: 3),
        sampleSize: 5,
        confidence: 0.8,
      );
      expect(p.isOverdue(DateTime(2026, 6, 9, 13)), isTrue);
      expect(p.isOverdue(DateTime(2026, 6, 9, 11)), isFalse);
      expect(p.timeUntil(DateTime(2026, 6, 9, 11)), const Duration(hours: 1));
    });
  });
}
